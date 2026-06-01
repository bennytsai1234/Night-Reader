# 夜讀 Night Reader Atlas Index

## 用途與使用方式

- 在閱讀程式碼之前，使用此索引定位相關模組。
- 細節放在各模組文件；本文件保留路由、邊界與跨模組規則。
- Codebase Atlas 通常只需執行一次來初始化這份地圖。
- 後續的理解、修改、驗證或混合工作，請使用下方列出的主工作流程，不要重新執行 Codebase Atlas。
- 只有在使用者明確要求 rebuild、refresh、regenerate 或 rescan atlas 時，才重新掃描整個 repo 並重建本索引。

## 初始決策

- Atlas 模式：standalone（獨立，無參考範本）
- 工作語言：繁體中文（來自 `AGENTS.md` 明確規定）
- 參考範本模式：none（僅從本專案建立 atlas）
- 工作交付策略：no commit（只寫檔案，使用者自行 commit）
- 報告詳細度：technical（報告可包含模組名稱、檔案路徑與相關程式脈絡）
- 工作入口：Generic + Claude Code + Codex

已生成的入口 adapter：
- [通用 adapter](night_reader_adapter.md)
- Claude Code adapter：`.claude/skills/night-reader-atlas/SKILL.md`
- Codex adapter：`.agents/skills/night-reader/SKILL.md`

## 專案操作限制

以下規則繼承自現有的專案指引，所有工作流程都必須遵守：

**語言**
- 所有使用者溝通與專案規則討論使用繁體中文。

**技術棧**
- Flutter 3.41.6、Dart ^3.7.0
- 狀態管理：Provider + event_bus
- 資料庫：Drift + SQLite（程式碼由 build_runner 生成 `.g.dart`）
- 網路：Dio + cookie_jar + dio_cookie_manager
- 閱讀器：自製 Reader V2 排版引擎（Canvas 渲染）
- WebView：webview_flutter（書源驗證、後台 headless）
- TTS：flutter_tts + audio_service + just_audio
- JS 引擎：flutter_js（Dart 橋接）
- DI：get_it

**測試與分析**
- 靜態分析：`flutter analyze`
- 執行全部測試：`flutter test`

**發布流程**
- 先更新 `pubspec.yaml` 版本號並 commit，再建 tag
- 先推 branch（`git push origin HEAD`），再建 tag（`git tag vX.Y.Z`），再推 tag（`git push origin vX.Y.Z`）
- 不可為未推送的本地 commit 建立 tag
- tag 推上後，確認 GitHub Actions `android-release.yml` 已開始執行即可，不需等待 build 完成

**產品範圍**
- 這是小說閱讀器，不引入 Legado 的漫畫、RSS、WebDAV、字典、Mobi/PDF 或完整 Android 原版 UI/動畫

**跨模組注意**
- 書源、閱讀器、下載、快取、備份彼此耦合；修改其中一塊通常需要確認其他流程未受影響
- Reader V2 與 Source Manager 是 release 的重點回歸區域
- 書源驗證流程涉及 WebView、Cookie 與實際網站互動，容易出現只有真機或真實網站才會發生的問題

## 架構決策

跨模組決策記錄於此；模組級別決策記錄於各模組文件的 Known Risks 或 Do Not Do 欄位。

| 標題 | 選擇方案 | 涉及模組 | 理由 |
|------|----------|----------|------|
| （無） | — | — | — |

## 工作流程文件

日常工作從 adapter 進入，adapter 先讀此索引、用一句話確認專案用途，再路由至下列工作流程之一：

- 理解工作流程（read — 解釋、定位、審查、重現、評估風險）：[night_reader_investigate_workflow.md](night_reader_investigate_workflow.md)
- 修改工作流程（write — 所有程式碼修改）：[night_reader_change_workflow.md](night_reader_change_workflow.md)

共用技術文件（debugging、TDD、verification、code review、design grilling）放在 `night_reader_techniques/` 下，按需讀取。

## 模組列表

