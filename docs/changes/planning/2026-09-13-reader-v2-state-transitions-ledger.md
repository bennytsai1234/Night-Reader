# Reader V2 狀態轉換路徑 — Evidence Ledger

本批次的共用證據帳本，涵蓋樣式變更、旋轉／viewport、簡繁切換、換源四條狀態轉換路徑。

**這份 ledger 與「Reader V2 120Hz / 排版穩定性」批次的 ledger 是分開的，不要混用。**

規則：

- 每個假設一列，**包含負面結果**。
- 「結論」欄只寫實際觀測到的東西；推測寫進「備註」。
- 每個迭代結束就更新對應路徑的表。

---

## 起始事實（Planner 於 repo 實際查證）

| # | 事實 | 依據 | 對本批次的意義 |
|---|---|---|---|
| S-01 | `ReaderV2Style` 沒有 fontFamily 欄位 | `lib/features/reader_v2/layout/reader_v2_style.dart` 的完整欄位清單 | **字型不是可變設定**，不在本批次範圍。若未來要支援，`layoutSignature` 需要補這一維 |
| S-02 | `BlockFingerprint.fontFamilySignature` 預設 `'system'`，全 repo 無呼叫端傳入其他值 | `lib/features/reader_v2/hybrid/core/hybrid_types.dart:105`；`rg "fontFamilySignature:"` 只有型別內部一處 | 同上。hybrid 層已預留維度但未接上 |
| S-03 | `readStyleFor` 把 `bold` 寫死為 `false` | `lib/features/reader_v2/features/settings/reader_v2_settings_controller.dart:67` 的 `ReaderV2Style(... bold: false ...)` | `layoutSignature` 中的 `style.bold` 是死輸入。**記錄不修**（feature freeze） |
| S-04 | `syncRuntimeConfiguration` 在 `LayoutBuilder.builder` 內每次 build 都被呼叫 | `lib/features/reader_v2/screen/reader_v2_page.dart:209`（LayoutBuilder）、`:215`（readStyleFor 依 `MediaQuery.paddingOf`）、`:221`（syncRuntimeConfiguration） | 樣式與旋轉共用同一觸發點 |
| S-05 | signature 不同就排一次 post-frame `unawaited(applyPresentation)`，無 debounce、無 coalesce | `lib/features/reader_v2/screen/reader_v2_controller_host.dart:139-146` | **T3 的主要假設來源**：inset／旋轉動畫期間逐幀新 signature 會造成重排風暴 |
| S-06 | `applyPresentation` 在 hybrid 路徑會 `beginPresentation(layoutGeneration + 1)` 後 `_positionHybridViewport` | `lib/features/reader_v2/session/reader_v2_runtime.dart:298-328` | 每次觸發都是一次世代推進與重新定位 |
| S-07 | `setChineseConvert` 只 bump `_contentSettingsGeneration`，由 host 轉成 `reloadContentPreservingLocation` | `reader_v2_settings_controller.dart:219-225`；`reader_v2_controller_host.dart:147-153` | 簡繁走的是 content reload，不是 presentation |
| S-08 | `reloadContentPreservingLocation` 先 capture location，再 `clearContentCache()`，再 `beginContentReload(layoutGeneration + 1)` | `reader_v2_runtime.dart:361-380` | **T4 的錨點風險**：capture 到的 `charOffset` 是轉換**前**文本的偏移 |
| S-09 | Reader 的換源走 `Navigator.pushReplacement(BookOpenRoute(...))`，建立全新 session，**不是**就地 reload | `reader_v2_page.dart:386-411` | T5 的風險面是進度遷移與 session 拆建競爭，不是排版失效 |
| S-10 | `_handleChangeSourceSelected` 先 `await _host.flushProgress()` 再 `resolveSwitch` / `persistSwitch`；失敗時 catch 後回傳訊息並停在舊 session | `reader_v2_page.dart:413-452` | T5 要驗的競爭與失敗路徑 |
| S-11 | `textColor` 變更**不 bump epoch**，設計上會有「tint 過渡、逐塊收斂到直繪」的瞬態 | `lib/features/reader_v2/hybrid/hybrid_reader_screen.dart:253-259` 及其註解 | **主題切換期間短暫缺 paragraph 是設計行為**，不得判成 bug |
| S-12 | `SourceSwitchService` 的 service 層測試已完備 | `test/core/services/source_switch_service_test.dart`（標題對齊、章節較少時 clamp、內容不可讀、無目錄、找不到書源、persist 回滾）、`test/core/services/source_switch_progress_test.dart:51`（章節內位置帶到新來源） | **T5 不得重建這些**。缺口在頁面層編排 |
| S-13 | 既有 runtime 壓力測試只驗「交錯後收斂為 ready」，未驗轉換前後語意位置是否保住 | `test/features/reader_v2/reader_v2_runtime_stress_test.dart:106` | T2 的缺口定義 |
| S-14 | `layoutSignature` 的組成 | `lib/features/reader_v2/layout/reader_v2_layout_spec.dart:138-164`：viewport w/h、contentWidth/Height、cellWidth、fontSize、lineHeight、letterSpacing、paragraphSpacing、padding×4、textIndent、bold、lastLineSpacingCompensation、CJK 特徵簽章 | T2 逐項驗證的依據；任何一維漏掉都會造成舊排版被誤用 |

