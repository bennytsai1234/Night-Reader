# reader

## Responsibility

閱讀器 V2（`lib/features/reader_v2/`，八層架構）掌管從「使用者點開一本書」到「流暢閱讀與離開」的全部過程：章節目錄與正文載入、替換規則與排版正規化、版式計算（legacy page 引擎）與增量排版（hybrid pump）、捲動視窗與錨點恢復、閱讀進度持久化、TTS、自動翻頁、書籤、選單與閱讀設定、閱讀時數統計、換源與退出流程。

- 任何閱讀 UX、排版、捲動、進度遺失、TTS 跟讀類問題，從這裡開始。
- DEVELOPMENT.md 明列 Reader V2 為 **release 重點回歸區域**：對 session / hybrid / use_cases 的變更需搭配完整手動捲動與翻頁驗證。
- 本模組是終端 feature，沒有下游消費者；唯一的「對外出口」是進度/書籤/時數等持久化資料（見 Dependencies & Impact）。

## Scope

代表性結構（80 個 .dart，全部在 `lib/features/reader_v2/`；本節亦列出模組外的開書進入點）：

- **進入點**：`lib/shared/navigation/book_open_route.dart` 的 `BookOpenRoute`（reader_v2 之外的唯一 route 進入點，內層包 `ReaderV2ReadTimeScope` → `ReaderV2Page`）。呼叫者為 `bookshelf_page.dart`、`book_detail_page.dart` 與 `reader_v2_page.dart` 本身（換源重開）。
- **Shell 層** `screen/`：`ReaderV2Page`（Widget entry + 所有 feature 回呼綁定）、`ReaderV2PageShell`（Scaffold、上下工具列、章節抽屜）、`ReaderV2ControllerHost`（runtime 與全部子控制器的唯一工廠）、`dependencies/reader_v2_dependencies.dart`（DAO 依賴組裝）。
- **Application 層** `use_cases/`：`ReaderV2PageCoordinator`（點擊分區、跳章、scrub、書籤、自動翻頁、TTS 跟讀）、`coordinators/ReaderV2PageExitCoordinator`（退出流程）、`ReaderV2DisplayCoordinator`（進度字串格式化）、`ReaderV2ChapterNavigationResolver`。
- **Runtime 層** `session/`：`ReaderV2Runtime`（中央狀態委派）、`ReaderV2StateMachine`（7 階段 FSM + operation token）、`ReaderV2NavigationController`（legacy page-window 翻頁）、`ReaderV2ViewportBridge`（capture/restore/saveProgress 委派）、`ReaderV2PreloadScheduler`、`ReaderV2ProgressController`、`ReaderV2Resolver`（legacy 排版快取）、`ReaderV2ReadTimeScope/Controller`（閱讀時數）。
- **Content 層** `chapter/`：`ReaderV2ChapterRepository`（目錄/正文載入，含替換規則）、`ReaderV2ContentTransformer`（替換規則 + 重分段 + `normalizeTypography`，常駐 worker isolate）、`ReaderV2Content` / `ReaderV2ProcessedChapter`。
- **Layout 層** `layout/`：`ReaderV2LayoutEngine`（legacy 分頁排版，804 行）、`ReaderV2LayoutSpec`（layoutSignature + em-grid 鎖寬）、`ReaderV2Style/Typography`。
- **Render 層** `render/`：`ReaderV2RenderPage` / `ReaderV2LineBox` / `ReaderV2TextAdapter`（legacy 頁面渲染模型）。
- **Viewport 層** `viewport/`：`ReaderV2ViewportController`（七閉包 attach/detach 介面）、`ReaderV2PointerTapLayer`。
- **Features 層** `features/`：tts（含 highlight 模型）、menu（上下工具列 + 點擊分區設定）、auto_page、bookmark、replace_rule（獨立管理頁）、settings（`ReaderV2PrefsRepository` + 控制 + sheets）。
- **Hybrid 子系統** `hybrid/`（方案 B 捲動引擎，生產路徑）：`HybridReaderScreen`（1749 行主體）、`pump/`（`LayoutPump` + `BudgetGovernor` + `LayoutCostModel`）、`measure/`（`DocumentIndex` 雙 Fenwick + `MeasurementStore` + `MetricsDiskCache` 磁碟度量）、`paragraph/ParagraphCache`（LRU + pin）、`view/`（`AdmissionController`、`HybridScrollView`、`HybridBlockSliver`、`CachedBlockWidget`）、`anchor/AnchorManager`、`text/`（`TextPreprocessor` isolate 切塊 + `HybridChapterRepository`）、`progress/HybridProgress`、`telemetry/`、`overlay/`（TTS 高亮、選取）。
- **測試** `test/features/reader_v2/`：hybrid 子目錄 13 個測試檔（pump/measure/screen/scroll/sliver/telemetry/text/core/overlay/repaint/em_grid/fuzz/preprocessor）+ 18 個上層單元測試 + 1 個 session 子目錄測試（read_time），含 4 個 `*_stress_test.dart`（runtime/resolver/preload/progress）。hybrid 沒有對應整面 widget test 覆蓋所有路徑（見 Known Risks）。

