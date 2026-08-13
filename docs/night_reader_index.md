# 夜讀 Night Reader Atlas Index

導航地圖。日常工作從 lead entrypoint skill 進入（讀此索引、挑相關模組、自帶變更/調查紀律）。此索引只裝地圖，不裝流程：它回答 *這是誰管的、我從哪開始、我不能弄壞什麼*；grep 回答 *確切位置在哪*。執行管理者（relay lead）與實作 agent 不讀此檔——前者由 dispatch plan 進入，後者在任務包的 Starting Points 收到所需模組文件路徑。Codebase Atlas 執行一次即建立此圖；之後僅在人類明確要求 refresh（只重掃有變動的模組）或 rebuild（整圖重建）時才重新執行。

工作語言：繁體中文 · 交付：commit and push · 回報：technical
Atlas built: 2026-08-13 · from commit e796448 · format 4

## Project Operating Constraints

繼承自既有專案指導原則（AGENTS.md / DEVELOPMENT.md），所有工作必須遵守：

- **語言**：對使用者與專案規則討論使用繁體中文。
- **維護政策**：**feature freeze** — 以維護、修 bug、效能調校、重構為主；不新增產品線功能。
- **發布流程**：GitHub Actions workflow（`v*` tag 觸發，可 `workflow_dispatch`），本機不做 build，APK 由 CI 建置。先推送 branch/commit，再建立並推送 tag；tag 推上後確認 workflow 已開始建置即可結束任務。
- **驗證指令**：`flutter analyze`、`flutter test`；書源相關變更優先用 `tool/` 腳本在真實書源上回歸（Linux host 需 QuickJS `.so`，由 `with_quickjs_env.sh` 自動找）；Drift schema 變更需 `dart run build_runner build --delete-conflicting-outputs`。
- **背景 isolate 契約**：Workmanager 背景任務在 isolate 執行，`callbackDispatcher` 內必須重跑 `configureDependencies()` 重建 DI（GetIt 不跨 isolate）；依 DEVELOPMENT.md 背景任務不可執行 JS 規則。**書源批量校驗 isolate 是例外**：在 isolate 內自行初始化 `NetworkService(ephemeral)` 與 JsEngine，以 `SourceValidationContext.runNonInteractive` 關閉 xhr/WebView 即可執行 JS 規則（`core/engine/js/js_engine.dart:50`）。
- **三方同步**：`SettingsProvider` ↔ `AppConfig` ↔ `PreferKey` 三者須保持一致；新增全域偏好鍵若 Model 層或 Reader 排版層要讀預設值，必須同時鏡像 `AppConfig`。

## Architecture Decisions

跨模組決策在此記錄。模組層決策寫入該模組的 Known Risks 或 Boundaries。

- **2026-08-13 全棧主版本升級（方案 B）**：Flutter 3.47 / Dart 3.13；Android AGP 9.1.0 / Gradle 9.3.1 / KGP 2.4.0 / compile+target SDK 37 / built-in Kotlin + 新版公開 DSL；移除舊 `BaseExtension` 路徑，root 改用 `LibraryExtension` 將外掛 compileSdk 只升不降拉齊 37。產品／資料／wire format／公開 API 不變。詳見 `docs/changes/completed/2026-08-13/full-stack-major-upgrade.md`。
- **受控 fork 策略（built-in Kotlin，經重開後重新確認）**：`third_party/{flutter_tts, flutter_js, file_picker}` 為 vendored 受控 fork，僅做 AGP 9 建置設定／相容 patch（runtime 與上游一致）。曾評估改走 legacy KGP 路線以丟掉 fork，但實測上游最新 hosted 版仍用 AGP 9 已移除的 `android{kotlinOptions}` 且無更新版本，故不可行。移除條件見各 `PATCHES.md`。file_picker 另含 win32 6 相容（供 host `flutter test`）。

## Module List

- [Engine](night_reader/engine.md) — 規則解析引擎
- [Data](night_reader/data.md) — 資料存取與儲存層
- [Infrastructure](night_reader/infrastructure.md) — 共用基礎架構
- [Services](night_reader/services.md) — 業務服務層
- [Reader](night_reader/reader.md) — 閱讀器 V2（八層架構 + hybrid 滾動引擎）
- [Source Manager](night_reader/source-manager.md) — 書源管理
- [Bookshelf](night_reader/bookshelf.md) — 書架與書籍詳情
- [Search](night_reader/search.md) — 搜尋與探索
- [App Shell](night_reader/app-shell.md) — 應用殼層與工具功能

## Module Summaries

### Engine

掌管非本地書籍的抓取與解析及本地 TXT 偵測切割：Legado 相容規則引擎（XPath/CSS/JSONPath/Regex/JS 五模式）、`WebBook` 業務調度、`CompleteContentFetcher` 正文完整性抓取、headless WebView、探索規則、事件匯流排（與 services 的第二套同名 bus 平行，互不相通）。書源抓不到／解析錯／規則語法／JS bridge 方法／本地格式支援的問題從這裡開始；規則行為變更影響全體書源。關鍵風險：JS 引擎 isolate 限制（校驗 isolate 可跑、Workmanager 不可）、登入關鍵字表兩處重複、`WebBook.getContentAwait` 為 dead code。