---

## T1 測試地基 — seam 與觀測點

| 路徑／能力 | 處理方式 | 實際驗證與後續風險 |
|---|---|---|
| 語意保位 anchor | 新增 `test/features/reader_v2/reader_v2_state_transition_test_support.dart`。`ReaderAnchorProbe` 取章節內句子 anchor；`expectReaderAnchorPreserved` 預設 exact，另以 `ChineseTextConverter` 提供 `equivalentText`（canonical convert type 1/2）。 | helper 自我測試已驗證：位置跑到第三句會丟出 mismatch 並包含 before/after 實際文字；同句 offset 改變不誤報；簡繁文字在 equivalent 模式通過、exact 模式拒絕。T2/T3 沿用 exact，T4 沿用 equivalent。 |
| 樣式 | 沿用 `ReaderV2SettingsController.setFontSize`，透過既有 `ReaderV2ControllerHost.syncRuntimeConfiguration` 進入 `ReaderV2Runtime.applyPresentation`；未新增樣式產品 API。 | T1 smoke 已觀測單一字級變更 `applyPresentation=1`、`reload=0`。逐維 layoutSignature 與語意判定交給 T2。 |
| viewport／inset | 沿用 `LayoutBuilder` 的 `Size`／`MediaQuery.paddingOf` 輸入；widget test 以外層 `MediaQuery` 與 constraints 連續送入 `Size(420,720)`、top/bottom inset，仍由 `specFromStyle`／`syncRuntimeConfiguration` 驅動 `applyPresentation`。 | T1 已驗證尺寸變更觸發一次呈現轉換。現有 page 對 top/bottom info 設為 externally reserved，因此單獨改 inset 不一定改 layout signature；這是 T3 必須明確區分的 inset-only 覆蓋風險，本 package 不修。 |
| 簡繁 reload | 沿用 `ReaderV2SettingsController.setChineseConvert` 與 host 的 content-settings generation → post-frame `reloadContentPreservingLocation`；測試以有 deadline 的 ready 輪詢等待收斂，不靠固定 pump 次數。 | T1 smoke 已觀測 `reloadContentPreservingLocation=1`，並以 equivalent anchor 驗證位置語意。T4 負責長度實測、重映射與四層快取。 |
| 換源 fake | `ReaderV2Page` 新增 `@visibleForTesting` nullable `sourceSwitchService` 注入，以及 page state 的 `debugSelectSourceForTesting` 入口；`test/.../reader_v2_state_transition_test_support.dart` 提供可控制成功、失敗與延遲的共用 `FakeReaderV2SourceSwitchService`；null 時維持原本 `SourceSwitchService()` 建構與 UI 流程。 | T1 smoke 在真實 page state 上注入共用 fake，實際觀測 `resolveSwitch=1`、`persistSwitch=1` 且成功。T5 負責 flush／失敗／session 拆建競爭；T1 未發現或修復 production bug。 |
| transition 計數 | `ReaderV2Runtime` 新增兩個 `@visibleForTesting` nullable observer：`debugOnApplyPresentationTriggered`、`debugOnReloadContentTriggered`；只在 `kDebugMode` 且 test 明確設定 callback 時呼叫，不建立正式路徑 counter/history。 | smoke 已驗 observer 預設為 null；未注入時 production 路徑不會建立觀測資料，profile/release 會由 `kDebugMode` gate 排除 dispatch。T3 可用它量連續 viewport 觸發，T4/T5 可用 reload／頁面流程觀測。 |

