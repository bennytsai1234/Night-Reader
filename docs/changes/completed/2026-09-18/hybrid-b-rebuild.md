# Hybrid B 責任重建 — production 實作與驗證

日期：2026-09-18。工作分支：`reader-hybrid-b-rebuild`。

本次依前一輪責任圖修改正式原始碼；不是將140整包覆蓋，也沒有建立 Reader V3。保留 native CustomScrollView／Sliver、ChapterBlock、TextPreprocessor、ui.Paragraph、LayoutPump、MeasurementStore、DocumentIndex／Fenwick 與 ReaderV2Location。

## 來源與範圍

Git 分支沿用128與考古紀錄的祖先。為避免把產品回退到7月，周邊 App、UI、設定、來源服務、工具鏈與既有回歸測試保留已審查上界 `6a4de1ab27e26ca56df1fc133c08d8bb988b54bc` 的現行檔案；Hybrid orchestration 按責任重建。相對該上界，實作差異集中在20個 production／test 檔案，而非相對128的所有檔案都重新設計。

保留140的增量 Fenwick、Sliver 幾何、TextBox capture／restore、placeholder縮排、B2與em-grid，以及後期真正的內容身分／UTF-16重映射、語意進度、TTS內容世代、positioned→ready→persisted、完整正文取得修復。沒有復活已移除的翻譯、標點字型或舊正文引擎。

## 已實作的責任修復

| 原問題 | 新 owner／契約 | 使用行為差異 |
|---|---|---|
| 整章切行 probe 繞過 queue；多次 await 可重取局部預算 | 切行與 drawable 同屬 LayoutPump 工作佇列與 frame credit，需求改變一起撤銷 | 拖曳期間仍能供應內容，跳章不繼續消費已不需要的舊工作 |
| 畫面所需 Paragraph 被 LRU／replacement 提前 dispose | Render、視口準備、命令各自持有 ParagraphLease；最後引用釋放才 dispose | 容量很小、重繪、替換與 detach 不再依靠 restore pin／一次性 waiter 時序 |
| contiguous ready block 因落入 visible 區而不能使用 | Admission 只維護 exact 連續邊界；既有前綴座標不移動 | 已可畫內容能即時進入原生 scroll world；不再以 readiness 調摩擦 |
| raw eviction 同步刪除仍有效的 scroll geometry；回讀重新切塊 | DocumentIndex 與不含正文的 ChapterLayoutPlan 擁有 active 幾何／切分 | 跨章往返可逐出正文而不重設文件座標；adaptive cost estimate 不改寫舊 BlockKey |
| 首屏成功取決於 guaranteed window／背景queue清空 | 只等待實際首屏、anchor與原生定位，然後由 runtime ready／persist | 遠端預載被阻塞時，已定位的首屏仍能完成 |
| 遠跳下載中，舊視口把需求拉回原章 | 直接使用既有 Runtime operation token／targetLocation 接管需求 | 新命令從開始就擁有目標，不另加觀察旗標 |
| 同名章節被誤當同一內容 | 移除 title-only 刪除，保留 URL identity 去重 | 相鄰同名但不同 URL 的章節不會僅因名稱相同而消失 |

已移除 screen 的 `_enqueued`、restore ticket、restore pinning、restore-prefetch barrier、user-scroll-observed barrier、prefetch generation 與舊 desired／discard rollback 鏈。保留不同事實所需的合法狀態：operation identity、namespace、當前需求、native positioning、手勢與通知合併。

## 已實際重現及驗證

本地環境由固定 Flutter 3.47.0／Dart 3.13.0 與實際套件 cache 建立，沒有修改第三方套件來繞過測試。SQLite native library 從同版本正常 build hook 取得並核對其雜湊。

- `flutter analyze --no-pub`：No issues found。
- `flutter test --no-pub --reporter expanded`：**1025 passed、84 skipped、0 failed**，退出碼0。84是既有 skip，不列為已執行通過。
- 新遠跳 pending-owner 回歸先失敗：目標第9章的需求起點應為7，實際被舊畫面留在0；修正後通過。
- title-only 去重反例先失敗：六個不同URL章節只剩三個；移除不成立的身分推論後通過。
- 真正 pointer drag 前進及返回、跨 raw eviction、Paragraph cache capacity=2：檢查既有 DocumentIndex reset generation、可見 Paragraph 完整與 residency 範圍。
- 小 cache 的 mounted consumer／replacement／cache.dispose／render.detach，以及 blocked speculative load 不阻塞首屏均有聚焦回歸。
- 保留的 visual-line segmentation、semantic末行補償、em-grid、樣式／旋轉／繁簡／換源回歸一起執行。

測試改成等待實際 frame 完成定位，不再把原本過早完成的 Future 當規格；舊 pin／friction／barrier 契約測試改驗證真正的 consumer lifetime、native motion 與需求失效。未加入大量 generated sweeps、monkey或benchmark框架。

