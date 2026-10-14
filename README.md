<p align="center">
  <img src="assets/app-icon.png" width="100" alt="夜讀">
</p>

<h1 align="center">夜讀 · Night Reader</h1>

<p align="center">
  為長篇小說打造的 Android 閱讀器：自己的書源、自己的排版、離線也能讀。
</p>

<p align="center">
  <a href="https://github.com/bennytsai1234/night-reader/releases">
    <img src="https://img.shields.io/github/v/release/bennytsai1234/night-reader?style=flat-square&color=blue" alt="Latest Release">
  </a>
  <img src="https://img.shields.io/badge/Platform-Android-green?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Framework-Flutter-blue?style=flat-square" alt="Flutter">
  <img src="https://img.shields.io/badge/License-GPL--3.0-orange?style=flat-square" alt="License">
</p>

---

夜讀從你匯入的書源搜尋、閱讀與下載網路小說，也能讀本地 TXT。書源規則相容 [Legado（閱讀）](https://github.com/gedoor/legado)，以 Flutter 重新實作。App 不內建任何書源或小說內容。

## 特色

- **舒服的排版**：字號、行高、字距、段距與縮排都能調，中文標點與中英文混排整齊；紙墨、竹青、石青、茶褐、素色五種風格，搭配淺色、深色或跟隨系統。
- **書架自動離線**：加入書架的書會自動下載整本，有新章節時跟著補上，沒網路也能讀。
- **一次搜遍書源**：多個書源同時搜尋，繁體、簡體一起找，同一本書合成一筆；也能從書源的「發現」分類瀏覽。
- **換源不迷路**：換到其他書源後，閱讀進度停在同一章。
- **聽書**：使用 Android 系統的語音引擎朗讀，可調語速與音調，朗讀中的句子會標示出來。
- **正文整理**：替換規則清掉廣告與雜訊，繁簡互轉。
- **書源工具**：批次校驗找出失效的書源，單一書源可以逐步除錯搜尋、詳情、目錄與正文。
- **資料帶得走**：完整備份與還原、書架匯入匯出、整本匯出成 TXT。

## 下載與更新

到 [GitHub Releases](https://github.com/bennytsai1234/night-reader/releases) 下載最新 APK，支援 Android arm64 裝置。

App 開啟時會自動檢查新版，連著 Wi-Fi 會先在背景下載好再提醒安裝。想搶先試用新功能，可在「我的」→「關於夜讀」打開「接收測試版更新」。各版的改動見「更新紀錄」或 [CHANGELOG.md](CHANGELOG.md)。

## 開始使用

1. 安裝後進入「我的」→「書源管理」，匯入你自己的書源（網址、檔案或剪貼簿）。
2. 用搜尋或發現找書，加入書架。
3. 書架上的書會自動下載，之後離線也能讀。

剛安裝時書架與搜尋都是空的，因為夜讀不附帶書源。

## 關於書源

書源是一份 JSON 規則，描述某個網站怎麼搜尋、怎麼取得詳情、目錄與正文。夜讀支援 Legado 書源常用的 CSS、XPath、JSONPath、Regex 與 JavaScript 規則。

夜讀不支援書源登入，也不做驗證碼這類需要手動操作的驗證，需要這些的書源會被當成無法使用（見 [ADR 0013](docs/adr/0013-no-source-login-or-interactive-verification.md)）。網站改版或擋爬蟲時，書源也可能失效，可以用書源校驗找出來。

## 回報問題

請到 [Issues](https://github.com/bennytsai1234/night-reader/issues) 回報，附上 App 版本、Android 版本、裝置型號與重現步驟；和書源有關的話，說明是搜尋、詳情、目錄還是正文出問題。

## 開發

夜讀以 Flutter／Dart 開發，APK 由 GitHub Actions 建置與發布。工具鏈、驗證與發布流程見 [AGENTS.md](AGENTS.md)，寫碼規範見 [CODING_STANDARDS.md](CODING_STANDARDS.md)，介面設計見 [DESIGN.md](DESIGN.md)，架構決定見 [docs/adr/](docs/adr/)。

## 致謝

- [Legado（閱讀）](https://github.com/gedoor/legado)：夜讀的書源規則與許多功能設計來自這個開源閱讀器。
- [Telegram iOS](https://github.com/TelegramMessenger/Telegram-iOS)：介面結構與互動參考這個開源專案，包括浮動玻璃列、分組清單與情境選單。
- Claude Opus 5.5 與 GPT 6.1 sol：協助本專案的開發。

## 免責聲明

夜讀是通用的閱讀與網頁規則解析工具，不提供、不託管、不推薦也不分發任何小說內容或第三方書源。書源、檔案與內容的取得和使用是否符合所在地法律與授權，由使用者自行確認。不得利用本專案繞過 DRM、付費機制、登入驗證或其他存取控制。

## License

夜讀以 [GNU General Public License v3.0](LICENSE) 授權釋出。