## T2 樣式變更 — 迭代紀錄

| 迭代 | 變更維度 | 觀察到的問題 | 分類 | 根因 | 修復 | regression test | 重驗 |
|---|---|---|---|---|---|---|---|
| 1 | fontSize、lineHeight、letterSpacing、paragraphSpacing、textIndent、paddingLeft/right、lastLineSpacingCompensation；兩維組合；scroll 未 settle；cellWidth 鎖／未鎖 | 七個逐維 case 各觀測 exact anchor 保留、generation +1、resolver metrics 只留下新 signature、`applyPresentation=1`、`reload=0`；組合為一次重排；鎖寬與未鎖寬 content width 均符合 contract；未 settle 的第一版測試因未先同步 moving location 而回到 charOffset 0 | test（未 settle 第一版）／production（rapid 另列） | 未 settle 第一版是 test harness 沒有先把模擬 scroll 位置寫入 runtime；不是 runtime 觀測 | 修正測試 seam：先 `updateVisibleLocation(movingLocation)`，再以 T1 capture observer 模擬未 settle | `reader_v2_style_change_test.dart` exact anchor case；重跑通過 | 13 項 T2 test 全綠（後續補 dead-input test 後為 14） |
| 2 | rapid style：同一 frame 依序送 fontSize 19 → 20 → 22 | 修復前實際 observer 為 `applyPresentation=3`；中間兩個 signature 各啟動 transition，最後 generation 會留下多代工作 | production | `ReaderV2ControllerHost.syncRuntimeConfiguration` 每次 signature 差異都直接註冊 post-frame callback，沒有 coalesce | host 保存最新 pending spec，單一 frame 只排一個 callback；callback dispatch 最新 spec | `reader_v2_style_change_test.dart`「連續快速 style 變更只留下最後 signature 與世代」 | 修復後實際為 `applyPresentation=1`、最後 `fontSize=22`、generation +1、cache signature 等於最後 signature；T2 suite 全綠 |
| 3 | lineHeight 邊界：0.5／1.0 → 1.2；4.0／3.5 → 3.0；direct `fromViewport` clamp | 修復前 direct spec 實際得到 `style.lineHeight=0.5`（對合法 1.2），signature 不一致；settings path 已能 normalize | production | `ReaderV2LayoutSpec.fromViewport` 只在 engine getter 套 clamp，沒有把 normalized value 放進 spec/signature；鎖寬 copy 也沿用 raw style | `fromViewport` 先 normalize lineHeight，再以 normalized style 建立 spec 與 locked style | `reader_v2_style_change_test.dart`「direct lineHeight input also uses the clamp contract」及 clamp transition test | 修復後 0.5 與 1.2、4.0 與 3.0 各自 signature 一致；等價輸入不重排；suite 全綠 |
| 4 | 完整 S1～S3 重跑 | 每一維三項均通過；lineHeight clamp、cellWidth locked/unlocked、兩維一次重排、rapid 最終 signature、未 settle exact anchor 均通過；bold/fontFamily 明確 skip | pass | 無新增問題 | 無 | 所有 T2 regression／matrix tests | `flutter test test/features/reader_v2/reader_v2_style_change_test.dart --reporter compact`：14 tests passed；既有 T1/layout/em-grid 基線另見報告 |

## T3 旋轉／viewport — 迭代紀錄