## Dependencies & Impact

**上游輸入**：
- `core/database/dao/*`：BookDao（進度寫入）、ChapterDao（目錄）、BookSourceDao、ReplaceRuleDao、ReaderChapterContentDao、BookmarkDao。DAOs 由 `ReaderV2Dependencies` 從 GetIt 取得（`getIt.isRegistered` 的 DAO 可為 null，替換規則/書籤/內容快取會自動降級）。
- `core/models/`：`Book`（書目與進度欄位：chapterIndex / charOffset / visualOffsetPx / durChapterTitle / readerAnchorJson）、`BookChapter`、`Bookmark`、`ReplaceRule`。
- `core/services/`（services 模組）：`ReaderChapterContentStorage` + `ReaderChapterContentStore`（正文物化管線）、`BookSourceService`（目錄/正文抓取）、`SourceSwitchService`（換源）、`TTSService`（經 `ReaderV2SystemTtsEngine`）、`AppLogService`（telemetry 摘要）。
- `core/engine/`：`ChineseTextConverter`（簡繁）、`AppPattern`、`AppEventBus`（upBookshelf）、`reader/chinese_text_converter`。**不依賴規則引擎 JS 執行**（內容轉換是 Dart 替換規則，非 JS 規則）。
- `core/config/app_config.dart`：`AppConfig.readerV2ContentJustify`（justify 開關，預設 false，僅供真機對照）。
- `features/settings/settings_page.dart`（全域設定入口）、`features/book_detail/widgets/change_source_sheet.dart`（換源 sheet）。
- 三方同步：`SettingsProvider ↔ AppConfig ↔ PreferKey` 不一致時，`ReaderV2PrefsRepository` 直接讀 SharedPreferences 的 `PreferKey.reader*` 會拿到舊值。

**下游影響**：
- 無直接 UI 下游（終端 feature）。持久化出口：`BookDao.updateProgress`（book 表進度欄位 + `readerAnchorJson`）、`BookmarkDao`、`ReadRecordDao`（閱讀時數，`reading_stats_page.dart` 顯示）、`AppEventBus.upBookshelf`。
- 改 `ReaderV2Location` 的 JSON 結構或 `visualOffsetPx` clamp 範圍，會破壞既有書的 `readerAnchorJson` 恢復（跨版本相容問題，見 Boundaries）。
- `ReaderV2ChapterRepository` 的 `book.origin == 'local'` 分支會拒絕非 TXT 的 local:// 路徑（格式不支援時丟例外），與 local_book 模組的行為耦合。

## Key Flows

