# reader

## Responsibility

- Reader V2 閱讀器主流程：以 `hybrid/` 的 Framework 滾動骨架（`CustomScrollView.center` + 雙 `SliverVariedExtentList`）承載自有 block 排版管線，負責章節載入、精確量測、渲染、無界滾動、進度、TTS 逐段高亮、閱讀設定、點擊區、書籤、章內替換、換源。release 重點回歸區。
- 未來工作從這裡開始：排版/渲染、章節預載與進度、TTS 高亮、閱讀設定、點擊區、書籤、章內替換、換源 sheet。

## Scope

- `hybrid/` — 現行閱讀主面與排版核心：`hybrid_reader_screen.dart` 組裝 bridge；`core/` 定義 Block/Epoch/Fingerprint 契約；`text/` 做章節視窗與 isolate 前處理；`measure/` 維護精確 metrics、雙 Fenwick `DocumentIndex` 與 contentHash 驗證的磁碟快取；`paragraph/` 管 `ui.Paragraph` LRU/pin；`pump/` 是唯一排版入口；`view/` 管 center 雙 sliver、admission 與 leaf render object；`anchor/overlay/progress/telemetry/` 為橫切模組。
- `screen/` — `reader_v2_page.dart`（`ReaderV2Page`，組裝 ControllerHost/Coordinator/HybridReaderScreen/Menus/Drawer）、`reader_v2_page_shell.dart`、`reader_v2_chapters_drawer.dart`、`reader_v2_controller_host.dart`（聚合子控制器）、`dependencies/reader_v2_dependencies.dart`（從 getIt 注入 DAO + `BookSourceService`，建 `ReaderV2ChapterRepository`）。
- `session/` — `reader_v2_runtime.dart`（`ReaderV2Runtime extends ChangeNotifier`，整合 repository/content/layoutEngine/renderPage/preloadScheduler/progressController，持有 NavigationController + ViewportBridge 並代理公開 API，預載速度門檻 1500/2600/3600）、`reader_v2_state_machine.dart` + `reader_v2_operation_token.dart`（集中 open/jump/restore/presentation/contentReload 的 phase、過期操作檢查、restore-in-progress、visible/committed location 與 page window 更新）、`reader_v2_navigation_controller.dart`（導航跳轉/窗口/neighbor advance）、`reader_v2_viewport_bridge.dart`（viewport capture/restore/進度儲存）、`reader_v2_state.dart`（`ReaderV2Phase{cold,loading,layingOut,restoring,ready,switchingMode,error}`）、`reader_v2_resolver.dart`、`reader_v2_progress_controller.dart`、`reader_v2_preload_scheduler.dart`、`reader_v2_performance_metrics.dart`、`reader_v2_page_window.dart`、`reader_v2_open_target.dart`、`reader_v2_location.dart`、`reader_v2_chapter_view.dart`、`reader_v2_session_facade.dart`。
- `use_cases/` — `reader_v2_page_coordinator.dart`（點擊分區/TTS 高亮追蹤/換源 sheet）、`coordinators/`（章節導航 resolver、display coordinator、page exit coordinator）。
- `chapter/` — `reader_v2_chapter_repository.dart`（取章節/正文/書源/replace rule）、`reader_v2_content.dart`、`reader_v2_content_transformer.dart`（套用 replace rule＋恆開文字正規化＋簡繁轉換；假名行恆跳過簡繁）、`reader_v2_japanese_pass.dart`（日文段落 ML Kit 翻譯 pass，transformer 後、fromRaw 前）、`reader_v2_processed_chapter.dart`。
- `layout/` — `reader_v2_layout_engine.dart`（599 行，`ReaderV2LayoutEngine`+`ReaderV2LayoutEngineStats`）、`reader_v2_layout.dart`、`reader_v2_layout_spec.dart`、`reader_v2_typography.dart`（`kReaderV2PunctFontFamily` 內嵌標點字型＋fingerprint 簽名）、`reader_v2_style.dart`（`ReaderV2Style`，`minReadableLineHeight`）、`reader_v2_layout_constants.dart`。
- `render/` — `reader_v2_render_page.dart`、`reader_v2_line_box.dart`、`reader_v2_text_adapter.dart`，僅供保留的舊 session/resolver 相容路徑與測試使用；現行 hybrid 畫面不經 tile painter。
- `viewport/` — 只保留跨 feature 公開 bridge `reader_v2_viewport_controller.dart`（七閉包）與原始指標點擊仲裁 `reader_v2_pointer_tap_layer.dart`；具體捲動實作已由 `hybrid/view/` 擁有。
- `features/` — `tts/`（`reader_v2_tts_controller.dart` 494 行，`abstract ReaderV2TtsEngine`+實作、`reader_v2_tts_sheet.dart`、`reader_v2_tts_highlight.dart`）、`settings/`（`reader_v2_settings_controller.dart`、`reader_v2_prefs_repository.dart`、`reader_v2_settings_sheets.dart`）、`menu/`（`reader_v2_menu_controller.dart`、`reader_v2_bottom_menu.dart`、`reader_v2_top_menu.dart`、`reader_v2_tap_action.dart`）、`auto_page/`、`bookmark/`、`replace_rule/`（`reader_v2_replace_rule_sheet.dart`、`reader_v2_replace_rule_page.dart`、`reader_v2_replace_rule_editor_sheet.dart`）。

## Dependencies & Impact

