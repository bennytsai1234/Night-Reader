# 瀏覽器驗證

## 現有責任

WebView 互動驗證流程：當書源需要登入、輸入驗證碼或寫入 Cookie 時，彈出內嵌瀏覽器讓使用者手動操作，完成後由 App 接管 Cookie 繼續抓取。也包含後台 WebView（headless）供規則引擎靜默執行 JS 重型書源。

## 範圍

- **互動 WebView UI**：`lib/features/browser/`（`browser_page.dart`、`browser_provider.dart`、`browser_params.dart`、`verification_code_dialog.dart`、`source_verification_coordinator.dart`）
- **後台 WebView 服務**：`lib/core/engine/web_book/headless_webview_service.dart`
- **WebView 資料服務**：`lib/core/services/webview_data_service.dart`、`backstage_webview.dart`
- **Cookie 相關**：`lib/core/services/cookie_store.dart`、`lib/core/network/interceptors/lenient_cookie_manager.dart`

## 依賴與下游影響

- 上游：**書源管理**（觸發驗證流程）、**搜尋與探索**（遇到需驗證書源時彈出）、**閱讀器 V2**（部分書源在抓取章節時觸發）
- 下游：**規則引擎**（驗證後 Cookie 由 cookie_store 提供給後續網路請求）
- Cookie 寫入後影響全局的網路請求行為

## 關鍵流程

1. 觸發驗證：書源抓取遇到驗證響應 → `SourceVerificationCoordinator` 判斷需要人工介入 → 導航至 `BrowserPage`
2. 互動驗證：使用者在 WebView 完成登入/驗證 → WebView 偵測到目標 URL 或使用者手動關閉 → Cookie 由 `cookie_store` 收集 → 通知原始流程繼續
3. 後台 WebView：`HeadlessWebviewService` 在背景運行 WebView → 執行 JS → 回傳渲染後 HTML

## 變更入口

- 驗證觸發條件：`source_verification_coordinator.dart`
- WebView 頁面 UI：`browser_page.dart`、`browser_provider.dart`
- Cookie 持久化：`cookie_store.dart`、`lenient_cookie_manager.dart`

## 變更路由

- 修改驗證觸發邏輯：`source_verification_coordinator.dart` → 相關 widget test `test/features/browser/`
- Cookie 管理變更：`cookie_store.dart` → `test/core/network/interceptors/lenient_cookie_manager_test.dart`

## 已知風險

- WebView 行為依賴真實網站與 Android webview_flutter 版本，幾乎無法在 CI 中自動化測試
- 後台 WebView 持有底層 Android WebView 資源，長時間運行可能消耗大量記憶體
- Cookie 的 domain 匹配邏輯（lenient cookie manager）有意偏寬鬆，可能導致 Cookie 被意外帶到不相關請求

## 參考備註

無（Standalone 模式）

## 禁止事項

- 不要讓 browser 模組直接修改書源資料；Cookie 收集後只寫入 cookie_store，不改書源規則
- 不要在後台 WebView 執行無終止條件的循環；需設 timeout 避免資源洩漏