**開書**：`BookOpenRoute` → `ReaderV2ReadTimeScope`（開始計時）→ `ReaderV2Page` → `LayoutBuilder` 首次建構 → `ControllerHost.ensureRuntime(size, style)`（建立 Runtime + TTS + AutoPage + Bookmark，`_openRuntimeAfterFirstFrame` 延一幀）→ `Runtime.openBook()` → `ensureChapters()`（先查 ChapterDao，再 `BookSourceService.getChapterList`）→ `_positionHybridViewport()`：`loadContent` → 經 `viewportBridge.viewportRestore`（= `HybridReaderScreen._restoreToLocation`）→ `_restoreCore` 重定中心 + `_pumpUntilAnchorReady` + `jumpTo` 錨點偏移 → `completeReadyOperation` 進 `ready`。熱掛載（runtime 已 ready）由 `HybridReaderScreen` 的 post-frame `_syncToRuntimeLocation(force: true)` 補同步。

**內容管線**（`ReaderV2ChapterRepository.loadContent`）：`ReaderChapterContentStorage.read`（services 模組物化：DB 快取 → 書源抓取）→ `ReaderV2ContentTransformer.process`（常駐 worker isolate `ReaderV2ContentTransformWorker`，失敗退 `compute`）→ 替換規則（`_processInBackground`，按 order 排序、去重複標題、重分段）→ `normalizeTypography`（恆開、無開關的排版正規化：全形標點、引號配對、破折號、刪 CJK 空格）→ `ReaderV2Content`（displayText / paragraphs / contentHash）。**contentHash 是磁碟度量快取的驗證 key，任何轉換規則變更都會自動讓舊 metrics 失效**。

**hybrid 排版與捲動**（生產主路徑）：章節文字 → `TextPreprocessor`（isolate 切 block，`maxBlockChars` 由 `BudgetGovernor.ballisticSliceBudget` 經 `LayoutCostModel.maxCharsFor` 決定）→ `_ensureWindowTasks`（center±2 章投放）→ `LayoutPump.pumpPending()`（每幀預算 = 實測 vsync 週期 − 安全邊際 − 非 pump 工作量；`_nextTask` 依 priority/direction 計分）→ 產出 `ui.Paragraph` 進 `ParagraphCache`（LRU + pin）、`BlockMetrics` 進 `MeasurementStore` → `AdmissionController`（由 center 向兩側連續 admit，I2）→ `DocumentIndex`（雙 Fenwick 座標，`revision` 直驅 `RenderHybridBlockSliver.markNeedsLayout`，**不經 widget setState**）。捲動中每幀 `_scheduleMotionCapture`（窄通道 capture，不 notify runtime）；settle 時 `_handleScrollSettled` → `captureAndReport(notify: true)` → `Runtime.saveProgress(immediate: true)` 即刻落盤。

**capture/restore 錨點**：錨點線 = `AnchorManager.anchorOffsetInViewport`（view 高 20%，clamp 24–120px，與 `ReaderV2LayoutSpec.anchorOffsetInViewport` 同一公式）。capture 產出 `ReaderV2Location{chapterIndex, charOffset, visualOffsetPx∈[-120,120]}`；restore 以 block + 行內 charOffset 重算 scroll offset。`visualOffsetPx` 是行內微調（非整行位移）。

**進度持久化**：settle / `AppLifecycleState.paused|detached|inactive` / dispose / 換源前 / 退出前 → `ProgressController`（debounce 400ms；`flush()` 串接防重入）→ `BookDao.updateProgress` + 寫回 `book` 物件欄位 + `readerAnchorJson = jsonEncode(location.toJson())`。restore 期間（`restoreInProgress`）所有 save 一律拒絕。

**排版/設定變更**：`ControllerHost.syncRuntimeConfiguration` 比對 `layoutSignature`（或 `contentSettingsGeneration`）→ `Runtime.applyPresentation(spec)` 或 `reloadContentPreservingLocation()` → `stateMachine.beginPresentation`（layoutGeneration+1）→ `HybridReaderScreen._onRuntimeChanged` 偵測 generation 變更 → `_handleEpochRebuild`（清空 ParagraphCache / MeasurementStore / DocumentIndex / _blocks / _enqueued，舊 namespace metrics 先落盤）→ restore 錨點。**換色例外**：textColor 不進 StyleFingerprint，只清 `_enqueued` 重投任務，paint 以 colorFilter tint 過渡收斂（見 Known Risks）。

