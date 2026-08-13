# app-shell — 應用殼層、導航與工具頁面

## Responsibility

掌管 App 生命週期起手式與殼層：進入點（`main.dart`）負責 DI 初始化、崩潰攔截、Native splash 銜接、Workmanager 初始化；`app_providers.dart` 集中註冊全域 Provider；`features/welcome/main_page.dart` 是底部三 tab 導航殼（書架／發現／我的）。此外掌管「工具類功能頁」：設定頁群（settings）、關於／更新檢查／崩潰日誌（about）、外部意圖處理（association）、下載佇列管理頁（cache_manager）、替換規則 Provider 與編輯 widgets（replace_rule，管理頁面本體在 reader_v2）。

未來工作何時從這裡開始：
- 任何「啟動順序、splash 行為、全域 Provider 增刪、底部 tab 結構」的變更，一律從 `lib/main.dart` 與 `lib/app_providers.dart` 開始。
- 新增設定項目 → 從 `features/settings/settings_page.dart` 開始。
- 深連結／分享檔案匯入的補完（已知缺口，見 Known Risks）→ 從 `features/association/` 開始。

## Scope

- `lib/main.dart` — 唯一起點。`main()`（:58）以 `runZonedGuarded` 包住 `_startApp()`（:65）；`callbackDispatcher()`（:43，`@pragma('vm:entry-point')`）與 `runBackgroundTask()`（:27）供 Workmanager 背景 isolate 使用；`ReaderApp`（:230）建 MaterialApp（theme/darkTheme/themeMode/locale/navigatorKey/scaffoldMessengerKey/appRouteObserver）；`_AssociationLifecycleHost`（:261）掛接外部意圖生命週期；`_StartupFailureApp`（:153）與 `_retryCriticalStartup`（:144，`getIt.reset()` 後重跑 `_startApp`）。
- `lib/app_providers.dart` — `AppProviders.providers`（:14）：BookshelfProvider、SettingsProvider、ThemeSettingsProvider、ChangeCoverProvider、DownloadService、TTSService（`.value` 取自 getIt）、ExploreProvider（`lazy: false` 使 DB 訂閱於啟動即建立）。
- `lib/features/welcome/` — `main_page.dart`（`MainPage` :38、`MainDestination` :383、`_KeepAliveWrapper` :397；`_defaultDestinations` :17 定義三 tab）、`startup_failure_panel.dart`（`StartupFailurePanel`，含重試／詳情／複製／崩潰日誌入口）。
- `lib/features/settings/`（11 檔）— `settings_page.dart`（「我的」tab 本體，四區：閱讀／書源／個人化／工具與其他，全部 `Navigator.push` 直連子頁）、`settings_provider.dart`（`SettingsProvider`，SharedPreferences 同步載入 + `AppConfig` 鏡像）、`theme_settings_provider.dart`（`ThemeSettingsProvider`，app/reader/menu 三區主題自訂，含給 reader 用的 static 解析 API）、`provider/settings_base.dart`（`SettingsProviderBase`：save/themeMode/locale）、子頁 `appearance_settings_page.dart`（外觀與主題，色彩編輯器）、`reading_settings_page.dart`（閱讀偏好，操作／自動翻頁／繁簡轉換）、`tts_settings_page.dart`（語速音調音量、引擎與音色）、`backup_settings_page.dart`（ZIP 備份／還原）、`data_privacy_settings_page.dart`（Cookie/WebView 清除、權限狀態、隱私說明）、`click_action_config_page.dart`（九宮格點擊區域）、`reading_stats_page.dart`（閱讀統計）。
- `lib/features/about/`（5 檔）— `about_page.dart`（版本資訊、GitHub、許可證、免責聲明、檢查更新、崩潰日誌）、`crash_log_page.dart`（可注入 `readLogs`/`clearLogs`/`writeClipboard` 供測試）、`update_check_runner.dart`（`UpdateCheckRunner` + `UpdateCheckOutcome`）、`update_dialog.dart`（`UpdateDialog`，回 `UpdateDialogResult.ignored/later`）、`external_url_launcher.dart`（`launchExternalUrlWithFeedback`）。
- `lib/features/association/`（5 檔）— `association_handler_service.dart`（Singleton，mixin 組合 `UriAssociationHandler` + `FileAssociationHandler` + `AssociationDialogHelper`）；`handlers/uri_association_handler.dart`（`legado://`、`yuedu://` path 映射）、`handlers/file_association_handler.dart`（JSON 內容偵測、本地書搬移並加入書架）、`handlers/association_dialog_helper.dart`（外部匯入 Dialog：書源／書架／替換規則；`AI_PORT: GAP-INTENT-01` 標記）、`handlers/association_base.dart`（subscription 生命週期）。
- `lib/features/cache_manager/download_manager_page.dart` — `DownloadManagerPage`：佇列摘要、暫停/恢復/重試/排序/刪除、失敗明細。
- `lib/features/replace_rule/`（4 檔）— `replace_rule_provider.dart`（**目前未被任何程式碼引用，見 Known Risks**）、`widgets/replace_edit_form.dart`、`replace_edit_options.dart`、`replace_edit_test_panel.dart`（被 reader_v2 編輯 sheet 使用）。
- 相關測試：`test/main_background_task_test.dart`（`runBackgroundTask`）、`test/features/welcome/main_page_swipe_test.dart`（用 `destinations` 注入 fake tab）、`test/features/welcome/main_page_explore_root_provider_test.dart`、`test/features/settings/{settings_pages_compile_test,theme_settings_provider_test,click_action_config_page_test}.dart`、`test/features/about/{about_page_test,crash_log_page_test}.dart`。

