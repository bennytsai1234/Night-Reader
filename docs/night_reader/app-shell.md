# app-shell — App Shell、導航與工具頁面

## Responsibility

掌管 App 生命週期起手式（DI 初始化、崩潰攔截、Native splash 銜接）、全域 Provider 註冊、底部三 tab 導航殼，以及設定群組、關於頁、深連結/分享外部意圖、下載佇列、替換規則管理等功能頁。不涉閱讀引擎、書架資料展示或書源發現。

## Scope

| 檔案/目錄 | 職責 |
|---|---|
| `lib/main.dart` | App entry point；runZonedGuarded → DI (`configureDependencies`) → MultiProvider → `ReaderApp` |
| `lib/app_providers.dart` | `AppProviders.providers` 集中列表 |
| `features/welcome/main_page.dart` | Bottom navigation shell（PageView + NavigationBar），三 tab：書架、發現、我的 |
| `features/welcome/startup_failure_panel.dart` | 核心初始化失敗時的錯誤面板（含重試、崩潰日誌入口） |
| `features/about/` | `AboutPage`（版本資訊、GitHub、開源許可證、免責聲明）、`UpdateCheckRunner`、`UpdateDialog`、`CrashLogPage` |
| `features/association/` | `AssociationHandlerService`（Singleton）：支援 `legado://` / `yuedu://` deep link 與 Android `ReceiveSharingIntent` 檔案匯入 |
| `features/settings/` | `SettingsPage`（「我的」tab 內容）、`ReadingSettingsPage`、`TtsSettingsPage`、`BackupSettingsPage`、`DataPrivacySettingsPage`、`ClickActionConfigPage`、`SettingsProvider` |
| `features/cache_manager/download_manager_page.dart` | `DownloadManagerPage`：檢視/暫停/重試/排序下載任務 |
| `features/replace_rule/` | `ReplaceRuleProvider` + 編輯 widgets；實際管理頁面在 `reader_v2/features/replace_rule/` |

## Dependencies & Impact

**依賴方向：** app-shell 依賴 core/（DI、DAO、Service）、shared/theme、以及 features/bookshelf、features/explore、features/source_manager、features/reader_v2 的部分頁面與 Provider。

**被依賴：** 無（單向 root → 子模組）。`main.dart` 是整個 App 的唯一起點。

**跨模組耦合：**
- `MainPage` 直接內建 `BookshelfPage()` / `ExplorePage()` / `SettingsPage()` 三個 widget 實例 — 如需替換 tab 需改此處（支援 `destinations` 參數供測試注入）。
- `AppProviders` 註冊 `BookshelfProvider`、`ExploreProvider`、`ChangeCoverProvider`、`SettingsProvider`、`DownloadService`、`TTSService`。
- `AssociationHandlerService` 透過 `SourceImportService` 寫入 source_manager、透過 `ReplaceRuleProvider` 寫入 replace_rule、透過 `BookshelfProvider` 寫入書架。
- `SettingsPage` 內 `Navigator.push` 導向各子頁面（無 routing framework）。

## Key Flows

### App 啟動序列（main.dart）

1. `runZonedGuarded` 包裹 `_startApp`，未捕獲例外由 `CrashHandler` 記錄。
2. `WidgetsFlutterBinding.ensureInitialized()` → `GestureBinding.resamplingEnabled = true`（高刷新率觸控對齊）。
3. `FlutterNativeSplash.preserve()` — 延後首幀，Native splash 一路撐到書架載完。
4. `configureDependencies()` — DI 注入（getIt）。
5. `FlutterError.onError` 自訂 → 記錄 + `CrashHandler.recordFlutterError`。
6. `ErrorWidget.builder` 自訂 → 黑底紅字錯誤畫面（非崩潰而是 rendering error 時顯示）。
7. `runApp(MultiProvider(providers: AppProviders.providers, child: ReaderApp()))`。
8. Post-frame callback → `_runPostFirstFrameStartupTasks`：debug 模式強制開記錄、清除 Legacy 字型殘留 (`selected_font_family`/pref + `fonts/` dir)、初始化 Workmanager。
9. 若 `configureDependencies` 拋錯 → `_StartupFailureApp` 顯示 `StartupFailurePanel`（含重試/崩潰日誌）。

### Splash → 書架轉場（main_page.dart）

`MainPage.initState` 註冊 `BookshelfProvider` listener，待 `isLoading == false` 或 2 秒逾時後呼叫 `FlutterNativeSplash.remove()`；最少保留 900ms 避免 Native 動畫被腰斬。

### 底部導航

`PageView` + `NavigationBar`，三 tab 預設：書架 / 發現 / 我的。double-tap 書架 tab 觸發 `BookshelfProvider.loadBooks()`。返回鍵在第一 tab 時顯示「再按一次退出」SnackBar，非第一 tab 則先導回 tab 0。