**翻頁**：hybrid 下經七閉包 `_moveToNextPage`（`ReaderV2ViewportController`）→ FIFO 佇列 → `_animateByNow`（viewport 高 − 行高 − 8，至少 50%）→ settle。`Runtime.moveToNextPage` 在 `hybridViewportActive` 時直接回 false——legacy `NavigationController` 的 page-window 翻頁**只在 hybrid 未註冊時**可用（生產永遠是 hybrid，見 Known Risks）。

**跳章/scrub**：`PageCoordinator.jumpToChapter` → `Runtime.jumpToChapter` → hybrid 走 `_positionHybridViewport`（章首錨點 + `pendingChapterJumpTarget` 語意：交錯跳章時先結束者不得清掉後到者的 target）。scrub 預覽 180ms debounce，commit 時換算百分比 → 章節內 charOffset。

**TTS**：`ReaderV2TtsController` 把章節 displayText 切 24–220 字 segment → `TTSService`（system TTS）→ 每 segment 播完 `_advanceSegment` → `Runtime.ensureCharRangeVisible`（hybrid 的 `_ensureCharRangeVisibleNow`，跨窗跳讀走 `_restoreCore`，同窗則 `_ensureRangeLaidOut` + animateTo）→ `HybridTtsHighlightOverlay`（`_ttsLineBoxes` 即時換算螢幕座標）。高亮跟隨由 `PageCoordinator.maybeFollowTtsHighlight` 驅動。

**退出/換源**：退出 → `ExitCoordinator.handleExitIntent` → `persistExitProgress`（flush）→ 未入書架且開啟提示時彈「加入書架」→ 拒絕則 `discardUnkeptBookStorage`（`BookStorageService.discardBook` 清暫存內容）。換源 → `_handleChangeSourceSelected`（先 `flushProgress`）→ `SourceSwitchService.resolveSwitch`（含 `validateTargetContent`）→ `persistSwitch` → `Navigator.pushReplacement(BookOpenRoute)`，舊 page dispose 前的 capture+flush 完成與否決定進度是否遺失。

## Change Entry Points & Routes

常見任務的起手式（先讀這些符號，再看測試）：

- **捲動/位置/錨點問題**：`hybrid/hybrid_reader_screen.dart`（`_captureVisibleLocation` / `_restoreCore` / `_handleScrollSettled` / `_ensureCharRangeVisibleNow`）＋ `anchor/anchor_manager.dart` ＋ `session/reader_v2_location.dart`。測試：`hybrid_reader_screen_test.dart`、`reader_v2_navigation_viewport_bridge_test.dart`。
- **排版品質/斷行/間距**：`hybrid/pump/layout_pump.dart`（B2 末行補償兩段式、placeholder 縮排）＋ `layout/reader_v2_layout_spec.dart`（em-grid 鎖寬）＋ `layout/reader_v2_layout_engine.dart`（legacy 引擎）。測試：`hybrid_pump_test.dart`、`reader_v2_layout_engine_test.dart`。
- **效能/幀預算**：`pump/budget_governor.dart`、`pump/layout_cost_model.dart`、`view/admission_controller.dart`、`telemetry/hybrid_telemetry.dart`、`session/reader_v2_performance_metrics.dart`。測試：`hybrid_sliver_live_admission_test.dart`、`hybrid_scroll_behavior_test.dart`、`hybrid_telemetry_test.dart`。
- **內容轉換/替換規則**：`chapter/reader_v2_content_transformer.dart`（worker isolate + normalizeTypography）、`chapter/reader_v2_chapter_repository.dart`。測試：`reader_v2_content_transformer_test.dart`、`reader_v2_chapter_repository_test.dart`。
- **進度/恢復**：`session/reader_v2_progress_controller.dart`、`session/reader_v2_viewport_bridge.dart`、`session/reader_v2_state_machine.dart`。測試：`reader_v2_progress_controller_stress_test.dart`、`reader_v2_runtime_stress_test.dart`、`reader_v2_state_machine_test.dart`。
- **預載**：`session/reader_v2_preload_scheduler.dart`、`session/reader_v2_resolver.dart`。測試：`reader_v2_preload_scheduler_test.dart`（＋stress）、`reader_v2_resolver_test.dart`（＋stress）。
- **UI/feature**：`screen/reader_v2_page.dart`（回呼綁定）、`screen/reader_v2_controller_host.dart`（設定/版式變更路口）、`use_cases/reader_v2_page_coordinator.dart`（點擊分區）、`features/settings/reader_v2_settings_controller.dart`。測試：`reader_v2_settings_controller_test.dart`、`reader_v2_page_shell_test.dart`、`reader_v2_pointer_tap_layer_test.dart`、`reader_v2_bottom_menu_test.dart`、`reader_v2_auto_page_controller_test.dart`。