- [規則引擎](night_reader/rule_engine.md)
- [書源管理](night_reader/source_manager.md)
- [閱讀器 V2](night_reader/reader_v2.md)
- [書架與書籍](night_reader/bookshelf.md)
- [搜尋與探索](night_reader/search_explore.md)
- [下載與快取](night_reader/download_cache.md)
- [瀏覽器驗證](night_reader/browser.md)
- [設定與備份](night_reader/settings_backup.md)
- [應用基礎設施](night_reader/infrastructure.md)

## 跨模組參考

- [事件匯流排 event_bus](night_reader/event_bus.md) — 字串命名事件的發送/監聽對照（靜態工具看不見，需人工維護）

## 模組摘要

**規則引擎** (`lib/core/engine/`)
所有書源規則的解析與執行底層：AnalyzeRule、AnalyzeUrl、CSS/XPath/JSONPath/Regex 解析器、JS 引擎（flutter_js）、web_book 服務。規則解析失敗、JS 執行錯誤、書源抓取行為異常，從這裡開始。測試覆蓋豐富（`test/core/engine/`）。

**書源管理** (`lib/features/source_manager/` + `lib/core/services/` source 相關)
書源的完整生命週期：新增、刪除、匯入、匯出、有效性驗證（含 isolate 執行）、訂閱更新、偵錯。修改書源管理頁、書源驗證流程、訂閱更新行為，從這裡開始。

**閱讀器 V2** (`lib/features/reader_v2/`)
閱讀頁面的全部功能：排版引擎、Canvas 渲染、viewport（捲動/滑動）、runtime 狀態機、TTS 朗讀、設定面板、書籤、替換規則。8 層架構（content → runtime → layout → render → viewport → shell → application → features）。最複雜的模組，測試覆蓋豐富（`test/features/reader_v2/`），修改閱讀體驗從這裡開始。

**書架與書籍** (`lib/features/bookshelf/`, `book_detail/`, `replace_rule/` + 相關 core services/models/DAO)
書架顯示、書籍詳情、封面管理、閱讀紀錄、書籤管理、全域替換規則。修改書架 UI、書籍資料結構、閱讀進度，從這裡開始。

**搜尋與探索** (`lib/features/search/`, `lib/features/explore/`)
多書源並行搜尋與書源探索分類。依賴規則引擎和書源管理。修改搜尋行為或探索頁，從這裡開始。

**下載與快取** (`lib/core/services/download*.dart`, `features/cache_manager/`, `lib/core/local_book/`, `chapter_content*.dart`, `reader_chapter_content*.dart`)
章節批次下載（DownloadService、DownloadExecutor）、快取清理、本地書籍（TXT/EPUB/UMD）匯入解析、章節內容排程預備（ChapterContentPreparationPipeline）。修改離線功能或本地書籍支援，從這裡開始。

**瀏覽器驗證** (`lib/core/engine/web_book/headless_webview_service.dart`, `lib/core/services/webview_data_service.dart`, `backstage_webview.dart`)
後台 headless WebView，供規則引擎靜默執行 JS 重型書源。互動式瀏覽器驗證（登入、驗證碼）尚未實作，此類書源直接回報錯誤。修改 headless WebView 行為，從這裡開始。

**設定與備份** (`lib/features/settings/` + `backup_service.dart`, `restore_service.dart`, `export_book_service.dart`, `bookshelf_exchange_service.dart`, `chinese_utils.dart`)
應用設定（讀者設定、TTS 設定）、備份匯出、還原匯入、書架交換、繁簡轉換。修改設定頁面或備份格式，從這裡開始。

**應用基礎設施** (`lib/core/database/`, `network/`, `di/`, `storage/`, `config/`, `constant/`, `models/`, `services/`（event_bus、cookie_store、http_client 等）+ `main.dart`, `app_providers.dart`, `features/welcome/`, `about/`, `association/`, `lib/shared/`)
Drift 資料庫（21 tables、20 DAOs）、HTTP client（Dio + cookie）、GetIt DI 容器、儲存路徑、應用啟動、導覽、主題、版本更新、深連結。所有模組的底層依賴。修改 DB schema、新增 DAO、修改啟動流程，從這裡開始。