### Data

掌管 Drift SQLite 主庫（20 tables／20 DAO、schema v2）、資料契約模型（Book/BookSource/Chapter 等）、Dio 攔截器與 cookie、磁碟快取與路徑。改 schema、加 DAO、改全域網路行為、除錯持久化從這裡開始。schema 變更需 build_runner + migration（schema v2 自 init 起未真正遷移過，升 v3 要自行寫完整步驟）；`_partQuery()` 手寫 SQL 欄位清單是重複來源；背景 isolate 內 DAO 依賴走「可選注入或 isRegistered 降級」模式。

### Infrastructure

掌管 Provider 基類（`BaseProvider`）、GetIt DI 接線、`AppConfig` 靜態鏡像、`PreferKey`（195 鍵）、例外階層、無狀態工具、共用 widget、設計系統（theme/tokens/導航）與建置/發布工具鏈所有權。加全域偏好鍵、改 DI 容器、改設計系統、改發布流程從這裡開始。變更向下游所有模組擴散；CI 白名單不含大部分 core/shared（本機請跑全量 `flutter analyze`）。

### Services

業務協調層：書源調度（`BookSourceService`）、正文快取管線、批量校驗（isolate 池）、下載、TTS、備份/還原、換源、匯入匯出、網路與快取、系統整合，加上 `tool/` 真實書源驗證腳本。除錯下載失敗、TTS 播放、備份管線、校驗分類從這裡開始；凡「要動多個 DAO 又調 engine」的任務也從這裡開始。高風險面：健康判定邏輯三處重複、雙 AppEventBus 分裂（download 的 upBookshelf 不會被 BookshelfStateTracker 收到）、isolate 序列化手寫且無往返測試。部分服務有真機-only 失敗模式。

### Reader

八層閱讀引擎（shell → application → runtime → content → layout → render → viewport → features）＋ hybrid 滾動子系統（LayoutPump／BudgetGovernor／MeasurementStore／MetricsDiskCache／AnchorManager／DocumentIndex／ParagraphCache／AdmissionController）。生產路徑恆為 hybrid，legacy page-window 是測試維護的 dormant fallback。全專案最複雜、回歸風險最高（release 重點回歸區域）。任何閱讀 UX、排版、捲動、進度遺失、TTS 跟讀問題從這裡開始。關鍵風險：epoch 重建、MetricsDiskCache 版本化二進位格式（v3）、layoutSignature 確定性判定清單、`ReaderV2Location` 跨版本持久化合約。

### Source Manager

書源生命週期管理：列表（篩選/排序/分組）、多選批次操作、匯入（URL/檔案/剪貼簿，isolate 解析＋預覽）、批量校驗（isolate 池＋健康分類持久化）、規則編輯器（六標籤頁）、除錯終端機、分組管理。專案政策的重點回歸區域。加匯入格式、改校驗階段/健康分類、除錯規則編輯器從這裡開始。注意：健康分類判定（`_applyHealthGroup`）在 service 與 isolate 兩處重複、`runtimeHealth` 是第三份語義；訂閱式更新仍不存在。

### Bookshelf

書架首頁與書籍詳情：CRUD、排序、批次更新/下載/刪除、本機書籍與書架 JSON 匯入/匯出、詳情頁（目錄、換源、封面、預下載、匯出 TXT）。書架 UI 或書籍資料流從這裡開始；進度/書籤的**寫入**在 reader 模組，本模組只顯示。換源底層遷移屬 services（`SourceSwitchService`），詳情頁與閱讀器兩條換源路徑語意必須一致；`upBookshelf` 事件（字串 `'upBookToc'`）是硬契約，任何書架歸屬變更都必須觸發。

### Search

多源並行搜尋（`SearchModel` 重算式合併引擎：併發派發、同源去重、跨源合併成卡、三級相關度排序、精準搜尋）與發現分類瀏覽（`ExploreProvider`、Legado 相容 flexbox）。改搜尋 UX、合併規則、結果篩選、探索排版從這裡開始；書源納入門檻（`isSearchEnabledByRuntime`／`canParticipateInDiscovery`）的判定在 services 側。搜尋與探索共用同一條書源派發管線；`thread_count` 與換封面共用並行數設定。

### App Shell

App 進入點（`main.dart`：DI、crash handler、Workmanager、splash 序列）、全域 Provider 註冊、底部三 tab 導航殼、設定頁群、關於/更新/崩潰日誌、外部意圖處理（association）、下載佇列管理、替換規則 Provider。導航、設定 UI、外部意圖、啟動順序的變更從這裡開始。已知缺口：AndroidManifest 沒有 deep link / `ACTION_SEND` intent filter（Dart 側流程空轉）、Workmanager 初始化但零任務排程、`DataPrivacySettingsPage` 與 `ReplaceRuleProvider` 為 dead code。