**必須保持同步的多檔路徑**：
1. **layoutSignature**：`ReaderV2LayoutSpec._buildSignature` 的欄位清單 ↔ `ControllerHost.specFromStyle` 的傳入參數 ↔ `ReaderV2LayoutStyle` 欄位 ↔ `Runtime.applyPresentation` 的 `!=` 比對。新增任何排版參數必須三處同時改，否則設定變更不會觸發重建（epoch 不 bump）。
2. **epoch 對齊**：`Runtime.layoutGeneration`（StateMachine bump）↔ `HybridReaderScreen._handleEpochRebuild` ↔ `MeasurementNamespace{epoch, fingerprint}` ↔ `ParagraphCache`/`DocumentIndex` 的 epoch key。epoch 不同步 = 舊 Paragraph 配新座標。
3. **StyleFingerprint**：`fromLayoutSpec` 欄位 ↔ `stableHash` ↔ `stableKey`（磁碟檔名材料）。新增欄位必須同時進三處，否則磁碟快取命中錯誤度量。
4. **ReaderV2Location JSON**：`toJson/fromJson` ↔ `BookDao.updateProgress` 的欄位 ↔ `book.readerAnchorJson` ↔ `BookOpenRoute.openTarget` 恢復（`ReaderV2OpenTarget.resume`）。schema 變更 = 舊書進度讀不回。
5. **內容管線座標系**：`normalizeTypography` 改變字元 ↔ `ReaderV2Content.contentHash` ↔ `MetricsDiskCache` 的 sha1 digest ↔ TTS/錨點 charOffset。**任何在 `ReaderV2Content.fromRaw` 之後改字的行為都會打爆 displayText 座標系**（code comment 明令禁止）。
6. **替換規則變更**：`ReplaceRuleDao` 更新 → `reloadContentPreservingLocation`（`contentSettingsGeneration` 偵測）→ `Repository.clearContentCache`。規則頁（`features/replace_rule/`）本身不會通知 reader——靠 settings generation 機制。
7. **anchorOffsetInViewport 公式**：`ReaderV2LayoutSpec.anchorOffsetInViewport` ↔ `AnchorManager.anchorOffsetInViewport`（兩處重複實作，改動需同步）。
8. **DB 快取與改存**：`ReaderChapterContentStore`（services 模組）的 schema/格式改動需與本模組的 `contentDao` 降級邏輯（null 時退回 `chapter.content` 欄位）對齊。

## Known Risks

