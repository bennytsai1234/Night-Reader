# reader

## Responsibility

- Reader V2 閱讀器主流程：八層架構（screen / session / use_cases / chapter / layout / render / viewport / features 子面板），負責章節載入、排版、渲染、翻頁（僅 scroll）、預載、進度、TTS 逐段高亮、閱讀設定、點擊區、書籤、章內替換、換源。release 重點回歸區。
- 未來工作從這裡開始：排版/渲染、章節預載與進度、TTS 高亮、閱讀設定、點擊區、書籤、章內替換、換源 sheet。

## Scope

- `screen/` — `reader_v2_page.dart`（`ReaderV2Page`，組裝 ControllerHost/Coordinator/RenderPage/Viewport/Menus/Drawer）、`reader_v2_page_shell.dart`、`reader_v2_chapters_drawer.dart`、`reader_v2_controller_host.dart`（聚合子控制器）、`dependencies/reader_v2_dependencies.dart`（從 getIt 注入 DAO + `BookSourceService`，建 `ReaderV2ChapterRepository`）。
- `session/` — `reader_v2_runtime.dart`（`ReaderV2Runtime extends ChangeNotifier`，整合 repository/content/layoutEngine/renderPage/preloadScheduler/progressController，持有 NavigationController + ViewportBridge 並代理公開 API，預載速度門檻 1500/2600/3600）、`reader_v2_state_machine.dart` + `reader_v2_operation_token.dart`（集中 open/jump/restore/presentation/contentReload 的 phase、過期操作檢查、restore-in-progress、visible/committed location 與 page window 更新）、`reader_v2_navigation_controller.dart`（導航跳轉/窗口/neighbor advance）、`reader_v2_viewport_bridge.dart`（viewport capture/restore/進度儲存）、`reader_v2_state.dart`（`ReaderV2Phase{cold,loading,layingOut,restoring,ready,switchingMode,error}`）、`reader_v2_resolver.dart`、`reader_v2_progress_controller.dart`、`reader_v2_preload_scheduler.dart`、`reader_v2_performance_metrics.dart`、`reader_v2_page_window.dart`、`reader_v2_open_target.dart`、`reader_v2_location.dart`、`reader_v2_chapter_view.dart`、`reader_v2_session_facade.dart`。
- `use_cases/` — `reader_v2_page_coordinator.dart`（點擊分區/TTS 高亮追蹤/換源 sheet）、`coordinators/`（章節導航 resolver、display coordinator、page exit coordinator）。
- `chapter/` — `reader_v2_chapter_repository.dart`（取章節/正文/書源/replace rule）、`reader_v2_content.dart`、`reader_v2_content_transformer.dart`（套用 replace rule+簡繁轉換）、`reader_v2_processed_chapter.dart`。
- `layout/` — `reader_v2_layout_engine.dart`（599 行，`ReaderV2LayoutEngine`+`ReaderV2LayoutEngineStats`）、`reader_v2_layout.dart`、`reader_v2_layout_spec.dart`、`reader_v2_typography.dart`、`reader_v2_style.dart`（`ReaderV2Style`，`minReadableLineHeight`）、`reader_v2_layout_constants.dart`。
- `render/` — `reader_v2_render_page.dart`（`ReaderV2RenderLine extends ReaderV2LineBox`，548 行）、`reader_v2_tile_layer.dart`、`reader_v2_tile_painter.dart`、`reader_v2_tile_key.dart`、`reader_v2_line_box.dart`、`reader_v2_text_adapter.dart`、`reader_v2_page_cache.dart`、`reader_v2_tts_highlight_overlay_layer.dart`。
- `viewport/` — `reader_v2_viewport_controller.dart`（`ReaderV2ViewportController`：scrollBy/animateBy/moveToNextPage/ensureCharRangeVisible）、`scroll_reader_v2_viewport.dart`（viewport lifecycle/runtime wiring/build 決策）、`scroll_reader_v2_viewport_model.dart`（章節 window/cache/strip/座標計算）、`scroll_reader_v2_motion_controller.dart`（reading offset、drag/fling、overscroll、動畫）、`scroll_reader_v2_command_queue.dart`、`scroll_reader_v2_canvas.dart`（loading/canvas/tile/TTS overlay widgets）、`scroll_reader_v2_visible_line.dart`、`reader_v2_screen.dart`、`reader_v2_position_tracker.dart`、`reader_v2_visible_page_calculator.dart`、`reader_v2_pointer_tap_layer.dart`、`reader_v2_infinite_segment_strip.dart`、`reader_v2_chapter_page_cache_manager.dart`。
- `features/` — `tts/`（`reader_v2_tts_controller.dart` 494 行，`abstract ReaderV2TtsEngine`+實作、`reader_v2_tts_sheet.dart`、`reader_v2_tts_highlight.dart`）、`settings/`（`reader_v2_settings_controller.dart`、`reader_v2_prefs_repository.dart`、`reader_v2_settings_sheets.dart`）、`menu/`（`reader_v2_menu_controller.dart`、`reader_v2_bottom_menu.dart`、`reader_v2_top_menu.dart`、`reader_v2_tap_action.dart`）、`auto_page/`、`bookmark/`、`replace_rule/`（`reader_v2_replace_rule_sheet.dart`、`reader_v2_replace_rule_page.dart`、`reader_v2_replace_rule_editor_sheet.dart`）。

