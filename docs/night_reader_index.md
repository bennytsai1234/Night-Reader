# 夜讀 Night Reader Atlas Index

夜讀是一款以長篇小說閱讀為核心的 Flutter 閱讀器，不內建任何書籍，提供書源規則解析、本地排版引擎、語音朗讀與離線快取。日常工作從 atlas 入口 skill 進入：讀本索引、挑相關模組文件、自帶變更/調查紀律——本索引只放導航地圖，不放流程。

- 先用索引定位要動的模組，細節留在各模組文件。
- Codebase Atlas 只跑一次建立此地圖。唯有使用者明確要求重建/刷新/重掃時才重跑——那會從目前 repo 實況全掃重建本索引。

工作語言：繁體中文 · 交付：no commit · 回報：technical

## Project Operating Constraints

繼承自既有專案指引，所有工作都須遵守：

- **語言**：使用者溝通與 atlas 文件皆用繁體中文（AGENTS.md / 全域 CLAUDE.md 指示）。
- **維護政策：feature freeze（功能凍結）**。本專案目前不接受新產品線功能；工作以維護、修 bug、效能調校、重構、既有功能內部改進為主。不要把新功能當成 bug 來推動。
- **範圍界線**：本專案是小說閱讀器，不引入其他產品線（漫畫、RSS 等）。
- **本機作業**：本機不做 build；只跑 `flutter analyze`、`flutter test`（必要時 `dart run build_runner build`）。APK 建置與發布一律在 GitHub Actions。
- **關聯性**：書源、閱讀器、下載、快取、備份彼此相關，改其中一塊通常要檢查其他流程（DEVELOPMENT.md）。
- **回歸重點區**：Reader V2 與 Source Manager 是 release 的重點回歸區域，變更後需加強驗證（DEVELOPMENT.md）。
- **書源驗證特性**：書源驗證涉及 WebView、Cookie 與真實網站互動，容易出現僅真機/真實網站才復現的問題；除錯時優先用 `tool/` 下的驗證腳本（DEVELOPMENT.md）。
- **Release 流程**：由 `.github/workflows/android-release.yml` 處理，tag 為 `v*`。標準流程：`flutter pub get → flutter analyze → flutter test → git push origin HEAD → git tag vX.Y.Z → git push origin vX.Y.Z`。需更新版號時先改 `pubspec.yaml` 並先提交。tag 推上後確認 GitHub Actions 的 Android Release workflow 已開始建置，看到建置中即可結束任務。
- **Flutter/Dart 版本**：Flutter `3.41.6`、Dart SDK `^3.7.0`、Java 17。
- **測試指令**：`flutter analyze`、`flutter test`；書源驗證用 `tool/` 腳本。
- **機密/著作權**：App 為純工具，不分發書籍或書源；不得引入任何書籍內容或第三方書源到 repo。

## Architecture Decisions

跨模組決策於開發中記錄於此表。模組層決策放各模組的 Known Risks 或 Do Not Do。

| 標題 | 選定選項 | 影響模組 | 理由 |
|---|---|---|---|
| _（初始化時為空）_ | | | |

## Module List

- [foundation](night_reader/foundation.md) — 應用殼、入口、共用層與跨切面 core 基礎
- [models](night_reader/models.md) — 資料契約層（Book / BookSource / Chapter 等）
- [database](night_reader/database.md) — Drift 持久層與 DAO
- [engine](night_reader/engine.md) — 規則引擎（AnalyzeRule / AnalyzeUrl / JS / WebBook）
- [services](night_reader/services.md) — 業務服務層（書源調度、TTS、備份、日誌…）
- [bookshelf](night_reader/bookshelf.md) — 書架頁與批次更新
- [book_detail](night_reader/book_detail.md) — 書籍詳情、目錄、換源、封面
- [search_explore](night_reader/search_explore.md) — 多書源搜尋與發現分類
- [source_manager](night_reader/source_manager.md) — 書源管理、校驗、偵錯、替換規則
- [reader](night_reader/reader.md) — Reader V2 閱讀器主流程
- [settings_about](night_reader/settings_about.md) — 設定、關於、版本更新
- [downloads](night_reader/downloads.md) — 背景下載佇列與快取管理頁
- [association](night_reader/association.md) — 深連結與檔案分享外部意圖

## Module Summaries