1. **HybridReaderScreen 是最大單一檔案（1749 行）**，內部狀態交錯（`_captureVisibleLocation` / `_restoreCore` / `_ensureWindowTasks` / `_handleEpochRebuild` / FIFO 佇列）互鎖，改動極易造成捲動/可見位置偏移或進度錯位。沒有整面 widget 測試覆蓋所有分支（`hybrid_reader_screen_test.dart` 僅覆蓋主要路徑）。
2. **雙軌並存但生產只有 hybrid**：`ReaderV2Page._buildContent` 恆建 `HybridReaderScreen`，`Runtime.hybridViewportActive` 恆真；legacy `NavigationController`（page-window）與 `ReaderV2Resolver`/`LayoutEngine`（分頁排版）在生產是不活躍的 fallback，主要靠單元測試維護（runtime/resolver/navigation 測試）。新功能要嘛只做 hybrid 路徑、要嘛兩軌都驗證——不要假設 legacy 會被移除。
3. **Epoch 重建（`_handleEpochRebuild`）清空五個集合**（ParagraphCache / MeasurementStore namespace / DocumentIndex / `_blocks` / `_enqueued`），重建期間首幀可能白屏或錯位。`_restorePinning`（submit-time pin）是對抗「初始視窗建置量 > 快取容量 → LRU 逐出首屏段落」的機制，改 ParagraphCache 容量或 pin 時機需重測開書首屏。
4. **I1–I5 不變式散落 debug assert**：`HybridScrollView`（I1 extent 只讀 admitted metrics）、`AdmissionController`（I2 連續 admit / I3 座標不位移 / I5 邊界不可達）、`LayoutPump`（I4 拖曳中不得排版）、`DocumentIndex`（I2/I3 fallback 全量重建）。改動這四個類時，測試用 debug build 會 assert 擊穿——**fling 中的 `pumpPending` 被 `_dragging` 擋下就是 I4**。
5. **換色/字型過渡路徑昂貴**：`RenderCachedBlock.paint` 在烘色不一致時走 `saveLayer + colorFilter`（極貴），靠重投任務收斂。`StyleFingerprint.platformFontSignature` 含 `Platform.operatingSystemVersion`——**OS 更新會 invalidate 全部磁碟 metrics**（設計如此，不是 bug）。
6. **MetricsDiskCache 是版本化二進位格式**（v3：magic `NRHM`、40-byte row、章節 sha1 digest、背景 isolate 解析）。任何 render 幾何變更（如縮排 placeholder 改寬）必須升 `_version`，否則舊檔被讀成新座標（v2→v3 就是縮排改 placeholder 的案例）。
7. **預算治理依賴實測 vsync**：`BudgetGovernor` 用 FrameTiming vsync 間隔實測幀週期（非平台 API），測試環境沒有 FrameTiming 會用 `defaultFramePeriodMicros=8333` 假設。`_cellWidthCache` 與 `LayoutCostModel._msPerChar` 是靜態/實例快取，跨 session 殘留。
8. **內容轉換 worker 有測試鉤子**（`debugDisableWorker`、`dictionaryDataLoader`、`debugReset`）——正式路徑 spawn 失敗會靜默退回 compute（行為不變但簡繁轉換留在主 isolate）。背景 isolate 限制（Workmanager 不可跑 FFI/JS 規則）是 repository 級事實，內容轉換全是 Dart 純函式所以不受影響。
9. **進度寫入的競態面**：settle 即刻落盤 vs `flushProgress` 的多點觸發（lifecycle/dispose/換源/退出）；`restoreInProgress` 期間 save 被拒絕；`ProgressController.flush` 的 active-flush 串接在 dispose 後仍會把最後一筆寫完（`_pendingLocation != null` 時 `unawaited(flush())`）——這是刻意設計。
10. **換源/退出前的 flush 依賴 dispose 順序**：`_handleChangeSourceSelected` 先 `flushProgress` 再 pushReplacement；若新流程改變順序，舊 runtime 的 capture+flush 未完成會丟進度（舊文件即有紀錄，仍是高風險區）。
11. **排版正規化恆開（無開關）**：`normalizeTypography` 的引號配對/標點轉換以「行」為 CJK 脈絡單位、交替狀態機——這些啟發式（如撇號 vs 收引號的誤傷取捨）有過多次修正（code comment 記載 2026-07-18 / 2026-07-28 決策），改動需對照注釋與 `reader_v2_content_transformer_test.dart`。
12. **進度顯示模型**：`HybridProgressSnapshot` 的 `==` 忽略 <0.1% 的 raw 變化（防 rebuild 風暴）——依賴它的 UI 若需要更高精度會看到「不動」的假象。

## Boundaries

