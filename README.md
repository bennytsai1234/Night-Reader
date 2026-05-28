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

### 一鍵校驗書源
匯入大量書源後，一鍵批次校驗。App 會自動幫你過濾掉非小說書源、需要登入才能看的書源、以及 VIP 付費牆——這些通通在校驗時就篩掉，省去手動一個個試的麻煩。

### 排版自由調整
字型大小、行距、字距、段落間距、左右留白、首行縮排……各種細節都能獨立調整，讓閱讀頁面完全符合你的習慣。標點符號也不會出現在行首或行尾，中文排版看起來乾淨整齊。

### 朗讀時逐字標記位置
開啟 TTS 語音朗讀後，畫面會即時高亮目前唸到的位置，精確到每個詞。暫停再繼續時，從上次停下的地方接著唸，不會從頭重來。章節結束後自動接下一章，不需要手動切換。

### 加入書架自動下載
把書加入書架的同時，App 會自動在背景幫你下載全書，之後沒有網路也能繼續看。

### 完整備份還原
一鍵備份所有資料，包含書架、書源、替換規則、書籤、閱讀進度與應用設定，換機或重裝後完整還原，不怕資料流失。

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