## Dependencies & Impact

**上游輸入（app-shell 依賴）：**
- `core/di/injection.dart`（`configureDependencies`/`getIt`，本模組是所有 DI 註冊的消費起點）。
- `core/services/`：`crash_handler.dart`（`CrashHandler.readLogs/clearLogs/recordError`）、`app_log_service.dart`（`AppLog`）、`update_service.dart` + `update_ignore_store.dart`（`UpdateCheckRunner` 的下游）、`download_service.dart`、`tts_service.dart`、`backup_service.dart` + `restore_service.dart`、`default_data.dart`（`DefaultData.initDeferred`）、`app_file_selection_service.dart`、`app_permission_service.dart`、`webview_data_service.dart`、`bookshelf_exchange_service.dart`（`SourceImportService` 定義於 `features/source_manager/source_manager_provider.dart`，見下）。
- `core/database/dao/`：`book_dao.dart`（background task）、`replace_rule_dao.dart`、`read_record_dao.dart`。
- `core/`：`config/app_config.dart`（`AppConfig.replaceEnableDefault` 鏡像）、`constant/prefer_key.dart`、`local_book/local_book_formats.dart`、`storage/app_storage_paths.dart`。
- `shared/`：`theme/`（app_tokens、app_text_styles、custom_app_theme、theme_customization）、`navigation/app_route_observer.dart`。
- 其他 features：bookshelf（`BookshelfPage`、`BookshelfProvider`）、explore（`ExplorePage`、`ExploreProvider`）、search（`SearchPage`，FAB 與閱讀統計跳轉）、source_manager（`SourceManagerPage`、`SourceImportService`）、book_detail（`ChangeCoverProvider`）、reader_v2（`ReaderV2PrefsRepository`、`ReaderV2SettingComponents`、`ReaderV2TapAction`、`ReaderV2ReplaceRuleSheet/Page`、`ReaderV2PrefsSnapshot`）。

**下游受影響（被依賴方向）：**
- 無模組依賴 app-shell（單向 root → 子模組）；`main.dart` 是唯一入口，任何啟動行為變更即全 app 變更。
- `ThemeSettingsProvider` 的 static 解析 API（`resolveReaderAreaColors`/`resolveReaderTheme`/`resolveAreaDarkMode`/`menuBuiltInIndex`，theme_settings_provider.dart:237-316）被 reader_v2 直接呼叫 — settings 與 reader 之間的合約。
- `SettingsProvider` 的 `themeMode`/`locale` 被 `ReaderApp` 消費；TTS 參數在 provider 建構時同步推給 `TTSService()`。
- `AssociationDialogHelper` 寫入 source_manager（`SourceImportService`）、replace_rule（`ReplaceRuleDao`）、bookshelf（`BookshelfProvider`、`BookshelfExchangeService`）— association 是跨模組寫入集中地。