### Deep Link / 分享處理

`AssociationHandlerService`（Singleton，mixin 模式）監聽 `AppLinks`（`legado://`、`yuedu://`）與 `ReceiveSharingIntent`。收到後依 type 顯示 Import Dialog，使用者可選擇匯入為書源、替換規則或書籍。

**注意：** 掃遍全 repo 未發現任何呼叫 `AssociationHandlerService().init()` 的位置 — 此 service 已定義但未掛入任何 widget 生命週期，屬已知缺口（見 #Known Risks）。

### 更新檢查

`UpdateCheckRunner` 封裝 `AppUpdateService` + `UpdateIgnoreStore`。啟動時背景檢查 (`runAutomatic`，僅 Android)、手動從 AboutPage 觸發 (`runManual`)。結果透過 `UpdateDialog` 顯示（忽略此版 / 稍後提醒 / 前往下載）。

## Change Entry Points & Routes

| 進入點 | 檔案 | 說明 |
|---|---|---|
| App 啟動 | `lib/main.dart:58` `_startApp()` | 修改啟動順序、DI 初始化、splash 行為 |
| Splash 邏輯 | `features/welcome/main_page.dart:164` `_releaseSplashWhenShelfReady()` | 修改「書架就緒即放行」判斷條件或逾時 |
| 底部 tab 結構 | `features/welcome/main_page.dart:15` `_defaultDestinations` | 增減 tab、更換 icon/label/page |
| 全域 Provider | `lib/app_providers.dart:13` `AppProviders.providers` | 增刪全域 Provider |
| Deep link 路由 | `features/association/handlers/uri_association_handler.dart:16` | 新增 URI scheme 或 path mapping |
| 設定頁路由 | `features/settings/settings_page.dart` | 各 ListTile 的 `Navigator.push` 是唯一路由方式 |
| 崩潰日誌 | `features/about/crash_log_page.dart` | 讀取來源為 `CrashHandler.readLogs()` |
| 更新檢查邏輯 | `features/about/update_check_runner.dart` | 替換 `AppUpdateService` 或忽略策略 |

App 無 routing framework；所有子頁面透過 `Navigator.push(MaterialPageRoute(...))` 直接 push。若引入宣告式路由（如 GoRouter / Navigator 2.0），所有 `Navigator.push` 呼叫點均需改寫。

## Known Risks

1. **AssociationHandlerService 未掛接：** `init()` 從未被呼叫，`legado://` deep link 與 Android 分享 intent 在當前主分支上完全不作用。`TODO`。
2. **SettingsPage 直接 import 跨模組頁面：** 硬編碼 `SourceManagerPage`、`DownloadManagerPage`、`ReadingSettingsPage`、`TtsSettingsPage` 等，若這些頁面重構或搬遷需同步修改此處。
3. **PageView 無 KeepAlive 以外的狀態保存：** 切 tab 時 page 不會 rebuild，但若某 page 內部因路由 push/pop 變更狀態，返回 tab 時不會自動刷新（需依賴 Provider 或自行實作 didChangeDependencies）。
4. **Workmanager callbackDispatcher 在 background isolate 中重新 `configureDependencies()`：** 需確保所有 DAO/Service 在 background isolate 也可安全建立；`BookDao` 直接注入，若底層 DB 連線非 isolate-safe 則會靜默失敗。
5. **ReplaceRuleProvider 在 features/replace_rule/，實際頁面在 features/reader_v2/：** 跨目錄引用，搬遷 refactor 時需注意雙向依賴。
6. **啟動逾時無使用者回饋：** `_splashShelfTimeout` 為 2 秒、逾時後直接 `remove()`，使用者無任何 loading 指示；若書架查詢超過 2 秒會看到短暫空白。
7. **ErrorWidget.builder 內呼叫 `CrashHandler.recordFlutterError`：** Rendering error 中再呼叫 platform channel 可能導致遞迴崩潰。

## Do Not Do

- 不要把 `configureDependencies()` 移出 `_startApp` 或放進 `main()` 之前 — 需在 `runZonedGuarded` 保護傘內。
- 不要在 app-shell 內直接 import features/reader_v2 的 widget 作為 tab page — `MainPage` 應只承載殼層。
- 不要為 app-shell 內的頁面引入獨立 routing framework 而不同步改寫所有 `Navigator.push` 站點 — 當前全 app 使用 imperative navigation，引入宣告式路由需一次性遷移。
- 不要在 `AppProviders` 內建立重量級物件（如 DB 連線、NetworkService）— Provider 只應作為狀態載具，重量級實例應從 getIt 取得（如 `TTSService` 已是 `.value` 模式）。
- 不要把 CrashHandler / AppLog 的初始化放在 `_startApp` 之後 — log 與 crash handler 應在 `configureDependencies()` 內最早註冊，確保啟動期間的錯誤也被捕獲。
