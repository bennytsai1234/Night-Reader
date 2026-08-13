# infrastructure

## Responsibility

共用基礎架構模組，掌管所有 feature 與 core 模組都依賴的橫切設施：Provider 基類、全域配置鏡像（`AppConfig`）、GetIt DI 接線、偏好鍵目錄（`PreferKey`）、例外階層、無狀態工具函式、共用 widget、設計系統（theme/tokens/navigation）、開書路由。另外持有建置／發布工具鏈的所有權：`pubspec.yaml`（版本元資料）、`android/` 建置設定、`.github/workflows/android-release.yml`（發布流程細節以索引的 Project Operating Constraints 為主）。

未來工作從這裡開始的時機：新增全域偏好鍵、更動 DI 容器、主題系統改動、任何跨模組共用的 widget／工具改動、版本與發布流程變更。此處的任何變更都會向下游所有模組擴散——改之前先確認每個使用端。

## Scope

- `lib/core/base/base_provider.dart` — `BaseProvider(ChangeNotifier)`，規範 loading／error／`CancelToken` 生命週期與 `runTask` 錯誤處理。**目前僅有一個子類**：`SourceDebugProvider`（source_manager 的規則除錯工具）。
- `lib/core/config/app_config.dart` — 靜態鏡像 `AppConfig`，4 個欄位：`replaceEnableDefault`、`readerPageAnim`、`readerLastLineSpacingCompensation`、`readerV2ContentJustify`。讓 Model 層（`book_extensions.dart`）與 Reader V2 排版層（`hybrid_reader_screen.dart`）不需 BuildContext 即可讀全域預設值。
- `lib/core/constant/` — `PreferKey`（195 個 shared_preferences 鍵）、`AppPattern`（全域正則）、`BookType`（位元旗標）、`SourceType`（含已 deprecated 的 `rss`，指向 Legado 對應的 `file`）。
- `lib/core/di/injection.dart` — `getIt` + `configureDependencies()`，唯一 DI 註冊點：Logger、`AppDatabase`、17 個 DAO、`NetworkService`、`TTSService`、預載的 `SharedPreferences`；最後並行初始化 `CrashHandler.init()`、`NetworkService.init()`、`TTSService.init()`。
- `lib/core/exception/app_exception.dart` — `AppException` 抽象基類 + 14 個子類（`NetworkException`、`ParsingException`、`SourceException`、`DownloadException`、`ConcurrentException` 等），`ParsingException.toString()` 會組裝 mode／rule／url／原始錯誤。
- `lib/core/utils/` — 6 檔無狀態工具：`string_utils`（全半角、中文數字轉 int）、`network_utils`（絕對 URL、域名）、`encoder_utils`（escape／base64／MD5）、`html_formatter`、`lru_map`（`LruMap` 快取）、`ttf_parser`（防盜字體還原，被 `analyze_rule_script.dart` 的 `queryTTF` 使用）。
- `lib/core/widgets/book_cover_widget.dart` — `BookCoverWidget`，支援 `memory://`（`ResourceService`）、`local://`／`file://`、HTTP（`cached_network_image`）四種來源 + 文字封面 fallback。
- `lib/shared/theme/` — 雙軌設計系統：
  - `app_tokens.dart`（`AppPalette`／`AppSpacing`／`AppRadius`）、`app_text_styles.dart`（字級）、`context_ext.dart`（`BuildContext` 語意色 extension）。
  - `app_theme.dart`（`AppTheme.lightTheme/darkTheme` 靜態 ThemeData + `ReadingTheme` 閱讀排版模型，`AppTheme.init()` 讀文件 `readConfig.json`）。
  - `custom_app_theme.dart`（`buildAppTheme(colors, brightness)`，**main.dart 現役路徑**）+ `theme_customization.dart`（`AppUiThemeColors`／`ReaderAreaThemeColors` 可自訂色彩模型）。
- `lib/shared/widgets/` — `AppBottomSheet`（含 `SheetSection`）、`SourceOptionTile`（換源選項清單列）。
- `lib/shared/navigation/` — `appRouteObserver`（全域 `RouteObserver` 單例）、`BookOpenRoute`（開書轉場 `PageRouteBuilder`，淡入 + 上滑，280ms/220ms）。
- 建置／發布工具鏈 — `pubspec.yaml`（version 0.2.145+159，sdk ^3.13.0）、`android/`（`applicationId com.inkpage.reader`、minSdk 24、targetSdk 37、ndk 28.2.13676358）、`.github/workflows/android-release.yml`（Flutter 3.47.0 釘版，arm64-v8a 單 ABI）。
- 測試 — `test/app_exception_test.dart`、`test/lru_map_test.dart`、`test/core/widgets/book_cover_widget_test.dart`、`test/shared/theme/theme_customization_test.dart`、`test/shared/widgets/app_bottom_sheet_test.dart`。`BaseProvider`、`AppConfig`、`PreferKey`、`utils/` 其餘檔案、`app_theme.dart` 無直接測試。