- **foundation**：擁有 App 入口（`main.dart`、`app_providers.dart`）、啟動殼（`features/welcome`）、共用 UI（`lib/shared`）、與跨切面 core（`base/config/constant/di/exception/local_book/storage/utils/widgets/network`）。未來工作從這裡開始：啟動崩潰、主題/Token、全域 Provider 註冊、Dio 攔截器、路徑/快取、Preference key、本機書格式偵測。症狀指向：開機黑屏/崩潰、主題顯示異常、全域狀態未注入、Cookie/UA 處理、深連結路由前的前置。
- **models**：擁有所有資料模型與契約（`core/models`，含 `Book`、`BookSource`、`Chapter`、`ReplaceRule`、`RuleDataInterface`、`BookExtensions`、`BookSourceLogic` 等）。未來工作從這裡開始：新增/修改資料欄位、序列化、JS 引擎可見的擴充方法、書源規則資料結構。症狀指向：全 App 編譯斷層、序列化/備份還原不相容、JS `java.*` 取得 book 欄位錯誤。
- **database**：擁有 Drift 主庫、所有 table 定義與 20 個 DAO（`core/database`）。未來工作從這裡開始：新增欄位/表、遷移、查詢效能、TypeConverter。症狀指向：資料升版崩潰、查詢漏資料、備份還原 schema 不符。注意：改 table 必須跑 `build_runner` 重新生成 `.g.dart`。
- **engine**：擁有規則引擎（`core/engine`：`AnalyzeRule`、`AnalyzeUrl`、`RuleAnalyzer`、四選擇器 CSS/XPath/Regex/JSONPath、`JsEngine`/`JsExtensions`、`WebBook`、`HeadlessWebViewService`、`ExploreUrlParser`、`AppEventBus`）。未來工作從這裡開始：書源規則解析失敗、JS 腳本執行、非同步 JS bridge、反爬字體解密、內容/目錄抓取、發現分類解析、跨模組事件匯流。症狀指向：某書源抓不到/格式錯、JS 報錯、多書源並發卡住、換頁/事件未廣播。release 重點回歸區。
- **services**：擁有業務服務層（`core/services`：`BookSourceService`、`DownloadService`、`TTSService`、`CheckSourceService`、`SourceDebugService`、`SourceSwitch/UpdateService`、`Backup/RestoreService`、`LocalBookService`、`ReaderChapterContentStore`、`NetworkService`、`HttpClient`、`AppLog`、`CrashHandler` 等）。未來工作從這裡開始：抓書流程調度、下載排程、TTS 朗讀服務、備份還原、書源校驗/偵錯、換源、章節正文取存、網路層組裝、日誌/崩潰。症狀指向：抓章節失敗、下載佇列不動、TTS 不出聲、備份缺資料、校驗誤判、換源異常、全域日誌遺失。
- **bookshelf**：擁有書架頁與批次更新匯入（`features/bookshelf`：`BookshelfPage`、`BookshelfProvider`+mixins）。未來工作從這裡開始：書架排序/分組顯示、批次下載/更新檢查、匯入還原書架、書架交換、本地書匯入入架。症狀指向：書架不重新整理、批次更新卡住、匯入失敗。相依 `AppEventBus.upBookshelf`。
- **book_detail**：擁有書籍詳情頁、目錄、下載佇列、換源、封面替換（`features/book_detail`：`BookDetailPage`、`BookDetailProvider`、`BookDetailChangeSourceProvider`、`ChangeCoverProvider`）。未來工作從這裡開始：詳情顯示、目錄操作、預下載、換源搜尋、封面变更。症狀指向：詳情空白、目錄載入失敗、換源找不到、封面存取錯誤。
- **search_explore**：擁有多書源搜尋與發現分類瀏覽（`features/search` + `features/explore`：`SearchProvider`、`ExploreProvider`、`ExploreShowProvider`）。未來工作從這裡開始：搜尋範圍/排序、搜尋歷史、發現分類展開與結果載入。症狀指向：搜尋無結果、發現頁空白、分類切換錯誤。
- **source_manager**：擁有書源管理、批次校驗、逐階段偵錯、編輯器、訂閱、與替換規則管理（`features/source_manager` + `features/replace_rule`）。release 重點回歸區。未來工作從這裡開始：書源：書源匯入/匯出/啟停/校驗、書源編輯、規則偵則偵錯、訂閱更新、全域/章內替換規則 CRUD。症狀指向：匯入失敗、校驗誤判、偵錯 log 缺、編輯器欄位錯、替換規則不生效。注意真機/真實網站才復現的 cookie/WebView 問題。
- **reader**：擁有 Reader V2 閱讀器主流程，八層架構（`features/reader_v2`：screen / session / use_cases / chapter / layout / render / viewport / features 子面板含 TTS、settings、menu、auto_page、bookmark、replace_rule）。release 重點回歸區。未來工作從這裡開始：排版/渲染、章節預載與進度、TTS 逐段高亮、閱讀設定、點擊區、書籤、章內替換、換源 sheet。症狀指向：排版錯位/崩潰、翻頁卡頓、預載失敗、TTS 高亮偏移、設定不保留。
- **settings_about**：擁有設定頁群與關於/更新檢查（`features/settings` + `features/about`：`SettingsProvider`、各設定子頁、`AboutPage`、`UpdateCheckRunner`）。未來工作從這裡開始：主題/閱讀/TTS/備份/隱私設定、版本更新檢查、崩潰日誌頁。症狀指向：設定不儲存、主題未套用、更新檢查失敗。`SettingsProvider` 與 `AppConfig` 雙向同步。
- **downloads**：擁有背景下載佇列管理頁與快取清理（`features/cache_manager` + `core/services` 中 `DownloadService`/scheduler/executor）。未來工作從這裡開始：下載佇列 UI、任務暫停/重試/刪除、快取清理、佇列與 `DownloadService` 互動。症狀指向：佇列不更新、任務卡住、快取未清、背景任務未執行。
- **association**：擁有外部意圖處理（`features/association`：`AssociationHandlerService`，深連結 URI 與分享檔案）。未來工作從這裡開始：深連結開書、分享 TXT/EPUB 匯入、意圖對話框。症狀指向：從連結/分享開啟失敗、本地書匯入無反應。
