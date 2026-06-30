# bookshelf

## Responsibility

- 書架頁：顯示在讀書籍、排序/分組、批次下載與更新檢查、匯入還原書架、書架交換、本機書匯入入架。
- 未來工作從這裡開始：書架顯示/排序、批次更新下載、匯入還原、書架交換。

## Scope

- `lib/features/bookshelf/bookshelf_page.dart`（838 行，`BookshelfPage`）。
- `lib/features/bookshelf/bookshelf_provider.dart` — `BookshelfProvider extends BookshelfProviderBase with BookshelfLogicMixin, BookshelfUpdateMixin, BookshelfImportMixin`（監聽 `AppEventBus.upBookshelf`）。
- `lib/features/bookshelf/provider/` — `bookshelf_provider_base.dart`（`BookshelfSortMode`）、`bookshelf_logic_mixin.dart`、`bookshelf_update_mixin.dart`（`BookshelfBatchDownloadResult`/`BookUpdateCheckResult`）、`bookshelf_import_mixin.dart`。

## Dependencies & Impact

- 上游：`models/book`、`engine/app_event_bus`、`services/{bookshelf_exchange_service,restore_service}`、`local_book/local_book_formats`、`widgets/book_cover_widget`、`database/dao`（經 provider mixins）、`di`。
- 下游影響：批次更新會呼叫 `DownloadService`/`BookSourceService`；匯入還原與 `services/backup` 共用。

## Key Flows

- 進入頁面 → 訂閱 `BookDao`/`BookGroupDao` → 依 `BookshelfSortMode` 排序顯示。
- `upBookshelf` 事件 → `BookshelfProvider` 重新整理。
- 批次下載/更新檢查：`BookshelfUpdateMixin` → `DownloadService`/`BookSourceService`。

## Change Entry Points & Routes

- 顯示/排序：`bookshelf_page.dart` + `bookshelf_provider_base.dart`。
- 批次更新下載：`provider/bookshelf_update_mixin.dart` + `services/download_service.dart`。
- 匯入還原/書架交換：`provider/bookshelf_import_mixin.dart` + `services/{restore_service,bookshelf_exchange_service}.dart`。

## Known Risks

- `upBookshelf` 事件與 `BookshelfProvider` 生命週期需對齊，頁面關閉後未解訂會漏更新或洩漏。
- 批次下載與 `downloads` 模組的佇列共用 `DownloadService`，需避免重複入隊。

## Do Not Do

- 不要在書架頁直接抓章節正文（層 book_detail/reader）。
- 不要在此新增非「書架」性質的頁面（feature freeze）。