## Dependencies & Impact

- **上游**：`shared_preferences`（鍵定義與讀寫）、`provider`（`BaseProvider` 基底）、`get_it`、`dio`（`CancelToken`／`DioException`）、`logger`（`AppLog`）、`cached_network_image`（封面）、`crypto`、`path_provider`（`AppTheme.init` 讀文件）；`third_party/` 受控 fork（flutter_tts、flutter_js、file_picker）只在建置層面影響本模組（AGP 9 相容 patch）。
- **下游（呼叫者）**：
  - `PreferKey` 被 6 個檔案直接引用：`settings_provider.dart`、`reader_v2_prefs_repository.dart`、`tts_service.dart`、`check_source_service.dart`、`bookshelf_logic_mixin.dart`、`reader_v2_tts_controller.dart`。
  - `AppConfig` 讀者：`book_extensions.dart:75,85`（`replaceEnableDefault`／`readerPageAnim`）、`reader_v2_prefs_repository.dart`（`readerLastLineSpacingCompensation`）、`hybrid_reader_screen.dart:283,816`（`readerV2ContentJustify`）。
  - `BookOpenRoute` 被 bookshelf、book_detail、reader_v2 三處用來開書。
  - `BookCoverWidget` 被 bookshelf、search、explore、book_detail 使用（`bookshelf_page.dart`、`search_result_item.dart`、`explore_book_item.dart`、`book_info_header.dart`）。
  - `buildAppTheme` 由 `main.dart` 用 `ThemeSettingsProvider.effectiveAppLight/Dark` 驅動；`AppTheme.readingThemes` 被 reader_v2 的 settings controller／sheets 直接讀取。
  - `AppLog` 全專案 105+ 處使用（services 模組持有實作）。
- **反向依賴注意**：`BookOpenRoute` import `features/reader_v2/...`（`ReaderV2OpenTarget`、`ReaderV2ReadTimeScope`、`ReaderV2Page`）——shared 向上依賴 features 是刻意但脆弱的耦合；`appRouteObserver` 被 `ReaderV2ReadTimeScope` 訂閱。

## Key Flows

- **啟動流程**：`main.dart` → `configureDependencies()`（註冊所有單例 + 預載 SharedPreferences）→ `MultiProvider(AppProviders.providers)` → `ReaderApp`（`Consumer2<SettingsProvider, ThemeSettingsProvider>` 驅動 `buildAppTheme`）→ 第一幀後 `DefaultData.initDeferred()`（其中 `AppTheme.init()` 讀 `readConfig.json` 載入 `readingThemes`，失敗或空則 fallback 內建 7 主題）。
- **設定三方同步**（跨模組契約，見索引 Project Operating Constraints）：`SettingsProvider` 建構時同步讀 prefs 寫入欄位並鏡像到 `AppConfig.replaceEnableDefault`；`ReaderV2PrefsRepository.load()` 讀取後 `_syncAppConfig()` 鏡像 `readerLastLineSpacingCompensation`；Model 層（`book_extensions.dart`）與排版層（`hybrid_reader_screen.dart`）無 context 讀 `AppConfig`。
- **背景 isolate 流程**：`callbackDispatcher`（`main.dart:43`）被 Workmanager 呼叫時重跑 `configureDependencies()` 建立獨立 GetIt 容器；`GetIt` 狀態不跨 isolate 共享，背景任務需要的新服務必須在該入口重新註冊。
- **錯誤流程**：Provider 用 `BaseProvider.runTask()` → `DioException.cancel` 靜默返回 null、`AppException` 取 `.message`、其餘記 `AppLog.e`；UI 層用 `lastError` 做型別分支。
- **發布流程**：`flutter pub get && flutter analyze && flutter test` → push branch → tag `vX.Y.Z` → push tag → CI 建 signed arm64-v8a APK 並發 GitHub Release（詳見索引）。

## Change Entry Points & Routes