## Key Flows

### App 啟動序列（main.dart）
1. `main()` → `runZonedGuarded(_startApp, ...)`，未捕獲例外進 `AppLog.e` + `CrashHandler.recordError`。
2. `_startApp`：`ensureInitialized` → `GestureBinding.resamplingEnabled = true` → `FlutterNativeSplash.preserve`。
3. 覆寫 `ErrorWidget.builder`（黑底、紅字、顯示 stack，同時 `recordFlutterError`）。
4. `await configureDependencies()` — 失敗即 `_StartupFailureApp`（可 `_retryCriticalStartup`：`getIt.reset()` 再跑一次）。
5. `FlutterError.onError` 覆寫（`presentError` + 記錄 + `recordFlutterError`）。
6. `runApp(MultiProvider(AppProviders.providers, ReaderApp()))`。
7. post-frame → `_runPostFirstFrameStartupTasks`：debug 模式強制 `recordLog=true`、清除 Legacy 字型殘留（`selected_font_family` pref + `fonts/` 目錄）、`Workmanager().initialize(callbackDispatcher)`。
8. `ReaderApp` 內的 `_AssociationLifecycleHost` post-frame 呼叫 `AssociationHandlerService().init(context)`。

### Splash → 書架轉場（main_page.dart）
`MainPage.initState` post-frame 呼叫 `_releaseSplashWhenShelfReady`（:265）：`BookshelfProvider` 載入完成即放行，否則等待最多 2 秒（`_splashShelfTimeout`）；逾時則顯示「正在載入書架」overlay（:284 `_handleSplashShelfTimeout`）。`_releaseNativeSplashOnce`（:312）保證最少顯示 900ms 且只執行一次；測試注入的 `destinations` 不會觸發 splash 釋放。同 post-frame 亦執行 `DefaultData.initDeferred()` 與自動更新檢查（延遲 500ms）。

### 底部導航
`PageView` + `NavigationBar`，`_KeepAliveWrapper`（AutomaticKeepAliveClientMixin）保活三 tab。double-tap 目前 tab 觸發 `_defaultDoubleTap`（書架 tab 重新 `loadBooks()`）。`PopScope` 攔截返回鍵：非 tab 0 先導回 tab 0，tab 0 兩秒內連按兩次才 `SystemNavigator.pop`。

### Deep Link / 分享（association）
`AssociationHandlerService`（Singleton）監聽 `AppLinks.uriLinkStream` 與 `ReceiveSharingIntent` 的 media stream/initial，依內容顯示「外部匯入」Dialog（書源／書架／替換規則三選一）。`.json` 檔按 key 偵測類型（`bookSourceUrl`/`pattern`/`themeName`），支援的本地書副檔名直接搬入 `InkpageBooks/` 並加入書架。
**注意：`AndroidManifest.xml` 沒有任何 deep link（`legado://`/`yuedu://`）或 `ACTION_SEND` intent filter — 平台層根本不會把這些意圖送進 App，Dart 側流程形同空轉（見 Known Risks）。**

### 更新檢查
`UpdateCheckRunner`（封裝 `AppUpdateService` + `UpdateIgnoreStore`）：自動（僅 Android、忽略過的版本直接 return、延遲 context 取用避免洩漏）；手動（AboutPage「檢查更新」，回 `UpdateCheckOutcome` 供 SnackBar）。`UpdateDialog` 三選項：忽略此版（寫入 ignore store）／稍後提醒／前往下載（GitHub release 頁）。

### 設定持久化
`SettingsProvider` 在**建構子**同步讀 SharedPreferences（消除啟動閃爍），變更經 `SettingsProviderBase.save` 非同步寫回；`AppConfig.replaceEnableDefault` 為雙向鏡像（:95-100, :176-178）。`ThemeSettingsProvider` 把 app/reader/menu 三區 × 淺/深色存成 `theme_*_v1` JSON keys，reader 端透過 static API 讀取。TTS 語速/音調/音量變更同步推給 `TTSService()` 單例。

### Workmanager 背景任務
`callbackDispatcher`（isolate 內重新 `configureDependencies()` 再查書架）— 但目前**沒有任何 `registerPeriodicTask`/`registerOneOffTask` 呼叫**，整條管線處於備而未用狀態。

