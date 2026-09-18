# Hybrid B 重建 — 提交選材索引

對照 [架構重審](architecture-review.md)。這是 72 筆 production／依賴判定的索引，不是已 cherry-pick 清單，也不是逐行審核全部 284 個祖先提交的宣稱。完整五問題紀錄與 284 筆 inventory 另以本次對話附件交付。每顆提交都必須按實際 source hunk 移植，不能只看共作者、日期或標題。

## Reader 核心：35 筆

| 提交 | 問題與處置 |
|---|---|
| 8f3d067 | 保留 TextBox.top capture/restore 互逆、縮小進度通知；contiguous edge 可進 cache 是有價值的修正，visible gate 不是最終契約。 |
| b8cba28 | 保留正文清理、UTF-16 與章名／文字切割的正確性；offset 必須對應真正的 displayText。 |
| c2ae3eb | 保留增量 Fenwick、有序 range 查詢與移除不必要 saveLayer 的熱路徑修復。 |
| 95353df | 保留 custom sliver 與 Fenwick geometry；BudgetGovernor/friction/lead deficit 拆開判定，不整包恢復。 |
| ba7df63 | 保留 reset/sliver lifecycle、穩定 fingerprint 與已確認的成本修正；不把多次 pump 的局部 budget 當成 frame 全域上限。 |
| b283a68 | 保留資訊列呈現，但章內進度改以 semantic position，不用局部 admitted extent。 |
| 5a9b2b1 | 首屏缺正文是真問題；以 visible consumer 存活期審 pin/waiter，不直接刪，也不原樣奉為契約。 |
| 7faf037 | 雖帶 release 性質仍有 typography 實作；逐 hunk 留有效排版，不因標題忽略。 |
| fbdd8c1 | 保留縮排 placeholder 與文字 offset 對應修正。 |
| 7913f82 | 保留 B2 最後字元所需 headroom 的 off-by-one 修正。 |
| 16b0f64 | 保留有上下文的標點／引號處理；不要只按字元孤立替換。 |
| 0c8b01a | 保留 B2/引號底層修正；成本估計與 telemetry 不是無界任務的解法。 |
| e8cee0a | 保留 normalization/typography 的有效成果；後來已撤除的翻譯功能不復活。 |
| f5e0e21 | 保留 em-grid、字寬、padding 與 overlay 幾何對齊；不是重做 motion engine 的理由。 |
| 30cd48d | 保留單側引號的上下文正規化修正。 |
| b6e138b | 保留已成立的字形 normalization 問題，確認 offset/內容 identity 一起更新。 |
| 716c864 | 保留已完成的字體／翻譯能力移除，不為參考 140 復活舊依賴。 |
| 2aa673f | 混合功能修復：保留手勢、錯誤、持久化；設定 debounce/dirty state 與核心排版 ownership 分開。 |
| 1316afe | 保留 block clip 的合法繪製邊界；clip 不能當成 metrics 正確的證明。 |
| fd6d3a4 | 保留 stale metrics 問題；先修 content/segmentation identity，必要重排才做 anchor-aware 幾何變換，不能只覆寫 height。 |
| b3cdfd7 | 閱讀時間 controller 與序列化 DB 寫入是產品功能，不是排版補丁。 |
| 168cd64 | route visibility 與 app foreground 是獨立真實輸入；保留合法狀態。 |
| ff75838 | 保留 TTS highlight 的 reader palette；顏色更新不應驅動幾何失效。 |
| 1160999 | 保留連續段落問題；不原樣帶回整個自然段的無界同步 layout；拆 raw eviction 與 semantic invalidation。 |
| e504ed6 | 保留 native sliver callback 可達輸入及 Paragraph lifetime 修復；不能看見 fallback 1.0 就刪。 |
| 7f9f339 | 標題含 test 仍改 production。保留 TTS/UTF-16/完整頁距問題，不保留 obsolete HybridEnsureGate。 |
| dc45619 | heartbeat 為 kDebugMode；不要當成 release 狀態爆炸的直接證據。 |
| 466ddae | 保留 combinedText 記憶化等確定性工作減量；被動觀測不是修復框架。 |
| 432a5d8 | 保留 content remap、line-height identity 等 source hunks；不帶入整套 restore/prefetch barrier、quiet-frame dispatch 與 oracle。 |
| 9c845ee | 保留過期 speculative work 問題；pending/dedup/cancel 收回 Pump，不複製 screen _enqueued + discard 回滾。 |
| c067e5d | 保留 dead-code 清理；區分 debug instrumentation、release 行為與總行數。 |
| 5e33d93 | 保留 targetLocation、positioned→ready→persisted、binding-aware continuation、pending 去重、segmentation disk identity；不恢復 CI source injection。 |
| 973fe12 | 合併曾帶回已刪除 _enqueued/計數欄位引用；不是可獨立搬的成熟化單位。靜態不一致不等於本次跑过該版 analyzer，也不是最新仍存缺陷。 |
| f73bc89 | 保留 content-aware location、consumer 導向 residency、完整頁距、visual-line transaction；切行旁路必須納入 Pump 排程 owner。 |
| ed529eb | 保留 charOffset/全文長度進度、resident-based demand、identity/TTS/換源一致化；仍有 barrier/drag hard stop，不能宣稱已乾淨。 |

