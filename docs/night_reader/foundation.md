# foundation

## Responsibility

- App 進入點、啟動殼、全域 Provider 註冊、共用 UI 層，以及跨切面 core 基礎（DI、常數、例外、網路攔截器、路徑/快取、工具、本機書格式偵測、Provider 基類、共用 widget）。
- 未來工作從這裡開始：開機崩潰/黑屏、主題與設計 token、全域狀態注入、Dio 攔截器/Cookie/UA、儲存路徑、Preference key、本機書格式偵測。

## Scope

- `lib/main.dart`、`lib/app_providers.dart` — 進入點；`main()` 用 `runZonedGuarded` 包裹、DI 初始化、`ErrorWidget.builder`、`Workmanager` 後台 callback、`ReaderApp` 殼。
- `lib/shared/` — `theme/`（`AppTheme`、`AppTokens`、`AppTextStyles`、`context_ext.dart`）、`widgets/`（`app_bottom_sheet.dart`、`source_option_tile.dart`）、`navigation/book_open_route.dart`（開書轉場至 `ReaderV2Page`）。
- `lib/features/welcome/` — `splash_page.dart`、`main_page.dart`（底部導航：書架/發現/我的）、`startup_failure_panel.dart`。
- `lib/core/base/base_provider.dart` — `BaseProvider`（`isLoading`/`errorMessage`/`cancelToken`）。
- `lib/core/config/app_config.dart` — 全域配置鏡像，與 `SettingsProvider` 同步。
- `lib/core/constant/` — `app_const.dart`、`app_pattern.dart`、`book_type.dart`、`source_type.dart`、`prefer_key.dart`。
- `lib/core/di/injection.dart` — `getIt` + `configureDependencies()`。
- `lib/core/exception/app_exception.dart`。
- `lib/core/local_book/` — `local_book_formats.dart`（`kSupportedLocalBookExtensions={'txt'}`）、`txt_parser.dart`。
- `lib/core/storage/` — `app_cache.dart`（`AppCache`，磁碟快取+過期）、`app_storage_paths.dart`、`file_doc.dart`、`storage_metrics.dart`。
- `lib/core/utils/` — `utils.dart`、`url_util.dart`、`string_utils.dart`、`html_utils.dart`、`network_utils.dart`、`lru_map.dart`、`ttf_parser.dart` 等。
- `lib/core/widgets/book_cover_widget.dart`。
- `lib/core/network/` — `str_response.dart`（`StrResponse`）、`interceptors/app_interceptor.dart`（`AppInterceptor`，UA/Referer/手動 redirect 鏈）、`interceptors/lenient_cookie_manager.dart`（`LenientCookieManager`，容錯 cookie）。組裝於 `core/services/network_service.dart`。

## Dependencies & Impact

- 上游：被所有 feature 與 core 子模組間接引用（常數/DI/utils/theme）。
- 下游影響：改 `main.dart` 啟動流程、`AppProviders` 註冊、`AppTheme`/`AppTokens`、`PreferKey`、`AppInterceptor` 會牽動全 App；改 `AppConfig` 影響 reader/models。
- 相依 `database`（DI 注入 DB/DAO）、`services`（`network_service`/`app_log`）。

## Key Flows

- 啟動：`WidgetsFlutterBinding` → `configureDependencies()` → `runApp(MultiProvider)` → `SplashPage` → 首框後 `_runPostFirstFrameStartupTasks`（Workmanager init、legacy font 清理）。
- 失敗路徑：`_StartupFailureApp` + `StartupFailurePanel` + `_retryCriticalStartup`（`getIt.reset()` 重啟）。
- 後台：`callbackDispatcher` 重新 `configureDependencies()`（Isolate 不共享主執行緒狀態）。

## Change Entry Points & Routes

- 啟動崩潰/DI：`lib/main.dart`、`lib/core/di/injection.dart`。
- 主題/Token：`lib/shared/theme/*`；同步檢查 `features/settings/settings_provider.dart`、`core/config/app_config.dart`。
- 全域攔截器/Cookie：`lib/core/network/*` + `core/services/network_service.dart`。
- Preference key：`lib/core/constant/prefer_key.dart`（新增 key 需檢查所有讀寫處）。
- 底部導航/入口：`lib/features/welcome/main_page.dart`。

## Known Risks

- `main.dart` 的 `callbackDispatcher` 在後台 Isolate 重新初始化 DI；JS 引擎因 FFI 無法跨 isolate，後台任務不可呼叫 JS 規則（見 engine 模組）。
- `AppConfig` 與 `SettingsProvider` 雙向同步，改其中一方需檢查另一方的鏡像是否一致，否則 Model 層讀到舊值。
- `AppInterceptor` 手動 redirect 上限 10，變更需留意循環重導向。

## Do Not Do

- 不要在啟動路徑做同步或長耗時操作。
- 不要把新產品線功能塞進 `main_page.dart` 導航（feature freeze）。
- 不要在 `network` 攔截器加入書源規則解析邏輯（屬 engine）。