## Change Entry Points & Routes

| 進入點 | 檔案:行 | 說明 |
|---|---|---|
| App 啟動順序 | `lib/main.dart:65` `_startApp()` | 啟動順序、DI、ErrorWidget/FlutterError 覆寫 |
| 背景任務 | `lib/main.dart:27` `runBackgroundTask()`、`:43` `callbackDispatcher()` | 改 task 內容；**若要真正排程**需新增 register 呼叫（目前沒有） |
| Splash 放行 | `lib/features/welcome/main_page.dart:265` `_releaseSplashWhenShelfReady()` | 條件、逾時（:61 `_splashShelfTimeout`）、最少顯示（:60 `_splashMinDisplay`） |
| tab 結構 | `lib/features/welcome/main_page.dart:17` `_defaultDestinations` | 增減 tab / 換頁面；測試靠 `MainPage(destinations:)` 注入 |
| 全域 Provider | `lib/app_providers.dart:14` | 增刪全域 Provider；`lazy:false` 語意（ExploreProvider）勿亂改 |
| Deep link 路由 | `lib/features/association/handlers/uri_association_handler.dart:16` | 新增 URI scheme / path 映射；平台側需同步改 AndroidManifest |
| 外部匯入 Dialog | `lib/features/association/handlers/association_dialog_helper.dart:16` | 匯入動作集中在這（書源/書架/規則） |
| 設定頁路由 | `lib/features/settings/settings_page.dart:14` | 所有子頁唯一的掛載點（無 routing framework） |
| 崩潰日誌 | `lib/features/about/crash_log_page.dart:8` | 資料源 `CrashHandler.readLogs()`（:106） |
| 更新檢查 | `lib/features/about/update_check_runner.dart:10` | 替換 `AppUpdateService` 或忽略策略；版本來源 URL 在 `core/services/update_service.dart:16` |
| 替換規則管理頁 | `lib/features/reader_v2/features/replace_rule/reader_v2_replace_rule_page.dart:7` | 實際管理 UI 在 reader_v2；由 `reader_v2_replace_rule_sheet.dart` 的「管理規則」進入（reader 選單內） |
| 下載佇列 | `lib/features/cache_manager/download_manager_page.dart:10` | 操作直接打在 `DownloadService` 上 |

**必須保持同步的多檔路徑：**
- `ThemeSettingsProvider` pref keys（theme_settings_provider.dart:28-43）⇄ `shared/theme/theme_customization.dart` 的資料類別 ⇄ reader_v2 對 static API 的呼叫 — 加主題欄位要四處一起改。
- `SettingsProvider` 欄位 ⇄ `PreferKey` ⇄ `AppConfig` 鏡像（`replaceEnableDefault`）⇄ reader 消費端。
- `ReaderV2PrefsRepository`（reader_v2/features/settings/）⇄ `ReadingSettingsPage` / `ClickActionConfigPage` — 閱讀偏好頁只是該 repository 的薄 UI。
- `ReplaceRuleDao`（core/database/dao/）⇄ `features/replace_rule/widgets/*` ⇄ reader_v2 的 rule sheet/page ⇄ `association_dialog_helper.dart:114`（`_importReplaceRules`）— 改模型三處齊改。
- `CrashHandler` ⇄ `crash_log_page` ⇄ `StartupFailurePanel` ⇄ `main.dart` 三處錯誤掛鉤。
- `UpdateCheckRunner` / `UpdateDialog` ⇄ `core/services/update_service.dart` + `update_ignore_store.dart`。
- `DownloadService`（core/services/）⇄ `DownloadManagerPage` ⇄ book_detail 的發起端。

## Known Risks