- 上游：`database/dao`（book/book_source/chapter/bookmark/replace_rule/reader_chapter_content）、`services/{book_source,book_storage,source_switch,tts,reader_chapter_content_store/storage}`、`engine/{app_event_bus,reader/chinese_text_converter}`、`models/{book,chapter,replace_rule,book_source}`、`config/app_config`、`constant/prefer_key`、`di`、`shared/{theme,navigation}`。
- 下游影響：TTS 經 `TTSService`+`ttsProgress` 事件；進度/書籤寫回 DAO；換源經 `source_switch_service`。閱讀設定與 `settings`/`AppConfig` 同步。
- 被開書轉場（`shared/navigation/book_open_route.dart`）進入。

## Key Flows

- 開書：`ReaderV2Page` → `ReaderV2Runtime` hybrid owner 模式 → `HybridChapterRepository` 包裝既有 repository → `TextPreprocessor` 切成 block → `LayoutPump` 建立同源 `ui.Paragraph`/metrics → `AdmissionController` 連續放行 → `HybridScrollView` 渲染。
- 預載：`HybridChapterRepository` 以錨點章維持 ±2 章，`LayoutPump` 依 dragging/ballistic/idle gate 與領先量排程；metrics 以 StyleFingerprint + contentHash 驗證磁碟命中。
- TTS：`ReaderV2TtsController` → `TTSService` → `ReaderV2TtsHighlight` → block 的 `Paragraph.getBoxesForRange` 產生整行高亮；`ensureCharRangeVisible` 經 FIFO bridge 跟讀。
- 換源：`PageCoordinator` → `change_source_sheet` → `source_switch_service` → 重載章節。

## Change Entry Points & Routes

- 排版/渲染：`hybrid/{text,measure,paragraph,pump,view,overlay}`；`LayoutPump` 是唯一可建置與 layout `ui.Paragraph` 的模組，改 `ReaderV2Style` 需同步檢查 StyleFingerprint 與失效矩陣。
- 滾動/視埠：`hybrid/hybrid_reader_screen.dart` + `hybrid/view/*`；跨 feature 命令契約仍在 `viewport/reader_v2_viewport_controller.dart`，`reader_v2_state.dart` 定義 `ReaderV2Phase` 狀態機。
- 章節載入/預載/進度：`session/reader_v2_runtime.dart` + `chapter/reader_v2_chapter_repository.dart` + `services/reader_chapter_content_store.dart`。
- TTS 高亮：`features/tts/*` + `services/tts_service.dart` + `render/reader_v2_tts_highlight_overlay_layer.dart`。
- 閱讀設定/點擊區/自動翻頁/書籤：`features/{settings,menu,auto_page,bookmark}/*`；同步 `SettingsProvider`/`AppConfig`/`PreferKey`。
- 章內替換：`features/replace_rule/*` + `chapter/reader_v2_content_transformer.dart`。
- 換源：`use_cases/reader_v2_page_coordinator.dart` + `features/book_detail/change_source_sheet.dart` + `services/source_switch_service.dart`。

## Known Risks

- `ReaderV2Runtime` hybrid owner 模式沿用 `ReaderV2StateMachine` 的 operation token 與 `layoutGeneration`；hybrid `LayoutEpoch` 必須維持一對一，不可建立第二個獨立世代來源。
- I1–I6 是硬底線：extent 只能讀精確 metrics；admission 必須從 center 向兩側連續，正常放行位於 visible+cache 外；late exact edge 只可在實際 visible 外恢復，且既有 block 座標必須完全不變；禁止 offset correction；dragging 零排版；領先量不足必須降級；所有重建以 `ReaderV2Location` ↔ `HybridAnchor` 為基準。
- capture/restore 的 `visualOffsetPx` 必須以同一套 `ui.TextBox.top` 幾何換算；不可混用 `LineMetrics` 行頂與 tight text box 行頂。
- TTS/錨點仍使用 `ReaderV2Content.displayText` 的 UTF-16 半開區間；縮排前綴不屬於 displayText，幾何換算必須扣除。
- 磁碟 metrics 的 fingerprint 必須跨程序穩定，且逐章 contentHash 不符時不可 warm；平台字型摘要變化需換命名空間。
- 排版 TextStyle/ParagraphStyle 的 fontFamily 首位是內嵌 `NightReaderPunct`（僅 U+2014/2015/2025/2026/22EF 五碼位，`tool/punct_font/generate.py` 產生）；改字型資產或 fontFamily 必須 bump `kReaderV2CjkTypographyFeatureSignature`，否則沿用舊字形 metrics。
- 文字正規化恆開且無使用者開關（2026-07-18 內化決策）；改規則會改 contentHash（快取自動冷重建），但仍須維持「fromRaw 之後不得改字」的座標系契約。日文翻譯 pass（`reader_v2_japanese_pass.dart`）是唯一允許的 transformer 後改字點，因其仍在 fromRaw 之前。
- 本機只能驗證邏輯與 widget 行為；120Hz fling p99、長時間 Paragraph 記憶體平台期與真機字型 fallback 仍需 CI APK/device lab 驗收。

## Do Not Do

- 不要在 reader 內直接抓書（用 `ReaderV2ChapterRepository`+`BookSourceService`）。
- 不要在 `LayoutPump` 之外建立或 layout `ui.Paragraph`，也不要把 placeholder/估算 extent 放進 sliver。
- 不要為上側補入做 scroll offset correction；向上生長只用 `CustomScrollView.center` 的負座標空間。
- 不要把閱讀設定另存為獨立持久層（統一走 `PreferKey`+`AppConfig`）。
- 不要恢復 slide 翻頁模式（已移除，固定 scroll）。
- 不要在 feature freeze 下新增新互動模式（除非使用者明確要求）。
