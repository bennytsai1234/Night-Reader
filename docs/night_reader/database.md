# database

## Responsibility

- Drift SQLite 持久層：主資料庫、所有 table 定義與 20 個 DAO，是 App 本機資料的唯一來源。
- 未來工作從這裡開始：新增欄位/表、遷移、查詢效能、TypeConverter。

## Scope

- `lib/core/database/app_database.dart` + `app_database.g.dart` — `class AppDatabase extends GeneratedDatabase`，匯入所有 tables/DAO。
- `lib/core/database/tables/app_tables.dart` — 所有 Drift table（`Books`、`BookSources`、`Chapters`、`Bookmarks`、`BookGroups`、`Cache`、`Cookie`、`DictRule`、`Download`、`HttpTts`、`KeyboardAssist`、`ReadRecord`、`ReaderChapterContent`、`ReplaceRule`、`RuleSub`、`SearchBook`、`SearchHistory`、`SearchKeyword`、`Server`、`SourceSubscription`、`TxtTocRule`）+ TypeConverters（`EmptyStringConverter` 等，605 行）。
- `lib/core/database/dao/` — 20 個 `@DriftAccessor` DAO，各附 `.g.dart` 生成檔：`book_dao.dart`（`BookDao`）、`book_source_dao.dart`（`BookSourceDao`，含 part 查詢）、`chapter_dao.dart`、`bookmark_dao.dart`、`book_group_dao.dart`、`cache_dao.dart`、`cookie_dao.dart`、`dict_rule_dao.dart`、`download_dao.dart`、`http_tts_dao.dart`、`keyboard_assist_dao.dart`、`read_record_dao.dart`、`reader_chapter_content_dao.dart`、`replace_rule_dao.dart`、`rule_sub_dao.dart`、`search_book_dao.dart`、`search_history_dao.dart`、`search_keyword_dao.dart`、`server_dao.dart`、`source_subscription_dao.dart`、`txt_toc_rule_dao.dart`。

## Dependencies & Impact

- 上游：經 `core/di/injection.dart` 注入，被幾乎所有 services 與 feature providers 使用（`getIt<XxxDao>()`）。
- 下游影響：table/欄位變更連動 `models`、`services/backup` 還原、各 DAO 查詢方法。
- 相依 `models`（型別）、`drift`/`drift_flutter` 套件、`build_runner`（生成 `.g.dart`）。

## Key Flows

- DI 註冊 `AppDatabase` 與所有 DAO 為單例。
- 各 DAO 提供 `watch*`（Stream）與單次查詢；`BookSourceDao` 有 `watchAll` 供 explore/bookshelf 訂閱。
- `backup` 經 DAO 匯出全表資料；`restore` 寫回。

## Change Entry Points & Routes

- 新增欄位/表：改 `tables/app_tables.dart` → 在 DAO 加方法 → 跑 `dart run build_runner build` 重新生成 `.g.dart` → 處理 schema migration（Drift `schemaVersion` + `MigrationStrategy`）→ 檢查 `services/backup_service.dart` 匯出清單。
- 查詢效能：先看對應 DAO，檢查 index 與 `watch*` 的 Stream 觸發頻率。

## Known Risks

- 忘記跑 `build_runner` 會使 `.g.dart` 與 table 不同步，編譯/執行崩潰。
- schema migration 未處理會在升版後對既有使用者崩潰。
- TypeConverter 行為（如空字串）若有改動會影響所有已存資料。

## Do Not Do

- 不要手改 `.g.dart` 生成檔。
- 不要在 DAO 放跨表的業務流程（層 services）。
- 不要在 table 定義引入對 `dio`/`engine` 的依賴。