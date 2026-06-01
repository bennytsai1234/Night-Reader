# 瀏覽器驗證

## 目前職責

後台 headless WebView，供規則引擎靜默執行需要瀏覽器環境的 JS 重型書源（例如：需要執行 JS 才能取得真實內容的頁面）。**互動式瀏覽器驗證（登入、驗證碼）尚未完整實作**，此類書源直接回報錯誤。修改 headless WebView 行為，從這裡開始。

## 範圍

| 路徑 | 職責 |
|---|---|
| `lib/core/engine/web_book/headless_webview_service.dart` | 後台 headless WebView 執行 JS 規則；由規則引擎的 AnalyzeRule 呼叫 |
| `lib/core/services/webview_data_service.dart` | WebView 資料管理（Cookie 同步、WebView 狀態清理）|
| `lib/core/services/backstage_webview.dart` | 後台 WebView widget 掛載點（在 MaterialApp 之下保持 alive）|
| `lib/features/source_manager/views/source_login_page.dart` | 互動式登入 UI（骨架，尚未完整）|

測試：無獨立測試（依賴真實 WebView 環境，只有 smoke test）

## 依賴與影響

- **上游**：規則引擎（AnalyzeRuleScript.evalJSAsync 在需要瀏覽器環境時呼叫 HeadlessWebViewService）
- **下游**：書源管理（書源驗證時需要 headless WebView）、閱讀器（章節抓取時需要 headless WebView）
- **平台**：webview_flutter（Android WebView）；iOS 尚未支援（無 WKWebView 對應實作）
- **狀態**：BackstageWebView 在 main.dart 中保持 alive，跨頁面共用 WebView 實例

## 關鍵流程

**headless 執行流程**：
```
AnalyzeRuleScript.evalJSAsync（規則引擎）
  → HeadlessWebViewService.execute(url, script)
    → BackstageWebView（從 widget tree 取得 WebView controller）
    → WebView.loadUrl(url) → 等待 JS bridge 回傳
    → 返回 JS 執行結果給規則引擎
```

**Cookie 同步流程**：
```
NetworkService（Dio cookie）↔ WebViewDataService
  → 確保 HTTP cookie 與 WebView cookie 一致
  → 用於需要登入狀態的書源
```

## 常見修改入口

- headless WebView JS 執行邏輯 → `lib/core/engine/web_book/headless_webview_service.dart`
- WebView Cookie 同步 → `lib/core/services/webview_data_service.dart`
- 後台 WebView 掛載 → `lib/core/services/backstage_webview.dart`
- 互動式登入（待完整實作）→ `lib/features/source_manager/views/source_login_page.dart`

## 修改路線

- 修改 headless 執行：HeadlessWebViewService 直接和 BackstageWebView 耦合；修改需同步兩個檔案
- 修改 Cookie 同步：WebViewDataService 管理 WebView cookie，需配合 CookieStore（Dio 側）同步

## Known Risks

- headless WebView 依賴 BackstageWebView widget 掛載在 widget tree 中；若 widget 未掛載，所有 headless 請求都會失敗（靜默）
- WebView 冷啟動需要時間，書源驗證時若 WebView 尚未 ready 會超時
- 部分書源的 JS 執行結果需要等待 AJAX 回應（非同步），目前的等待機制是 polling，時機難以掌握
- **互動式登入尚未實作**：需要手動驗證碼或 OAuth 登入的書源，無法自動處理，直接回報書源不可用
- iOS 平台：webview_flutter 在 iOS 上的行為與 Android 有差異，headless 場景尚未充分測試

## Reference Notes

None（standalone 模式）

## Do Not Do

- 不要在 headless WebView 中儲存使用者帳密（安全風險）
- 不要為尚未實作的互動式登入流程建立假 UI（直接回報錯誤）
- 不要讓 headless WebView 執行無限等待（應有超時保護）