| 迭代 | 假設 | 觀察（applyPresentation 觸發次數／世代推進次數） | 分類 | 修復 | 重驗 |
|---|---|---|---|---|---|
| 1 | continuous Size/MediaQuery inset gradient（12 個逐 frame 漸變，`Size(360,640)` → `Size(1000,360)`，每 frame 都 pump）是否造成 S-05 風暴 | 修復前實測 `applyPresentation=12`、`layoutGeneration=12`；最終 `viewportSize=Size(1000,360)` | production hypothesis confirmed | 尚未修復；這是 S1 修復前基線 | `reader_v2_rotation_viewport_test.dart` S1 measurement；進入 S2，需保留最終尺寸生效證據 |
| T2 handoff note | style rapid（非旋轉／inset）可重現同 frame signature storm：修復前 `applyPresentation=3`，修復後 coalesce 為 1；T3 仍須以自己的 viewport／inset sequence 實測 S-05，不可把此列當成旋轉結論 | 已有明確 style-only storm evidence；未聲稱 viewport storm | reference for T3 | T2 host coalesce 已限制每 frame 最新 style spec 一次 dispatch；viewport 行為仍待 T3 | T3 需保留自己的 rotation/inset scope |
| 2 | S2 coalesce 是否合併連續 viewport/inset stream 且不遺失最後尺寸 | 同一 12-frame sequence 修復後 `applyPresentation=1`、`layoutGeneration=1`；最終仍為 `Size(1000,360)` | production | host 以 latest-spec pending + one quiet scheduler frame coalesce；in-flight 後仍會重新排最新 pending | S1 measurement test 改為 regression；修復前同一測試實測 `12`，修復後 `1`，且最後尺寸斷言通過 |
| 3 | 旋轉前後語意位置是否 exact 保持，且往返不累積偏差 | 5 次直→橫→直共 10 次 presentation：anchor `charOffset=1356` 每次相同；未 settle 旋轉 `charOffset=1900, visualOffsetPx=36` 前後相同；章首、章末（chapter 2 offset 1198）、極短章節三組均 exact 通過 | test | 無 production bug；S3 使用 T1 `ReaderAnchorProbe` exact contract，widget seam 不宣稱真機旋轉證據 | `reader_v2_rotation_viewport_test.dart` 的 3 個 S3 tests 全綠；widget-level only，真機旋轉/inset 逐幀行為未在本 package 驗證 |

## T4 簡繁切換 — 迭代紀錄