## Dependencies & Impact

- 上游：`database/dao`（book/book_source/chapter/bookmark/replace_rule/reader_chapter_content）、`services/{book_source,book_storage,source_switch,tts,reader_chapter_content_store/storage}`、`engine/{app_event_bus,reader/chinese_text_converter}`、`models/{book,chapter,replace_rule,book_source}`、`config/app_config`、`constant/{page_anim,prefer_key}`、`di`、`shared/{theme,navigation}`。
- 下游影響：TTS 經 `TTSService`+`ttsProgress` 事件；進度/書籤寫回 DAO；換源經 `source_switch_service`。閱讀設定與 `settings`/`AppConfig` 同步。
- 被開書轉場（`shared/navigation/book_open_route.dart`）進入。

## Key Flows

- 開書：`ReaderV2Page` → `ReaderV2Dependencies` 注入 → `ReaderV2ChapterRepository` 取首章 → `ReaderV2ContentTransformer` 套 replace/簡繁 → `ReaderV2LayoutEngine` 排成 line/page → `ReaderV2RenderPage`+tile 渲染 → `ReaderV2ViewportController` 翻頁。
- 預載：`ReaderV2PreloadScheduler` 依速度門檻預載前後章，經 `ReaderChapterContentStore`。
- TTS：`ReaderV2TtsController` → `TTSService` → `ttsProgress` 事件 → `reader_v2_tts_highlight` 疊圖。
- 換源：`PageCoordinator` → `change_source_sheet` → `source_switch_service` → 重載章節。

## Change Entry Points & Routes

- 排版/渲染：`layout/reader_v2_layout_engine.dart` + `render/*`；改 `ReaderV2Style` 需檢查 `minReadableLineHeight`。
- 翻頁/視埠：`viewport/*`；`reader_v2_state.dart` 定義 `ReaderV2Phase` 狀態機。
- 章節載入/預載/進度：`session/reader_v2_runtime.dart` + `chapter/reader_v2_chapter_repository.dart` + `services/reader_chapter_content_store.dart`。
- TTS 高亮：`features/tts/*` + `services/tts_service.dart` + `render/reader_v2_tts_highlight_overlay_layer.dart`。
- 閱讀設定/點擊區/自動翻頁/書籤：`features/{settings,menu,auto_page,bookmark}/*`；同步 `SettingsProvider`/`AppConfig`/`PreferKey`。
- 章內替換：`features/replace_rule/*` + `chapter/reader_v2_content_transformer.dart`。
- 換源：`use_cases/reader_v2_page_coordinator.dart` + `features/book_detail/change_source_sheet.dart` + `services/source_switch_service.dart`。

## Known Risks

- `ReaderV2Runtime` 與 `NavigationController` 為核心，`ReaderV2StateMachine` 已集中 high-risk operation、restore-in-progress、visible/committed location 與 page window mutation；可繞過 state machine 的 runtime API（`setState`／`state=` setter 等）已於 2026-07 移除，新增變異路徑一律經 state machine 的 begin/complete/fail 介面。
- 排版引擎反覆量測 line layout（`ReaderV2LayoutEngineStats`），效能迴歸風險高。
- TTS 逐段高亮依賴 layout 的字元座標，排版改動會讓高亮偏移。
- `ScrollReaderV2Viewport` 已拆為 viewport model、motion controller、command queue 與 canvas widgets；後續改動仍需留意 reading offset、人工 window 邊界續滑與 progress settle 的呼叫順序。
- 預載門檻與背景任務互動需驗；過度預載會吃記憶。

## Do Not Do

- 不要在 reader 內直接抓書（用 `ReaderV2ChapterRepository`+`BookSourceService`）。
- 不要把閱讀設定另存為獨立持久層（統一走 `PreferKey`+`AppConfig`）。
- 不要恢復 slide 翻頁模式（已移除，固定 scroll）。
- 不要在 feature freeze 下新增新互動模式（除非使用者明確要求）。