## Git 與 CI 證據邊界

本地完整測試對應本次 production／test tree。離線環境的 Git 物件以內容雜湊核對後提交；只有正式 source 已成為 commit，獨立的 Reader V2 workflow 才 checkout 執行 analyze、tests及Android。驗證步驟不注入程式、不套補丁，並檢查 `git diff --exit-code`。臨時工具鏈／傳輸 workflow 不保留在交付 tree。

下節補上中斷後讀回確認的獨立 CI 結果。上方1025／84是實作階段的本地完整測試紀錄；下方298是另一輪 CI 聚焦測試，兩者不可混算，也不表示接續檢查時重新執行了本地完整測試。

## 獨立 CI 與 Android 驗證結果

**已確認：**production commit 為 `1cf0d5d1ce993c7d868c77204eb153e26936cc76`，tree 為 `03d6b38291a4b19db9c1842b14017a6f95f4b5d8`。[Reader V2 run 35306106586](https://github.com/bennytsai1234/Night-Reader/actions/runs/35306106586) 的 head SHA 與 `reader-checks`、`reader-android` 兩份產物內的 `SOURCE.txt` 完全一致。

執行時間：2026-09-18 04:12:53–04:23:25 UTC，即台灣12:12:53–12:23:25。run、check job `105478500983`、android job `105478923838` 均為 `completed / success`。兩個 job 的 `Verify validation did not modify tracked source` 步驟也成功。

| 檢查 | 讀回的實際結果 |
|---|---|
| 全專案 `flutter analyze` | `No issues found! (ran in 22.0s)` |
| Reader／換源／字元轉換聚焦測試 | `00:53 +298: All tests passed!` |
| Android debug APK | `Built build/app/outputs/flutter-apk/app-debug.apk` |
| Pixel 6 profile、API35、x86_64模擬器旅程 | 一個完整journey通過；框架輸出 `00:43 +2: All tests passed!` 含tearDownAll，不計成兩個獨立旅程 |
| 受測來源未被改寫 | 兩個job均通過 `git diff --exit-code` |

聚焦測試的命令與範圍：

```bash
flutter test test/features/reader_v2 \
  test/core/services/source_switch_service_test.dart \
  test/core/services/source_switch_progress_test.dart \
  test/core/engine/reader/chinese_text_converter_length_test.dart \
  --reporter expanded
```

Android旅程使用正常TXT匯入管線建立前言與三章，經實際目錄widget跳到索引2→0→1，拖曳220 logical px並保存，核對DB的章節／字元位置，返回書架再重開。重開核對章節與字元位置相同、`visualOffsetPx` 誤差不超過0.1 logical px；各settled檢查可見block非空、連續且無缺失Paragraph。

生命週期部分是測試binding注入 `paused/resumed`，**不是**作業系統Home鍵切背景或process kill驗證。Android本輪也沒有操作旋轉、TTS或高速長時間滾動；不能拿host測試代替這些裝置情境。

已檢視 `reader-after-reopen.png`（415358 bytes）：最後截圖有連續正文與進度列，沒有首屏整片空白或錯誤畫面。這是一張重開後的截圖，不是對整段動畫每一幀的視覺驗證。

**真實警告：**測試通過且截圖保存之後，清理階段 `adb uninstall` 回報 `Failure [DELETE_FAILED_INTERNAL_ERROR]`／`Failed to uninstall app`。Android job仍成功；紀錄保留此清理失敗，不宣稱整份log零錯誤。沒有為這個測後卸載失敗修改Reader production或重跑已通過情境。

產物已下载並以SHA-256與GitHub API digest核對相同：

| Artifact | ID | SHA-256 |
|---|---|---|
| reader-checks | 10530534197 | `eaad4097f5d641fbe149a935aba3d447d01415bf2009a8a0d5a56b28f6fa969f` |
| reader-android | 10530874404 | `1b19d029a4231599f52904222c35aac89ff3e67352e26a4a0eea7512ac19707a` |

本次接續提交只補驗證紀錄，沒有再改production／tests／workflow；受測程式仍是上述1cf0d5d。`main` 讀回仍為 `6a4de1ab27e26ca56df1fc133c08d8bb988b54bc`。

## 尚未驗證及保留限制

尚未驗證：實體手機、120Hz／P99、高速連續閱讀的裝置效能，缺本次實體裝置量測。host回歸只能證明所執行情境的契約，不能宣稱所有裝置永不卡頓。

Active文件的精確量測與text-free切分 metadata 隨已訪問範圍累積，直到明確文件重建；沒有宣稱全書常數記憶體。單一visual line若超過目標字數，仍以正確行界為最小transaction。

畸形來源在不同URL提供相同正文的問題沒有被title-only刪除規則可靠解決，本次不再以猜測身分造成漏章。相同URL仍去重；不同URL的真正重複需可靠來源／內容身分，本次未宣稱已全面識別。

沒有修改 main、沒有 release tag、沒有發布 APK。