| 迭代 | 假設 | 觀察 | 分類 | 修復 | 重驗 |
|---|---|---|---|---|---|
| 1 | `ChineseTextConverter` 的實際 `0→1→2→0` 鏈是否改變長度；長度差是否集中在章末或普遍分布 | 以 `flutter test test/core/engine/reader/chinese_text_converter_length_test.dart --reporter expanded` 實測：`samples/西游记.txt` 的 code-unit 長度鏈為 `677421→677421→677481→677481`；`0→1` delta `0`、`1→2` delta `+60`、`2→0` delta `0`，`1→2` 每千字 `+0.089`。60 個 +1 span 分布於 source offset `21547` 至 `669xxx` 的多個千字區段（非單一章末集中）。具體長度變更例：`騄→𫘧`、`駃→𫘝`、`騠→𫘨`、`騔→𩨀`、`勣→𪟝`、`爇→𦶟`、`蒭→𫇴`、`鯾→𫚣`、`蹻→𫏋`、`鐄→𨱑`、`縺→𦈐`、`鮆→𫚖`。Reader V2 state-transition smoke 的實際正文 fixture（兩段合併，60 code units）鏈為 `60→60→60→60`，三段 delta 均 `0`，沒有 length-changing span。 | test（S1 實測；尚無 production 結論） | 無；先保留量測 harness，尚未修改 production | S1 measurement test `1` passed；結果決定 S2 必須處理 `1→2` 的 Dart code-unit offset 重映射，不能只依舊 offset clamp |
| 2 | `1→2`／`2→0` 的 code-unit 長度變更是否造成語意位置漂移，且 content／measurement／paragraph／disk 四層是否全部 freshness-safe | `flutter test test/features/reader_v2/reader_v2_chinese_convert_loop_test.dart --reporter expanded`：9 tests passed；三方向均以 T1 `equivalentText` 通過，`1→2` offset `+1`、`2→0` offset `-1`，章末由舊長度移到新長度，6 次連續往返回到原 offset，未 settle 保留 anchor 與 `visualOffsetPx=36`；hybrid safe restore seam 收到重映射後位置並回到 `ready`。`1→2` 同時觀測新 `displayText` 含 `𫘧`、`contentHash` 改變、repository cache 指向新內容。四層 freshness test `3` passed：`MeasurementStore` 的 epoch 7 entry 不被 epoch 8 命中並可 invalidate；`ParagraphCache` 的舊 epoch paragraph 不被新 epoch acquire，新 paragraph 為獨立 entry；`MetricsDiskCache` 同 fingerprint 以 `content-hash-before` 可讀、改 `content-hash-after` 為空。 | production（offset restore 根因）＋ test（四層觀測） | `ReaderV2ContentLocationMapper` 以穩定句子序號定位，再以同一轉換 canonical form 的 code-unit prefix boundary 對齊句內位置；`reloadContentPreservingLocation` 在 clear 前保留 cached old `ReaderV2Content`，新內容載入後把 remapped location 傳入 fallback 與 hybrid restore。沒有改變替換規則、converter 順序、cache key 契約或 P4V rollback。 | 修復前實測 `flutter test ... --plain-name "1 to 2 remaps the expanded code-point offset"` 失敗：預期 `<10>`、舊直接 offset 實際 `<9>`；修復後同 focused case 及完整 9-test loop 通過。四層 freshness regression 由 `test/features/reader_v2/hybrid/reader_v2_content_conversion_cache_freshness_test.dart` 覆蓋並通過 |
| 3 | Android 上的實際 Reader V2 conversion action 是否能完成 reload/restore；不足性能樣本是否誤被宣稱為性能通過 | 使用 `pwsh -NoProfile -ExecutionPolicy Bypass -File .\tool\run_android_reader_workload.ps1 -DeviceId emulator-5554 -Scenario continuous -BuildMode debug -Action style_chinese_conversion -Iterations 1 -TimeoutSeconds 300 -EnableInvariantHook -ReportDir artifacts/android-reader/t4-chinese-conversion-continuous`：fixture 成功 push，workload APK 成功安裝，`READER_CONTINUOUS_ACTION ... style_chinese_conversion` 1 次，app log 的 `style-chinese-conversion-settled` 為 `phase=ready`、`layout=1`、`epoch=1`、`location.chapterIndex=0`、`charOffset=4`；driver test `All tests passed`。runner 依 fail-closed 規則整體標 `INVALID`，因 app frames `224`、driver frames `69` 均不足 `300` 且不一致；另記錄 1 筆 I8 微小 ballistic velocity observation（`0.0000317→0.0000913`），沒有 semantic anomaly，未據此擴大成 T4 production bug。此前 `flutter run -d emulator-5554 --debug --no-pub` 亦成功 build/install/啟動並見 `夜讀 Ready to Run`；初次 downgrade `161<4128` 後由 Flutter uninstall/reinstall 完成。 | env（Android debug workload 的性能窗口不足／兩來源 frame 不一致；I8 需另案以完整性能/monkey gate 判讀） | 無新增修復；保留 finite `300s` timeout、existing watchdog 與 fail-closed 判定，不改 runner、runtime knob 或 Android flow。 | Android functional conversion action 已執行且 test/driver passed；performance status 只能記為 `invalid/未判定`，不得宣稱 Android 性能通過 |

## T5 換源頁面層 — 迭代紀錄

