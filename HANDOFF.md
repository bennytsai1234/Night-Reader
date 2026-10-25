# 交接（2026-10-25）

## 進行中

- 源倉庫書源相容（分支 `feat/source-compat`；2026-10-25 實測 48 個一般小說書源，#131 修完匯入後 11 個完整通過）：使用者要全部補齊。Cloudflare 已做（ADR 0032）。還沒做，照源倉庫 803 個文字書源的用量排：登入（`loginUrl` 242、`loginUi` 107 個書源）、`startBrowser(Await)`（148，可在看不到的瀏覽器裡載入、不跳畫面）、Jsoup 元素（`org.jsoup` 117；元素物件只有 text/html/attr，缺 `abs:` 屬性與 `Packages.org.jsoup`；搬山人、黃金屋、台灣小說網）、`data:` 網址與網址選項 `type`（67；魔丸）、加解密照 Java 規則重寫（解密只收 Base64、一律 PKCS7、CFB/OFB 區塊大小不同、缺 SHA-512；約 40 個 `java.*` 加解密函式沒有；74 小說網）、Java 類別（`Thread.sleep`、`MessageDigest`、`Mac` 等；七貓、紙間）、`cookie.getKey`（輕小說文庫）、`longToast`、`androidId` 等。神文、番茄 APP 目錄空、愛看吧與豆瓣正文空還沒查。實測腳本不在 repo：用 `SourceChecker` 搭 `toc_require_complete_test.dart` 那種最小 binding 就能連真的網站跑（測試環境沒有 WebView，Cloudflare 與網頁渲染量不到）。

## 先不做

- 定格換場用到其他骨架換場（書籍詳情、發現、書源管理、設定各頁、閱讀器面板與載入畫面）：使用者 2026-10-24 說高刷新率上的卡頓（#105）已經解決，要推廣等使用者提。動手前先跟使用者說要動哪些畫面。
- 十種風格重新設計：使用者說延到很後面，先照現在的用。
- 搜尋相關度排序：使用者回報某個關鍵字排序不對時再看。
- 對比度測試還留著：使用者要拿掉再處理。
- 網站曝光（#60）：只有使用者能做；使用者說自己用得滿意前不推薦給別人，不用提醒。
