<p align="center">
  <img src="assets/app_icon/inkpage_reader_icon.png" width="100" alt="夜讀">
</p>

<h1 align="center">夜讀</h1>
<h3 align="center">Night Reader</h3>

<p align="center">
  極簡、流暢的自主小說閱讀器，專為長篇閱讀與個人書源管理打造。
</p>

<p align="center">
  <a href="https://github.com/bennytsai1234/Reader/releases">
    <img src="https://img.shields.io/github/v/release/bennytsai1234/Reader?style=flat-square&color=blue" alt="Latest Release">
  </a>
  <img src="https://img.shields.io/badge/Platform-Android-green?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Framework-Flutter-blue?style=flat-square" alt="Flutter">
  <img src="https://img.shields.io/badge/License-GPL--3.0-orange?style=flat-square" alt="License">
</p>

---

## 特色功能

### 📚 書源管理，一鍵搞定
匯入書源後，點一下批次校驗，App 會自動幫你淘汰掉無效的書源——包含連不上的、需要登入的、需要付費訂閱才能存取的，通通篩掉。剩下的才是真正能用的書源，省去手動逐一測試的時間。

### 🔤 閱讀排版，細節全掌握
字型大小、行距、字距、段落間距、左右邊距、首行縮排，每項設定都能單獨調整。標點符號不會出現在行首或行尾，中文排版乾淨整齊，讀起來舒服。

### 🔊 語音朗讀，跟著走不迷路
開啟語音朗讀後，畫面上會即時標示目前唸到哪個詞。暫停後繼續，從上次的地方接著唸，不會從頭來。一章唸完自動接下一章，不需要手動切換。

### 📥 手動離線快取，按需存取
加入書架只儲存書籍資訊、目錄與閱讀進度，不自動下載章節正文。對於確認具有合法授權的內容，可在書籍詳情頁手動點選「預下載章節」啟用離線快取，方便在無網路時閱讀。

### 🗂️ 一鍵備份，換機不怕歸零
書架、書源、替換規則、書籤、閱讀進度、App 設定，全部一次備份。換手機或重裝 App 後匯入備份，一切回到原樣。

---

## 下載安裝

前往 [GitHub Releases](https://github.com/bennytsai1234/Reader/releases) 下載最新版本的 `inkpage-reader-vX.Y.Z-arm64-v8a.apk`，於 Android 設備上安裝即可。

---

## 快速上手

1. 開啟 App，進入**書源管理**。
2. 點擊右上角選單，選擇**網路匯入**或**本地匯入**，加入您信任的書源。
3. 前往**搜尋**頁，在已匯入且確認具合法授權的來源中搜尋內容，並加入書架。
4. 在書架點擊書籍即可開始閱讀。

---

## 常見問題

**Q：安裝後沒有任何小說？**
App 是純工具型閱讀器，不提供也不儲存任何書籍內容。請先匯入書源。

**Q：支援哪些本地電子書格式？**
支援 `TXT`、`EPUB`、`UMD`。

**Q：需要驗證的書源怎麼辦？**
需要瀏覽器互動驗證（如登入、驗證碼）的書源目前不支援，此類書源會直接回報錯誤。建議改用不需驗證的書源。

---

## 開發

請參考 [DEVELOPMENT.md](DEVELOPMENT.md) 了解如何架設開發環境與執行測試。

---

## 免責聲明

本 App 為通用網頁規則解析與本地文本排版工具。**本專案不提供、不內建、不託管、不維護、不推薦、亦不分發任何書籍、章節內容或第三方書源。**

使用者應自行確認其匯入之書源、檔案及內容具有合法授權，方可使用本 App 進行存取。**禁止使用本 App 存取、下載、快取或散布未經著作權人授權之著作內容，亦禁止藉此繞過任何付費機制、登入驗證、存取控制或數位著作權管理（DRM）技術保護措施。**

使用者對其匯入書源所涉及之版權、法律及其他責任，由使用者自行承擔，本專案及開發者不負任何擔保或連帶責任。若任何第三方認為本專案文件或連結涉及權利問題，請透過 GitHub Issue 聯繫，本專案將盡速處理。

## 授權

本專案以 [GPL-3.0](LICENSE) 授權釋出。
