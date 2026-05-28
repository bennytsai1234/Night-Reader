# 應用基礎設施

## 現有責任

Drift 資料庫定義與所有 DAO、HTTP client（Dio）、Cookie 管理、DI 容器（get_it）、儲存路徑管理、應用常數與偏好 key、應用啟動（Splash → Main）、底部導覽、主題、版本更新檢查、深連結處理、崩潰日誌。所有其他模組均依賴此層。

## 範圍

- **資料庫**：`lib/core/database/`（`app_database.dart`、`tables/app_tables.dart`、全部 DAO）
- **網路**：`lib/core/network/`（`interceptors/`）、`lib/core/services/http_client.dart`、`network_service.dart`
- **DI**：`lib/core/di/injection.dart`（get_it 注入）
- **儲存路徑**：`lib/core/storage/app_storage_paths.dart`、`file_doc.dart`、`storage_metrics.dart`、`app_cache.dart`
- **常數與設定**：`lib/core/config/app_config.dart`、`lib/core/constant/`（`app_const.dart`、`prefer_key.dart`、`book_type.dart`、`page_anim.dart`、`source_type.dart`、`app_pattern.dart`）
- **模型基礎**：`lib/core/models/`（非書籍專屬：`base_source.dart`、`cookie.dart`、`server.dart`、`keyboard_assist.dart` 等）
- **服務基礎**：`lib/core/services/event_bus.dart`、`cookie_store.dart`、`app_log_service.dart`、`crash_handler.dart`、`app_permission_service.dart`、`resource_service.dart`、`rate_limiter.dart`
- **版本更新**：`lib/core/services/update_service.dart`、`app_version.dart`、`update_ignore_store.dart`
- **應用入口**：`lib/main.dart`、`lib/app_providers.dart`
- **啟動 / 導覽**：`lib/features/welcome/`（`splash_page.dart`、`main_page.dart`）
- **關於頁面**：`lib/features/about/`（`about_page.dart`、`update_dialog.dart`、`update_check_runner.dart`、`crash_log_page.dart`）
- **深連結**：`lib/features/association/association_handler_service.dart`
- **共用主題 / 元件**：`lib/shared/`（主題、文字樣式、token、底部 sheet、navigation）
- **測試**：`test/core/database/`、`test/core/network/`、`test/core/services/`（update、permission、app_interceptor 等）、`test/features/welcome/`

## 依賴與下游影響

- 上游：Flutter SDK、Android SDK、所有 pub.dev 套件
- 下游：**所有模組**均依賴此層的 DAO、DI、常數、儲存路徑
- 資料庫 schema 變更（新增欄位或 table）會影響所有使用該 DAO 的模組
- DI 容器（injection.dart）是服務的單一注入點；新增服務時需要在此登錄

## 關鍵流程

1. 應用啟動：`main.dart` → Provider MultiProvider 掛載 → `SplashPage` 初始化資料庫與服務 → `MainPage`（底部導覽）
2. HTTP 請求：Dio instance（`http_client.dart`）→ `AppInterceptor`（請求 header、重試、error 處理）→ `LenientCookieManager`（Cookie 注入）
3. 深連結：`app_links` 接收 URI → `AssociationHandlerService` 路由至對應頁面
4. 版本更新：`UpdateCheckRunner` 在啟動時查詢 GitHub Releases API → `UpdateDialog` 提示使用者

## 變更入口

- 新增 DB table 或欄位：`lib/core/database/tables/app_tables.dart` → 新增/修改對應 DAO → `app_database.dart` 加 schema migration
- 新增全域 Provider：`lib/app_providers.dart`
- 修改 HTTP 行為（header、retry）：`lib/core/network/interceptors/app_interceptor.dart`
- 修改啟動流程：`lib/features/welcome/splash_page.dart`

## 變更路由

- 資料庫 schema 遷移：`app_tables.dart` 修改 → `app_database.dart` 加 `schemaVersion` 遞增與 migration callback → 執行 `build_runner` 重新生成 `.g.dart` → 回歸 `test/core/database/`
- 修改 DI：`injection.dart` → 確認所有受影響模組的 Provider 正確取得新服務

## 已知風險

- Drift 的 schema migration 是手動撰寫的 SQL；遺漏 migration step 會導致舊版升級後資料庫損壞
- `injection.dart` 是全局單例；循環依賴或注入順序錯誤可能導致 runtime 崩潰且難以追蹤
- `workmanager` 背景任務需要在 Android 原生端（`MainActivity`）登錄；純 Flutter 層的改動不夠
- 深連結 URI scheme 需要在 `AndroidManifest.xml` 宣告；`AssociationHandlerService` 改動需同步確認

## 參考備註

無（Standalone 模式）

## 禁止事項

- 不要在 DAO 層加入業務邏輯；DAO 只做 CRUD
- 不要在 `app_providers.dart` 之外建立額外的全局 Provider 掛載點
- 不要跳過 schema migration；每次 table 或欄位變更都需要遞增 `schemaVersion` 並撰寫 migration