1. **Deep link 與分享檔在平台層失效（已知缺口 GAP-INTENT-01）：** `main.dart:261` 的 `_AssociationLifecycleHost` 已正確呼叫 `init()`，但 `android/app/src/main/AndroidManifest.xml` 沒有 `legado://`/`yuedu://` 的 `<intent-filter>`，也沒有 `receive_sharing_intent` 所需的 `ACTION_SEND` filters — App 永遠收不到這類意圖。補 manifest 是讓此功能真正生效的前置步驟。
2. **Workmanager 初始化但零任務排程：** `main.dart:196` initialize 後沒有任何 register 呼叫；`callbackDispatcher` 在背景 isolate 重新 `configureDependencies()`，若未來啟用排程，需確認所有 DAO/Service 能在背景 isolate 安全重建（`flutter_js` 因 FFI 無法跨 isolate，見 DEVELOPMENT.md）。
3. **`DataPrivacySettingsPage` 未掛載：** `settings_page.dart` 沒有「資料與隱私」入口（四區：閱讀／書源／個人化／工具與其他）；隱私說明／權限說明頁也只能經由它到達。整頁是 dead code，`settings_pages_compile_test.dart` 只驗證可建構。
4. **`ReplaceRuleProvider` 是 dead code：** `features/replace_rule/replace_rule_provider.dart` 無任何引用；實際管理 UI 在 `reader_v2/features/replace_rule/`（`ReaderV2ReplaceRulePage` 直接操作 `ReplaceRuleDao`），只有 `widgets/` 三件被 reader_v2 編輯 sheet 使用。搬遷/刪除時注意不要把 `widgets/` 一起刪。
5. **SettingsProvider 建構子同步讀 prefs：** 依賴 `getIt<SharedPreferences>()` 已註冊（否則 `_loadFromPrefs` 在建構期炸），且建構流程（`_loadFromPrefs`）內直接 `TTSService()`。Provider 建立順序被 `AppProviders.providers` 隱式決定。
6. **SettingsPage 直接 import 跨模組頁面：** 硬編碼 `SourceManagerPage`、`DownloadManagerPage`、reader_v2 元件等，這些頁面重構或搬遷需同步改 `settings_page.dart`。
7. **PageView KeepAlive 不保存路由狀態：** 切 tab 不會 rebuild，但若 tab 內頁面 push/pop 變更狀態，返回時不會自動刷新（依賴 Provider 通知）。
8. **`ErrorWidget.builder` 內呼叫 `CrashHandler.recordFlutterError`：** rendering error 中再碰 platform channel（檔案寫入）有遞迴崩潰風險。
9. **更新檢查硬編碼 GitHub API：** `core/services/update_service.dart:16` 寫死 `bennytsai1234/night-reader`；repo 遷移需同步。
10. **自動更新檢查無使用者可見失敗：** `_runAutomaticUpdateCheck` 失敗只進 AppLog，靜默。
11. **測試覆蓋缺口：** splash 釋放時序（`_releaseSplashWhenShelfReady`/逾時 overlay）與 association handlers 無測試；`crash_log_page` 有注入點測試但 `main.dart` 的啟動錯誤路徑無整合測試。`test/features/welcome/main_page_swipe_test.dart` 以 `destinations` 注入規避 splash/provider 依賴 — 改 `MainPage` 初始化邏輯時這些測試可能失真。

## Boundaries

- 不要把 `configureDependencies()` 移出 `_startApp`/`runZonedGuarded` 保護傘之外 — 啟動錯誤必須落在 crash handler 網內。
- `AppProviders` 只放狀態載具；重量級實例一律從 getIt 取得並用 `.value`（如 `TTSService`）。
- `AppLog`/`CrashHandler` 須在 `configureDependencies()` 內最早註冊（log 與 crash 註冊順序不得晚於其他 DI），確保啟動期錯誤也被捕獲。
- 全 app 無 routing framework：所有頁面 `Navigator.push(MaterialPageRoute(...))`；引入宣告式路由需一次性改寫全部 push 站點（含 settings_page 全部 ListTile、about、crash_log、reading_stats、startup_failure_panel）。
- `MainPage` 只承載殼層；不要直接塞入其他 feature 的 widget 作為 tab page，除非同時更新 `_defaultDestinations` 與 `welcome` 測試。
- `main_page.dart` 的 splash 邏輯只有在 `widget.destinations == null`（真實啟動）時執行 — 測試注入的 MainPage 永不釋放 Native splash，測試不應依賴 splash 行為。
- 專案為 feature freeze（DEVELOPMENT.md 明定）：新增產品線功能不在本模組工作範圍，只做維護、修 bug、重構與內部改進。
- 更新流程約定（AGENTS.md）：tag `v*` 觸發 `.github/workflows/android-release.yml`；版本號在 `pubspec.yaml`。