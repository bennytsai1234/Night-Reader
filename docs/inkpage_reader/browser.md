# 瀏覽器驗證

## 現有責任

後台 headless WebView：供規則引擎靜默載入需要 JS 渲染的書源頁面，回傳渲染後 HTML 再交由規則引擎解析。WebView 資料服務管理 WebView 執行個體的生命週期與共享狀態。

**注意**：互動式瀏覽器驗證（讓使用者手動登入、輸入驗證碼、寫入 Cookie）**尚未實作**。需要登入或驗證碼的書源目前會直接回報錯誤，使用者應改用不需驗證的書源。

## 範圍

- **後台 headless WebView**：`lib/core/engine/web_book/headless_webview_service.dart`
- **WebView 資料服務**：`lib/core/services/webview_data_service.dart`
- **後台 WebView 管理**：`lib/core/services/backstage_webview.dart`
- **Cookie 管理**：`lib/core/services/cookie_store.dart`、`lib/core/network/interceptors/lenient_cookie_manager.dart`

## 依賴與下游影響

- 上游：**規則引擎**（`web_book_service` 呼叫 headless WebView 執行 JS 重型書源）
- 下游：**規則引擎**（取得渲染後 HTML 繼續解析）
- 影響範圍侷限於規則引擎的 web_book 路徑，不影響一般書源

## 關鍵流程

1. JS 重型書源抓取：規則引擎判斷書源需要 WebView 渲染 → `HeadlessWebviewService` 在背景載入頁面 → 執行 JS → 回傳渲染後 HTML → 規則引擎繼續解析

## 變更入口

- 後台 WebView 邏輯：`headless_webview_service.dart`
- WebView 資料狀態：`webview_data_service.dart`
- Cookie 持久化：`cookie_store.dart`、`lenient_cookie_manager.dart`

## 已知風險

- headless WebView 持有底層 Android WebView 資源，長時間運行可能消耗大量記憶體
- WebView 行為依賴 Android 版本，難以在 CI 中自動化測試
- Cookie 的 domain 匹配邏輯（lenient cookie manager）有意偏寬鬆，可能導致 Cookie 被意外帶到不相關請求

## 禁止事項

- 不要在後台 WebView 執行無終止條件的循環；需設 timeout 避免資源洩漏
- 不要實作互動式瀏覽器驗證；此功能不在產品範圍內