| 迭代 | 情境 | 觀察 | 分類 | 修復 | 重驗 |
|---|---|---|---|---|---|
| 1 | S1 靜止換源；flush capture 前位置由 viewport/TTS 更新 | 靜止 case 實測 `DB=(chapter 1, offset 17, visual 23.5)` 與 `switchingBook` 完全一致。moving case 的 flush snapshot 實測 `DB=(chapter 1, offset 29, visual 31.25)`；修復後 `switchingBook` 同值。暫時還原 page 順序的 pre-fix focused regression 實際失敗：預期 `(1,29,31.25)`，實際 `switchingBook=(0,7,4.0)`；DB 已是 `(1,29,31.25)`。 | production | `ReaderV2ControllerHost.flushProgress()` 回傳實際 flush location；`ReaderV2Page._handleChangeSourceSelected` 改為先 await flush，再以該 snapshot 組 `switchingBook`。新增 debug-only before-flush hook 僅用於重現跨 await 的 location race。 | `flutter test ...reader_v2_source_switch_loop_test.dart` S1 兩項通過；輸出保留實際 DB/switchingBook 值。 |
| 2 | S2 `resolveSwitch` 失敗；`persistSwitch` 失敗 | resolve failure：舊 page 仍存在且 runtime 未 dispose，DB/location 均為 `(0,13,8.5)`，`upBookshelf` event `0`，錯誤為 `換源失敗: Bad state: resolve failure sentinel`。persist failure：DB/location 均為 `(1,19,11.75)`，event `0`，錯誤為 `換源失敗: Bad state: persist failure sentinel`；兩者 `persistCalls` 分別 `0/1`。 | test（無新增 production bug） | 無；現有 catch/transaction 邊界已符合 page-level contract。 | S2 兩項均通過；舊 session 可繼續、舊進度未破壞、失敗不發書架事件，錯誤原因保留。 |
| 3 | S3 `pushReplacement` + dispose late flush；極短延遲；返回競爭 | late flush blocked 時新 DB 為 `(1,23,9.25)`、舊 DB `null`，late pending 位置 `(0,41,17.5)`；release 後新 DB/location 仍 `(1,23,9.25)`。1ms resolve/persist 的新 session DB/location `(0,27,6.5)`，event `1`。返回競爭完成後 reader 不存在，新 DB/location `(0,15,5.25)`，event `1`。 | test（無新增 production bug）＋ env fixture adjustment | 保留既有 `flushProgress` 與 `pushReplacement`；新增 page test-only replacement seam；測試 fixture 註冊 `ReadRecordDao`，讓 `BookOpenRoute` 的既有 read-time scope 可建立。 | S3 三項通過；沒有觀測到舊 session late flush 覆蓋新 book，也沒有觀測到返回後再次 push。 |
| 4 | S4 package loop 終點：S1–S3、service regression、分析與全量測試 | T5 page suite `7` tests、T5+core source-switch regression `17` tests、兩個 core service suites `10` tests 均全綠；`flutter analyze` 為 `No issues found!`；全量 `flutter test` 實測 `1082` tests passed。 | pass | — | S1–S3 出口成立；未新增分析 error，full suite 全綠。 |

## T2 Relay acceptance（2026-09-14）

Relay independently reran the T2 style matrix (`14` tests) and `flutter analyze`
with no issues; the Reader V2 subtree also passed with `237` tests. The worker's
full-suite evidence records `1058` passing tests. The seven executable style
dimensions, clamp and cell-width boundaries, one-transition combination, rapid
coalescing, unsettled-anchor restore, and explicit `bold`/`fontFamily` skips are
accepted. The two production fixes retain pre-fix failure evidence and do not
change P4V's rollback state or any archived history.

## T1 Relay acceptance（2026-09-14）

Relay independently reran `flutter analyze` with no issues and the T1 helper plus
four-path smoke command with 9 passing tests. Worker evidence additionally records
223 Reader V2 tests, 1044 full Flutter tests, and 10 existing source-switch service
tests as passing. T1 is accepted as a test foundation: the normal app route remains
unchanged, all new production-facing entry points are `@visibleForTesting` or
`kDebugMode`-gated observers, and the documented Android/rotation/inset-only and
failure-race boundaries remain for T3–T5.

## T3 Relay acceptance（2026-09-14）

Relay independently reran the T3 rotation/viewport test (`4` tests) and the T2
style matrix (`14` tests), with `flutter analyze` reporting no issues. The required
S1-before-repair evidence confirms `12` viewport frames caused `12` presentation
dispatches and `12` generation advances; after scheduler-quiet-frame coalescing,
the same sequence produces `1` dispatch and `1` generation advance while the final
`Size(1000,360)` is applied. The five round trips, unsettled rotation, chapter
boundaries, and very-short-chapter exact-anchor cases pass. T3 is accepted with its
widget-only Android evidence boundary; worker evidence records `1062` full-suite
tests passed, and no archived history or P4V rollback state was changed.

## T4 Relay acceptance（2026-09-14）

Relay independently reran the conversion length, remap, four-layer freshness, and
existing transformer tests (`34` passed), `flutter analyze`, and the Reader V2
subtree (`253` passed). The required S1 sample measurement, concrete length-changing
spans, `0→1`/`1→2`/`2→0` semantic cases, long-chapter end, repeated round trips,
unsettled restore, hybrid restore, and content/measurement/paragraph/disk freshness
evidence are accepted. The pre-fix offset regression is retained (`Expected 10,
Actual 9`). The bounded Android flow is correctly `INVALID` for insufficient and
inconsistent frame sources, not a performance pass; no archived history or P4V
rollback state was changed.

## T5 Relay acceptance（2026-09-14）