- **`ReaderV2Location` 是跨版本持久化合約**：JSON `{chapterIndex, charOffset, visualOffsetPx}` 寫入 `book.readerAnchorJson`；`visualOffsetPx` clamp 在 `[-120, 120]`（`ReaderV2Location.minVisualOffsetPx/maxVisualOffsetPx`），NaN/無限大視為無效 capture（`ViewportBridge._normalizeCapturedLocation` 丟棄）。加欄位可、改語意不可。
- **layoutSignature 的欄位清單就是確定性判定規則**：新增排版/字型參數（fontSize、lineHeight、letterSpacing、paragraphSpacing、padding*、textIndent、bold、lastLineSpacingCompensation、cellWidth、viewportSize、contentWidth/Height、`kReaderV2CjkTypographyFeatureSignature`）必須進 `_buildSignature`，否則 `applyPresentation` 的 `!=` 比對不觸發、epoch 不重算、磁碟 metrics 配舊座標。**textColor 刻意不在其中**（色不影響幾何）。
- **磁碟 metrics 的 key 語意**：檔名 = `sha1(bookUrl)`/`sha1(fingerprint.stableKey).bin`；內容有效性靠章節 `contentHash` 的 sha1 digest 逐章驗證。fingerprint 任何欄位變更（含新增欄位進 `stableKey`）都會讓舊檔「讀不到但仍在磁碟」——安全但佔空間，無清理機制。
- **縮排是 placeholder 座標系統**：段首縮排以 `indentChars` 個 U+FFFC placeholder（每字 1 code unit）進 Paragraph，不是 U+3000 文字；`charOffset`/TTS/錨點換算必須扣除 `indentChars`。改縮排實作（如改回 U+3000）會同時破壞 LayoutPump 座標、justify 行為與磁碟快取版本。
- **em-grid 鎖寬的 padding 是 spec 級值**：鎖寬把殘差平分進 `layoutSpec.style.paddingLeft/Right`，hybrid overlay（TTS 高亮）與 sliver 的水平 padding 必須讀 spec 值（`_overlayStyle`），不可用 `widget.style` 原始值。
- **間距規則含硬編碼特例**：標題後 = `paragraphSpacing * 8px`（`_trailingSpacingFor`）；段落末塊 = `fontSize × 行高 × paragraphSpacing`；同段續塊間 0 間距。改動需連同 `LayoutCostModel.mayCompensateLastLine` 的單行上界估算（兩處共用同一判斷）一起驗證。
- **justify 預設關閉**：`AppConfig.readerV2ContentJustify = false`（內文 start 對齊、em-grid 鎖寬後 justify 只剩破壞格線的副作用）；B2 末行字距補償開關 = `lastLineSpacingCompensation`。兩者都只影響外觀、不影響斷行與座標合約（補償有 clamp 保護）。
- **不要在應用層新增 `dart:io` 依賴**：`hybrid_reader_screen.dart` 是唯一特例（`Platform.operatingSystemVersion` 進 font fingerprint）；也不要新增平台條件判斷。
- **`ReaderV2State` 欄位增減必須同步 `copyWith` 與 `StateMachine`**（舊文件禁令仍然成立，無例外）。
- **FIFO 命令佇列紀律**：除 `settleScroll`（`jumpTo` 停慣性）外，不得繞過 `_HybridCommandQueue` 直接操作 scrollController；`_restoreCore` 執行期間不得啟動新 restore（`AnchorManager.beginRestore` 擋重入，拖曳中直接拒絕）。
- **worker/isolate 所有權**：`ReaderV2ContentTransformWorker` 是 App 級單例，測試必須用鉤子重設；`TextPreprocessor(useIsolate: false)` 是測試 seam，正式路徑恆用真 isolate。
- **書籤/替換規則/內容快取可降級**：`bookmarkDao`、`replaceDao`、`contentDao` 在 GetIt 未註冊時為 null（背景 isolate 或測試環境），對應功能自動停用——不得假設 DAO 恆存在。
- **本模組遵守 feature freeze**：只做維護、修 bug、效能調校、重構；不加產品線功能。發布流程見 AGENTS.md（tag 觸發 CI，本機不 build）。