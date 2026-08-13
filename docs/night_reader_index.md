# 夜讀 Night Reader Atlas Index

導航地圖。日常工作從 lead entrypoint skill 進入（讀此索引、挑相關模組、自帶變更/調查紀律）。Delegated subagent 不讀此檔——它們在 task contract 中收到所需模組路徑。Codebase Atlas 執行一次即建立此圖；僅在明確要求重建/重新掃描時才重新執行。

工作語言：繁體中文 · 交付：no commit · 回報：technical

## Project Operating Constraints

繼承自既有專案指導原則，所有工作必須遵守：

- **語言**：對使用者與專案規則討論使用繁體中文。
- **維護政策**：**feature freeze** — 以維護、修 bug、效能調校、重構為主；不新增產品線功能。
- **發布流程**：GitHub Actions workflow（`v*` tag 觸發），本機不做 build，APK 由 CI 建置。
- **驗證指令**：`flutter analyze`、`flutter test`；書源相關變更用 `tool/` 驗證腳本；schema 變更需 `dart run build_runner build --delete-conflicting-outputs`。
- **背景限制**：Workmanager 在 Isolate 執行，需重新初始化 DI，且不可執行 JS 規則（FFI 不跨 isolate）。
- **三方同步**：`SettingsProvider` ↔ `AppConfig` ↔ `PreferKey` 三者須保持一致。

## Architecture Decisions

跨模組決策在此記錄。模組層決策寫入該模組的 Known Risks 或 Do Not Do。

- **2026-08-13 全棧主版本升級（方案 B）**：Flutter 3.47 / Dart 3.13；Android AGP 9.1.0 / Gradle 9.3.1 / KGP 2.4.0 / compile+target SDK 37 / built-in Kotlin + 新版公開 DSL；移除舊 `BaseExtension` 路徑，root 改用 `LibraryExtension` 將外掛 compileSdk 只升不降拉齊 37。產品／資料／wire format／公開 API 不變。詳見 `docs/changes/completed/2026-08-13/full-stack-major-upgrade.md`。
- **受控 fork 策略（built-in Kotlin，經重開後重新確認）**：`third_party/{flutter_tts, flutter_js, file_picker}` 為 vendored 受控 fork，僅做 AGP 9 建置設定／相容 patch（runtime 與上游一致）。曾評估改走 legacy KGP 路線以丟掉 fork，但實測上游最新 hosted 版仍用 AGP 9 已移除的 `android{kotlinOptions}` 且無更新版本，故不可行。移除條件見各 `PATCHES.md`。file_picker 另含 win32 6 相容（供 host `flutter test`）。

## Module List

- [Engine](night_reader/engine.md) — 規則解析引擎
- [Data](night_reader/data.md) — 資料存取與儲存層
- [Infrastructure](night_reader/infrastructure.md) — 共用基礎架構
- [Services](night_reader/services.md) — 業務服務層
- [Reader](night_reader/reader.md) — 閱讀器 V2（八層架構）
- [Source Manager](night_reader/source-manager.md) — 書源管理
- [Bookshelf](night_reader/bookshelf.md) — 書架與書籍詳情
- [Search](night_reader/search.md) — 搜尋與探索
- [App Shell](night_reader/app-shell.md) — 應用殼層與工具功能

## Module Summaries

### Engine
Owns the rule parsing pipeline (HTML/CSS/XPath/JSONPath/Regex/JS), WebBook service, headless WebView, event bus, and local TXT parsing. Start here when investigating crawl failures, rule debug issues, or adding a new rule type. Key risk: JS engine cannot run in background isolates.

### Data
Owns the Drift SQLite database (20 DAOs, schema v2), data contract models (Book, BookSource, Chapter, etc.), network interceptors/cookies, and disk cache. Start here when changing storage schema, adding a DAO, or debugging data persistence. Schema changes require build_runner + migration.

### Infrastructure
Owns the Provider base class, DI wiring (`GetIt`), config mirror (`AppConfig`), preference keys, shared theme/tokens, and utility functions. Start here when adding a global preference, changing the DI container, or modifying the design system. Changes here cascade to every module.

### Services
Owns the orchestration layer: book source dispatch, download executor, TTS (flutter_tts/audio_service/just_audio), backup/restore, source validation, and logging. Start here when debugging download failures, TTS playback issues, or the backup pipeline. Some services (TTS, download) have real-device-only failure modes.

### Reader
Owns the 8-layer reading engine (shell → application → runtime → content → layout → render → viewport → features) with double-track navigation (scroll + page). The most complex and highest-regression-risk module. Start here for any reading UX, typography, or layout bug. Key risk: epoch reconstruction when content changes mid-session.

### Source Manager
Owns source import/export (network + local), batch validation in isolate, rule debug tool, and subscription updates. Heavy regression area per project policy. Start here when adding import formats, changing validation logic, or debugging the rule editor.

### Bookshelf
Owns bookshelf CRUD, batch update/import, book detail page (TOC, source switching, cover), reading progress, and bookmarks. Start here for bookshelf UI changes or book metadata flow. Proximity to Reader and Source Manager means cross-module sync is common.

### Search
Owns multi-source parallel search (concurrent dispatch, merge, rank) and explore/category browsing. Start here for search UX changes, explore page layout, or adding search ranking heuristics. Search and Explore share the same source dispatch pipeline.

### App Shell
Owns the app entry point, splash → navigation boot flow, deep linking/file share intents, settings pages, download queue management, and global replace rules. Start here for navigation changes, settings UI, or external intent handling. Deep linking and file share are currently known gaps with active intent placeholder.