Relay independently reran the T5 page suite plus both unchanged service suites:
`17` tests passed (`7` page tests and `10` service tests), and `flutter analyze`
reported no issues. The flush-location authority race, resolve/persist failures,
late dispose flush, short-delay replacement, return competition, DB rows, event
counts, and error messages are accepted. The service test files have zero diff;
the normal `pushReplacement` flow and `flushProgress` were retained. Worker
evidence records `1082` full tests passed, with no network or Android claim.

## T6 Knowledge extraction（2026-09-14）

### Durable / batch-local 分界

以下是跨批次仍成立、因此已沉澱到專案入口文件的 durable facts：

- 四條狀態轉換不是同一條 reload 路徑：樣式與旋轉／viewport 都由
  `LayoutBuilder` 的 style／尺寸輸入進入 `syncRuntimeConfiguration`，經
  `layoutSignature` 與 scheduler quiet-frame coalescing 後走 `applyPresentation`；
  簡繁由 `contentSettingsGeneration` 進入 `reloadContentPreservingLocation`，做
  舊內容保留、UTF-16 boundary 語意重映射與 freshness-safe restore；換源先以
  `flushProgress()` snapshot 作唯一位置權威，再 `resolveSwitch → persistSwitch →
  pushReplacement(BookOpenRoute(...))` 建立新 session。完整觸發鏈在
  `docs/night_reader/reader.md` 的 `State-transition contracts`。
- `textColor` 不改變幾何，故不 bump `layoutGeneration/epoch`；Hybrid 仍以顏色
  freshness 重建 bounded cache namespace 並 restore，主題切換期間短暫缺 paragraph、
  tint 逐塊收斂至直繪是設計瞬態，不是 layout transition 失敗。
- `ReaderV2Style` 沒有 `fontFamily`，`readStyleFor` 的 `bold` 固定為 `false`；
  兩者是目前未接上的輸入，不是本批次遺漏的可變 style。若未來支援，
  `layoutSignature` 與 hybrid fingerprint 必須同步補維度。
- `SourceSwitchService` service-layer 覆蓋已完備；目前需要維護的是 page-layer
  編排、flush／失敗競爭與新 session 拆建，不應重建既有 service tests。
- T1 的 `ReaderAnchorProbe`／`expectReaderAnchorPreserved`、epoch／generation／
  metrics freshness assertions，以及可控制成功／失敗／延遲的
  `FakeReaderV2SourceSwitchService` 是後續狀態轉換測試的共用 seam；T2/T3 用 exact
  anchor，T4 用 conversion-aware `equivalentText`。

以下只屬本批次的 batch-local evidence，保留在 ledger／completed reports，不搬進
長期模組地圖或日常操作導引：12-frame 修復前後的 dispatch 數、特定 fixture 的
offset／content length 與 DB row 數值、各 package 當次測試總數、widget-only 與
bounded memory-DB seam 的執行邊界，以及 Android workload 的 frame 不足／來源不一致
而 `INVALID` 的一次性結果。它們是證據，不是未來每次修改都必然成立的產品契約。

### 三條 Known Risks 對應結果

| reader.md Known Risk | 本批次結果 | 仍保留的邊界 |
|---|---|---|
| Capture/Restore 的像素級耦合 | T2 七個 style 維度、T3 五次直→橫→直、未 settle、章首／章末／短章 cases 均保住 exact semantic anchor，未觀測累積漂移。 | 公式仍分散且沒有真機旋轉／system-inset 證據，因此風險降為已覆蓋案例未重現，不是移除風險。 |
| 替換規則與正文雜湊的順序敏感性 | T4 對實際 `1→2` UTF-16 擴張做位置重映射，更新 `displayText/contentHash` 並隔離 content／measurement／paragraph／disk freshness；既有替換→轉換順序未改。 | 未來若改替換規則或管線順序，仍須重新驗證；不能只靠舊 offset clamp。 |
| 進度落盤的時序與離場競爭 | T5 確認 flush snapshot 是換源權威，resolve/persist failure 保留舊 session，`pushReplacement` 後舊 session late flush 不覆寫新 book row。 | 證據限於 page-layer bounded memory-DB seam；real network、device timing 與新 session layout 未驗證。 |

### 測試路徑與 L3

T1 seam 與 T2–T5 的檔案入口如下；日常使用方式已集中寫入
`DEVELOPMENT.md` 的 `Reader V2 狀態轉換驗證入口`，避免把測試操作說明複製到
`reader.md`：

