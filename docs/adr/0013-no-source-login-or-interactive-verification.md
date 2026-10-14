# 書源不支援登入與互動驗證

夜讀不提供書源登入，也不做需要使用者操作的驗證：沒有登入頁、不顯示驗證碼、不為書源開瀏覽器。需要登入或互動驗證才能用的書源，就當成不能用的書源。這讓抓取與解析可以在沒有畫面的地方（背景執行緒、背景下載、書源校驗）照常執行，不必等使用者回應。

## Consequences

- 書源規則裡的 `java.startBrowserAwait`、`java.getVerificationCode` 一律立即拒絕（`SourceInteractionBlockedException`），書源校驗據此把書源標成「已隔離」（排出搜尋與閱讀），不會等到逾時。
- 為了相容 Legado 書源，規則能呼叫的 `source.getLoginInfo`／`putLoginInfo`／`getLoginHeader` 等函式仍然存在，只是讀寫書源自己的快取，沒有任何介面會填入登入資料；`loginUrl`、`loginUi`、`loginCheckJs` 欄位照樣隨書源匯入匯出保留。書源編輯器不顯示「登入網址」。
- 不需要互動的網頁渲染（網址選項 `webView`、`java.webView`）照常支援，它只在背景載入網頁取回 HTML。