- **新增偏好鍵**（最常見任務）：1) `PreferKey` 加鍵 → 2) `SettingsProvider`（若屬全域設定）加欄位 + `_loadFromPrefs` + setter → 3) 若 Model 層要讀預設值，鏡像到 `AppConfig` → 4) 若屬 Reader 設定，在 `reader_v2_prefs_repository.dart` 加 snapshot 欄位 + save 方法。三步驟檔案必須同步改，否則契約漂移。
- **主題改動**：token 來源是 `app_tokens.dart` → 新主題路徑 `custom_app_theme.dart`／`theme_customization.dart`（顏色模型序列化）→ 持久化鍵在 `theme_settings_provider.dart:28-43` 的 private 常數（`theme_app_light_custom_v1` 等，**不在 PreferKey 目錄**）→ 舊路徑 `app_theme.dart`（`lightTheme/darkTheme` 仍被測試使用）。改主題需同時檢查兩個路徑與測試 `theme_customization_test.dart`。
- **開書流程改動**：`BookOpenRoute`（shared/navigation）與 `reader_v2_open_target.dart`／`reader_v2_read_time_scope.dart`（features/reader_v2/session）綁定，三處同步。
- **DI 變更**：`injection.dart` 是唯一註冊點；新增背景任務需要的服務必須同步加進 `callbackDispatcher` 的註冊流程。
- **`BaseProvider` 變更**：目前只有 `SourceDebugProvider` 一個子類——改前檢查該檔案即可（舊文件的「27+ ViewModels」已不成立）。
- **封面相關**：`book_cover_widget.dart` 與 `ResourceService`、`BookCoverStorageService`（services）連動。

## Known Risks

- **`AppConfig.readerPageAnim` 契約漂移（TODO）**：`book_extensions.dart:85` 讀它當翻頁動畫預設，但程式碼中**沒有任何寫入端**——舊同步點 ReaderSettingsMixin 已刪除，ReaderV2 也不寫 `PreferKey.readerPageTurnMode`（鍵存在但無人使用）。目前等效恆為 0（滑動）。未來接 ReaderV2 的翻頁模式設定時要重新接線。
- **CI 白名單盲區**：release workflow 的 `flutter analyze`／`flutter test` 只涵蓋指定路徑（reader_v2、source_manager、theme_settings_provider 等），**不含 `lib/core/`（除少數檔案）、`lib/shared/` 大部分**——基礎架構檔案壞掉時 CI 可能照樣綠燈。本機驗證請跑全量 `flutter analyze`。
- **雙軌主題並存**：`main.dart` 走 `buildAppTheme`（自訂色彩），測試（about／settings 等 4+ 個）仍用 `AppTheme.lightTheme/darkTheme` 靜態主題。兩軌視覺細節已不同步（例如 dialog 圓角、elevation），改一軌要對照另一軌。
- **`AppTheme.readingThemes` 全域 mutable static**：無同步機制；`AppTheme.init()` 讀的是 Android 遺產 JSON 格式 `readConfig.json`（文件目錄），Reader V2 的 theme index 全部依賴 `readingThemes` 順序——文件損壞或手動編輯可能造成 index 越界（settings controller 有 clamp 但 sheets 直接索引）。
- **`BookCoverWidget._failedCoverSources` 全域 static Set 永不清除**：session 內失敗的 URL 永不重試；長時間使用可能累積。
- **`TtfParser` 是簡化實作**（`ttf_parser.dart:143` 註解）：特徵取字形數據偏移與長度（base64），與原 Android `QueryTTF` 的輪廓點特徵不同——防盜字體還原率可能較低，屬已知取捨。
- **`PreferKey` 195 鍵無命名空間**：跨 feature 撞名只能靠 review；另有 `rss = file` 的 deprecated 對位（`source_type.dart:10`）。
- **舊文件已過時**：過去的 infrastructure.md 記載「229 鍵」「27+ ViewModels extends BaseProvider」「SplashPage 建立 AppProviders」——均與現況不符（現為 195 鍵、1 個子類、`main.dart` 直接建立）。

## Boundaries

- **三方同步契約（硬規則）**：`SettingsProvider` ↔ `AppConfig` ↔ `PreferKey` 三者須一致（索引 Project Operating Constraints 明列）；新增 shared_preferences 鍵若 Model 層要讀，必須同時鏡像 `AppConfig`。
- **不要新增 `AppConfig` 之外的 mutable static 狀態**：沒有同步故事。
- **主題目錄的平台潔淨度已分化**：`app_theme.dart` 已 import `dart:io`／`path_provider`（讀 `readConfig.json`），但 `app_tokens.dart`、`custom_app_theme.dart`、`theme_customization.dart`、`context_ext.dart` 保持純 Flutter——不要在後者加平台依賴。
- **發布工具鏈規則**：版本元資料改 `pubspec.yaml` 須先 commit 再 tag；release 只產 arm64-v8a 單 ABI；CI 釘 Flutter 3.47.0；本機不做 build；`workflow_dispatch` 只建置不發布（避免假 release）。
- **建置層面受控 fork**：`third_party/` 三個 fork 僅做 AGP 9 建置相容 patch（詳見各 `PATCHES.md`），全棧版本（AGP 9.1.0／Gradle 9.3.1／SDK 37）有 ADR 決策——不要降版或改回 legacy KGP 路線。
- **維持 feature freeze**：此模組以維護、修 bug、重構為主；不新增產品線功能。
- **`SourceType.rss` 已 deprecated**：新程式碼用 `SourceType.file`（Legado 對應）。