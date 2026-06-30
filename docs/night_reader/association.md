# association

## Responsibility

- 外部意圖處理：深連結（URI）開書、分享檔案（TXT/EPUB）匯入、意圖對話框。
- 未來工作從這裡開始：深連結開書、分享本地書匯入、意圖對話框。

## Scope

- `lib/features/association/association_handler_service.dart` — `AssociationHandlerService extends AssociationBase with UriAssociationHandler, FileAssociationHandler, AssociationDialogHelper`（單例）。
- `lib/features/association/handlers/` — `association_base.dart`、`uri_association_handler.dart`（URI/深連結）、`file_association_handler.dart`（分享檔案）、`association_dialog_helper.dart`。

## Dependencies & Impact

- 上游：`services/{app_log_service,local_book_service}`、`shared/navigation`、`core/local_book/local_book_formats`。
- 下游影響：深連結開書經 `book_open_route`→`reader`；分享檔案經 `LocalBookService` 匯入→`bookshelf`。

## Key Flows

- App 啟動/回前台 → `app_links`/`receive_sharing_intent` 取意圖 → `AssociationHandlerService` 分流 → URI 開書 或 檔案匯入 → 對話框確認 → 導向 reader/bookshelf。

## Change Entry Points & Routes

- 意圖分流：`association_handler_service.dart` + `handlers/*`。
- 深連結開書：`handlers/uri_association_handler.dart` + `shared/navigation/book_open_route.dart`。
- 檔案匯入：`handlers/file_association_handler.dart` + `services/local_book_service.dart`。

## Known Risks

- 平台深連結/分享意圖差異大（Android intent filter、Cold vs Warm start），易有只特定進入路徑才復現的問題。
- 檔案匯入失敗需有明確對話框回饋，否則使用者無感。

## Do Not Do

- 不要在 association 直接抓章節或渲染閱讀（層 reader）。
- 不要繞過 `LocalBookService` 自行解析本地書格式。