## Reader 功能層：19 筆

| 提交 | 問題與處置 |
|---|---|
| 85162fb | 保留章內 scrub 互動，接 semantic progress/target。 |
| b71d1ae | 保留目前章節主題色。 |
| 3a37516 | 保留排版／進階文案，不以考古回退 UI。 |
| 3eb0e2c | 保留 error 狀態的使用者手動重試／換源／返回。 |
| 0b09358 | 保留外觀設定文案。 |
| 406f0d0 | 保留規則保存失敗與 saving lifecycle。 |
| 153d5e2 | 保留規則讀取失敗與 empty 的區分。 |
| 0cab940 | 保留 helper 的有效 BuildContext 參數。 |
| 0b0bffd | 保留換源不丟进度的問題；快照應取自 flush 完成後，不是 await 前的舊值。 |
| a7c7c6d | 保留規則 sheet 的 loading/error/empty 與 toggle 失敗恢復。 |
| 0df79f6 | 保留部分保存失敗的資料一致性問題；補償回寫不是原子交易。 |
| 4a83df4 | 保留先退出 sheet、再替換 Reader route 的 owner 修復。 |
| 9102f39 | 沿用現行 UI spacing/typography。 |
| b35a2c2 | 保留正文／選單各自的日夜偏好。 |
| 595142f | 保留自訂 menu palette。 |
| 9f29130 | 保留資訊列區域色彩。 |
| 4954f16 | 保留正文和選單明暗模式解耦；屬合法產品狀態。 |
| e796448 | 保留 return await 將非同步例外留在本層 catch；SDK 升級與架構取捨分開驗證。 |
| b4edec9 | 保留共享 AppBottomSheet/AppStateView，不另創 UI。 |

## Reader 外的上游與依賴：18 筆

| 提交 | 問題與處置 |
|---|---|
| 86a53d7 | 已移除的 legacy 模型不因回到舊基線復活；未把所有刪除都聲稱完成全專案可達性證明。 |
| 3b13745 | 保留 CacheManager.get memory deadline；不推論所有 getFromMemory 入口已覆蓋。 |
| 9d0b7f4 | 保留 TTS voice 可用性／平台結果與設定重套；本次未跑裝置音色驗證。 |
| 3f3120b | 保留同 DB transaction 的換源原子遷移。 |
| 671e609 | 保留傳入 ChapterDao 的 ownership；不同 DB 注入契約仍需核對。 |
| 71ace07 | 新完整正文取得器：未取完達頁數上限要失敗，不可回傳截斷成功。此顆尚未接 service。 |
| 64ad7c6 | 實際將 BookSourceService 接到完整取得器，與 71ace07 一起保留。 |
| 8ba7698 | 保留 bounded concurrency、去重與 batch 順序；所有分頁仍須成功。 |
| 3549185 | 保留 pageConcurrency 參數透傳，完成並發接線。 |
| 0900fe1 | 保留全域閱讀偏好與 Reader 排版入口分工。 |
| 42591b2 | 保留 BookDao.appDatabase，交易需使用 DAO 真正所屬 DB。 |
| 358946c | 不原樣採用為測試缺 DI 而引入的 silent save return；optional read fallback 和寫入成功不同。 |
| cdf335e | 保留點擊區域設定 load/save 錯誤及局部寫入互斥；不是 Reader gate。 |
| 08c7ea2 | 保留閱讀偏好 load failure 的結束狀態與手動重試。 |
| ac228bb | 保留畸形來源重複章節問題，但不接受相鄰 title 相等就刪除的通用 identity 判定。 |
| 1a68fad | 保留閱讀時間所需 appRouteObserver。 |
| 0f2333a | 保留 observer 接入 MaterialApp 的實際接線。 |
| 8b4f3b9 | 保留 BookOpenRoute 的 ReadTimeScope。 |

## CI source provenance：8 筆

`6123e91` 匯出歷史、`69e6400` baseline checks、`06d256d` ownership workbench、`b96512b` 編碼 payload、`7f5825c` checksum/apply、`f5130d0` 保存受測 source/log、`cfec289` 在 checkout 改 navigation 並插入測試、`a3e13e8` 保留退出碼及 Android journey。

這段歷史證明：只篩 lib/ 修改會漏掉真正被 CI 執行的 source 變換。`5e33d93` 才將修復直接落進 production 並移除 transport。本次重建不帶回 payload/apply，也不將歷史測試結果當成本次執行結果。

## 本次交付邊界

本分支只新增審查文件並移除本次臨時匯出 workflow。沒有 production cherry-pick、重寫、測試新增或 Reader 行為變更。完整實作與執行驗證仍未完成。