- T1：`reader_v2_state_transition_test_support.dart`、其 `_test.dart` 自我測試，
  以及 `reader_v2_state_transition_smoke_test.dart`。
- T2：`reader_v2_style_change_test.dart`。
- T3：`reader_v2_rotation_viewport_test.dart`。
- T4：`reader_v2_chinese_convert_loop_test.dart`、
  `hybrid/reader_v2_content_conversion_cache_freshness_test.dart`，另有
  `test/core/engine/reader/chinese_text_converter_length_test.dart`。
- T5：`reader_v2_source_switch_loop_test.dart`；既有 service regression 為
  `test/core/services/source_switch_service_test.dart` 與
  `test/core/services/source_switch_progress_test.dart`。

L3 實際覆核：

```text
flutter test test/features/reader_v2 --reporter compact
260 tests passed
All tests passed!
```

這次 subtree run 找到 T1–T5 的新增 Reader V2 測試；其餘 converter 長度基線位於
subtree 外，已由 DEVELOPMENT 的額外命令明確指出。未重新命名或移動任何測試檔。

### 無上下文文件實效檢查

1. 提問：「我要改閱讀字級相關的東西。」
   - 可查答案：先讀 `reader.md` 的 `State-transition contracts`，知道 style 由
     `readStyleFor → syncRuntimeConfiguration → layoutSignature → applyPresentation`
     進入；再按 `DEVELOPMENT.md` 表格跑 T2 style test 與 subtree，並使用 T1 exact
     anchor／generation／metrics assertions。文件也明示 `fontFamily` 尚未存在、
     `bold` 是固定輸入，避免把未支援能力當成漏測。
   - 仍需口頭知識：沒有。若要宣稱真機排版或效能，仍須依 DEVELOPMENT 的 Android
     驗證邊界另取證據；這不是狀態轉換入口的缺件。
2. 提問：「換源好像會跳錯章。」
   - 可查答案：先讀 `reader.md` 的換源 trigger chain 與 `進度落盤的時序與離場競爭`
     risk，知道先 flush snapshot、再 resolve/persist、最後 pushReplacement 新
     session；接著從 DEVELOPMENT 的 T5 page test 入口開始，並確認 service tests
     已存在而不重建。
   - 仍需口頭知識：文件可定位 page-layer 編排、失敗與 late-flush 競爭，但 real
     network/source-sheet UI、新 session layout 與裝置 timing 仍未由本批次驗證，需
     回到 live code 或建立相應環境證據。

### 重複與保留檢查

`reader.md` 只承載 Reader 結構、四條 trigger chain、設計缺口與 Known Risk 結果；
`DEVELOPMENT.md` 只承載測試命令、檔案入口與 exact/equivalent helper 的使用導引。
兩份文件沒有完整重述同一項事實；120Hz stability 已有的段落與 P4V rollback
內容均保留，沒有改動 P1–P6 archived docs/history。

## T6 Relay acceptance（2026-09-14）

Relay independently accepted T6 as a documentation-only knowledge package.
`docs/night_reader/reader.md` now carries the four state-transition trigger
chains, durable design contracts, and the three Known Risk outcomes; `DEVELOPMENT.md`
provides the verification entry points without copying the module-map facts.
The four required easy-to-misread facts are explicitly searchable: `textColor`
does not bump layout epoch/generation, `fontFamily` is not a current style input,
`bold` is fixed, source switching is `pushReplacement` into a new session, and
the service-layer source-switch tests are already complete while page-layer
orchestration remains the maintenance surface.

Relay reran `flutter analyze` with `No issues found!` and
`flutter test test/features/reader_v2 --reporter compact`, with `260 tests
passed`. The worker's static document checks reported
`DOC_EFFECTIVENESS_CHECKS_OK`, `FINAL_DOC_CHECKS_OK`, and `WHITESPACE_OK`.
No `lib/` source was changed by T6, no test was renamed or moved, and the
existing P4V rollback remains `RenderCachedBlock.isRepaintBoundary => true`.

The acceptance boundary is explicit: T6 does not add a full-suite, Android,
real-device, or performance rerun, and it does not turn the bounded/invalid
Android observations or batch-local counts into durable claims. No commit,
push, reset, clean, stash, or archived-history rewrite was performed.
