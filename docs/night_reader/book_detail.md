# book_detail

## Responsibility

- 書籍詳情頁：顯示書籍資訊、目錄操作、預下載章節、換源搜尋、封面變更。
- 未來工作從這裡開始：詳情顯示、目錄載入/操作、預下載、換源、封面替換。

## Scope

- `lib/features/book_detail/book_detail_page.dart`。
- `lib/features/book_detail/book_detail_provider.dart`（800 行，`BookDetailProvider`：詳情/目錄/下載佇列）。
- `lib/features/book_detail/change_cover_provider.dart`（`ChangeCoverProvider`，全域註冊）、`change_cover_sheet.dart`。
- `lib/features/book_detail/source/book_detail_change_source_provider.dart`（`BookDetailChangeSourceProvider`，換源搜尋 pool 並發）。
- `lib/features/book_detail/widgets/` — `book_info_header.dart`、`book_info_intro.dart`、`book_info_toc_bar.dart`、`change_source_sheet.dart`、`book_detail_change_source_item.dart`、`book_detail_change_source_filter_bar.dart`、`cover/`（`cover_header.dart`、`cover_grid_item.dart`、`cover_manual_input.dart`）。

## Dependencies & Impact

- 上游：`engine/web_book`（經 `BookSourceService`）、`engine/app_event_bus`、`database/dao`、`services/{book_source,download,book_cover_storage,reader_chapter_content_store}`、`di`。
- 下游影響：預下載與 `downloads`/`services/download` 共用佇列；換源經 `services/source_switch_service`；封面經 `services/book_cover_storage_service`（影響書架顯示）。
- 入書後開書經 `shared/navigation/book_open_route.dart` → `reader`。

## Key Flows

- 進入詳情 → `BookDetailProvider` 載入書籍資訊＋目錄（`BookSourceService.getBookInfo/getChapterList`）。
- 預下載 → `DownloadService` 入隊；目錄顯示已快取章節數（`ReaderChapterContentStore`）。
- 換源 → `BookDetailChangeSourceProvider` 多書源搜尋 → `source_switch_service` → 重設書源。
- 改封面 → `ChangeCoverProvider` → `book_cover_storage_service`。

## Change Entry Points & Routes

- 詳情/目錄：`book_detail_provider.dart` + `widgets/book_info_toc_bar.dart`。
- 預下載：`book_detail_provider.dart` 下載區段 + `services/download_service.dart`。
- 換源：`source/book_detail_change_source_provider.dart` + `services/source_switch_service.dart`。
- 封面：`change_cover_provider.dart` + `services/book_cover_storage_service.dart`。

## Known Risks

- `BookDetailProvider`（800 行）狀態多，目錄/下載/換源混雜，改動易互相影響。
- 換源 pool 並發與 `NetworkService` 書源鎖互動，需驗證不被鎖死。
- 封面儲存變更後須觸發書架刷新（`upBookshelf`）。

## Do Not Do

- 不要在詳情頁渲染閱讀正文（層 reader）。
- 不要繞過 `source_switch_service` 自行換源。