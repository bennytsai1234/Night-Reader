# source_manager

## Responsibility

- 書源管理：批次匯入/匯出/啟停/校驗、書源編輯、規則偵錯、訂閱更新，以及全域/章內替換規則 CRUD。是 release 重點回歸區。
- 未來工作從這裡開始：書源：書源匯入/匯出/啟停/校驗、書源編輯欄位、逐階段偵錯、訂閱更新、替換規則。

## Scope

- `lib/features/source_manager/source_manager_page.dart`、`source_manager_provider.dart`（913 行，isolate 批次匯入、校驗、分享、啟停）。
- `lib/features/source_manager/source_editor_page.dart`（Tab 編輯器）+ `views/`：`source_edit_basic.dart`、`source_edit_book_info.dart`、`source_edit_search.dart`、`source_edit_explore.dart`、`source_edit_toc.dart`、`source_edit_content.dart`。
- `lib/features/source_manager/source_debug_page.dart` + `source_debug_provider.dart` — `SourceDebugProvider extends BaseProvider`（逐階段搜尋/詳情/目錄/正文除錯，接 `SourceDebugService` logStream）。
- `lib/features/source_manager/source_group_manage_page.dart`、`source_subscription_page.dart`。
- `lib/features/source_manager/widgets/` — `source_item_tile.dart`、`source_manager_menus.dart`、`source_manager_dialogs.dart`、`source_batch_toolbar.dart`、`source_check_status_bar.dart`、`rule_text_field.dart`、`import_preview_dialog.dart`。
- `lib/features/replace_rule/` — `replace_rule_provider.dart`（`ReplaceRuleProvider`，CRUD+分組）、`widgets/`（`replace_edit_form.dart`、`replace_edit_options.dart`、`replace_edit_test_panel.dart`）。

## Dependencies & Impact

- 上游：`engine`（間接，透過 check/debug）、`database/dao/book_source`、`services/{check_source,source_debug,source_update,source_switch,network}`、`models/{book_source,book_source_part}`、`storage/app_storage_paths`、`base/base_provider`、`di`。
- 下游影響：書源啟停/變更影響 search/explore/book_detail/reader；替換規則影響 reader 的 `ReaderV2ContentTransformer`。

## Key Flows

- 批次校驗：`SourceManagerProvider` → `CheckSourceService`（Isolate）→ 狀態回報 → `source_check_status_bar`。
- 偵錯：`SourceDebugProvider` 訂閱 `SourceDebugService` logStream → 逐階段顯示。
- 編輯：`source_editor_page.dart` + `views/*` → 寫入 `BookSourceDao` → 觸發 `sourceChanged`。
- 替換規則：`ReplaceRuleProvider` → `ReplaceRuleDao`；reader 端讀取套用。

## Change Entry Points & Routes

- 匯入/匯出/啟停/批次：`source_manager_provider.dart` + `import_preview_dialog.dart`。
- 校驗：`source_manager_provider.dart` + `services/check_source_service.dart` + `source_check_status_bar.dart`。
- 偵錯：`source_debug_provider.dart` + `services/source_debug_service.dart`。
- 編輯欄位：`source_editor_page.dart` + 對應 `views/source_edit_*.dart`。
- 訂閱：`source_subscription_page.dart` + `services/source_update_service.dart`。
- 替換規則：`features/replace_rule/replace_rule_provider.dart` + reader `reader_v2_content_transformer.dart`。

## Known Risks

- 書源驗證涉及 WebView/Cookie/真實網站，易出現僅真機或真實網站才復現的問題；優先用 `tool/` 腳本重現。
- `CheckSourceService` 在 Isolate 跑，JS 規則覆蓋受限（見 services 模組）。
- 編輯器各 Tab 欄位對應 `models/book_source_part` 結構，改 model 需連動 `views/*`。
- 替換規則變更不會自動通知 reader 已載入章節，需評估是否需重排。

## Do Not Do

- 不要在 `source_manager` 直接抓正文（層 book_detail/reader）。
- 不要在偵錯流程關掉全 App 的書源併發鎖（會被 ban）。
- 不要新增非書源/替換規則的管理頁面（feature freeze）。