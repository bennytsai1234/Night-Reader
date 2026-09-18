<p align="center">
  <img src="assets/app_icon/inkpage_reader_icon.png" width="100" alt="夜讀">
</p>

<h1 align="center">夜讀 · Night Reader</h1>

<p align="center">
  一款以長篇小說閱讀為核心的 Flutter Android 閱讀器。
</p>

<p align="center">
  自行管理書源、本地 TXT、閱讀排版、TTS 與離線內容。
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

## 關於夜讀

夜讀（Night Reader）是一款自主開發的 Android 小說閱讀器，主要面向長篇文字閱讀與自訂書源使用情境。

專案提供網頁書源規則解析、搜尋、目錄與正文讀取、本地 TXT、閱讀器、TTS、離線快取與資料管理等能力。

夜讀目前仍處於持續維護與相容性收斂階段。核心閱讀流程已可使用，但部分功能仍可能受到書源規則、網站結構、Android 裝置、TTS 引擎或特殊資料狀況影響。

本專案不內建任何可直接閱讀的小說或第三方書源。

---

## 目前狀態

| 功能 | 狀態 | 說明 |
|---|---|---|
| 網路書源 | 🧪 可用 | 支援多種規則，但不保證所有書源完全相容 |
| 搜尋與發現 | 🧪 可用 | 實際結果依書源品質與規則而異 |
| 書源校驗 | 🧪 輔助功能 | 用於找出明顯異常，不代表通過後一定可完整閱讀 |
| 書源除錯 | 🧪 可用 | 可逐階段檢查搜尋、詳情、目錄與正文 |
| Reader V2 | ✅ 核心可用 | 持續修正排版、位置恢復與特殊長文情境 |
| 閱讀排版 | ✅ 可用 | 字號、行高、字距、段距、縮排、主題等 |
| 自動翻頁 | 🧪 可用 | 依閱讀器狀態與內容可能存在邊界情況 |
| 書籤 | ✅ 可用 | 支援閱讀位置標記 |
| 替換規則 | ✅ 可用 | 支援正文清理與 Regex 替換 |
| 繁簡轉換 | ✅ 可用 | 支援簡轉繁、繁轉簡 |
| TTS | 🧪 可用 | 裝置、語音引擎與系統背景限制可能影響行為 |
| 離線下載 | 🧪 可用 | 支援下載佇列，但特殊情況下進度或重試狀態仍可能異常 |
| 備份／還原 | 🧪 可用 | 適合作為資料遷移工具，重要資料仍建議保留原始備份 |
| 書架匯入／匯出 | 🧪 可用 | 大型或特殊格式資料可能存在相容性問題 |
| 本地電子書 | ✅ TXT | 目前僅支援 TXT |
| EPUB | ❌ 不支援 | 尚未提供 EPUB 閱讀 |
| 書源訂閱自動更新 | 🚧 未完成 | 目前沒有完整可依賴的自動更新流程 |

> 🧪 表示功能已有實作並可使用，但仍存在相容性或特殊情況限制。

---

## 書源

夜讀以規則式書源為主要網路內容入口，支援包含：

- CSS
- XPath
- JSONPath
- Regex
- JavaScript
- 自訂 HTTP Header
- Cookie
- 部分 WebView 流程
- 多頁目錄與正文
- 書源搜尋與發現

設計上以 Legado 類型書源規則作為重要相容目標，但兩者並非完全相同的執行環境。

複雜 JavaScript、特殊編碼、反爬蟲、登入狀態、WebView、Cookie 或網站行為都可能造成個別書源無法正常運作。

### 書源校驗

夜讀提供批次書源校驗與單一書源除錯工具。

批次校驗主要用來快速發現：

- 搜尋失效
- 發現失效
- 詳情取得失敗
- 目錄失效
- 正文失效
- 上游網站異常
- 部分登入／權限問題

校驗屬於自動化探測，不等同於完整真人閱讀流程。

需要使用者互動的 WebView、驗證碼、特殊登入或網站防護流程，可能無法透過批次校驗正確判斷。

---

## 閱讀器

Night Reader 使用自製 Reader V2 閱讀架構處理長篇文字。

目前包含：

- 長篇正文閱讀
- 閱讀進度保存
- 章節切換
- 字號調整
- 行高
- 字距
- 段距
- 首行縮排
- 閱讀區主題
- 日間／夜間外觀
- 中文標點排版處理
- 點擊區域自訂
- 自動翻頁
- 書籤
- 替換規則
- 繁簡轉換

閱讀器仍是專案中持續調校的重要區域，特別是超長章節、快速切換排版、進度恢復、TTS 跟隨與特殊滾動情況。

---

## TTS 語音朗讀

支援 Android 系統提供的 TTS 能力，包括：

- 語速
- 音調
- 音量
- 語音選擇
- TTS Engine 選擇
- 朗讀進度高亮
- 自動接續內容
- Android 媒體通知整合

不同 Android ROM、TTS Engine 與系統背景限制的行為可能不同。

---

## 搜尋與發現

已匯入並啟用的書源可以參與聯邦搜尋。

搜尋支援：

- 多書源並行
- 搜尋範圍
- 精準搜尋
- 書源失敗資訊
- 失敗來源重試
- 結果合併與排序

如果書源提供發現／分類規則，也可以透過「發現」頁瀏覽分類內容。

搜尋結果與穩定性最終仍取決於各書源及其上游網站。

---

## 書架與書籍

書架提供：

- 收藏與移除
- 閱讀進度
- 書籍封面
- 目錄
- 更新檢查
- 書源切換
- 章節預下載
- 書籍資訊修改
- 本地 TXT 匯入
- 書架資料交換

部分操作涉及多個資料表、下載快取與書源資料，因此遇到異常時建議先保留原始資料再進行大量匯入或還原。

---

## 離線閱讀

加入書架不代表整本小說會自動下載。

可以手動選擇：

- 全部章節
- 從目前章節開始
- 接下來若干章
- 指定章節範圍
- 尚未快取的章節

背景下載提供佇列、暫停、重試與移除等操作。

不同書源的限流、登入狀態、網站異常與目錄變動仍可能造成部分下載失敗。

---

## 本地電子書

目前本地書只支援：

```text
TXT
```

可直接匯入 TXT 並由夜讀解析章節與閱讀位置。

目前不支援 EPUB。

---

## 備份與資料遷移

夜讀提供：

- App 資料備份
- 備份還原
- 書架匯入／匯出
- 書籍 TXT 匯出

備份包含多項本地資料與設定。

由於資料結構仍可能隨版本演進，重要資料建議另外保留原始檔案與舊備份，不建議只保留唯一一份 Night Reader 備份。

---

## 快速開始

1. 前往 GitHub Releases 安裝最新 Android APK。
2. 開啟夜讀並進入「書源管理」。
3. 匯入自己使用的書源。
4. 使用搜尋或發現找到內容。
5. 加入書架並開始閱讀。
6. 如需離線閱讀，可在書籍詳情中建立下載任務。

夜讀預設不附帶第三方書源，因此首次安裝後書架與搜尋來源為空是正常情況。

---

## 系統需求

目前主要支援：

- Android
- arm64-v8a

APK 透過 GitHub Actions 建置並發布至 GitHub Releases。

---

## 專案維護狀態

目前專案以既有功能維護為主，重點包括：

- Bug 修正
- 書源相容性
- Reader V2 穩定性
- 效能調校
- Android 相容性
- 測試與回歸
- 既有架構整理

現階段不以持續增加大型新功能為主要方向。

---

## 開發

技術棧：

- Flutter
- Dart
- Provider
- Drift / SQLite
- Dio
- QuickJS / `flutter_js`
- WebView
- `flutter_tts`

開發與維護文件：

- [DEVELOPMENT.md](DEVELOPMENT.md)：本機工具鏈、驗證與除錯入口
- [DESIGN.md](DESIGN.md)：視覺、主題與互動系統
- [docs/architecture.md](docs/architecture.md)：執行流程與狀態歸屬
- [docs/night_reader_index.md](docs/night_reader_index.md)：Codebase Atlas 模組導航

基本驗證：

```bash
flutter pub get
flutter analyze
flutter test
```

Android APK 建置與 Release 由 GitHub Actions 處理。

---

## 回報問題

如果遇到問題，建議 Issue 至少附上：

- Night Reader 版本
- Android 版本
- 裝置型號
- 發生功能
- 重現步驟
- 錯誤訊息或截圖
- 若與書源有關，請描述是哪一階段失敗

書源網站本身失效、網站改版、反爬蟲或規則不相容，也可能造成閱讀失敗。

---

## 免責聲明

Night Reader 是通用閱讀與網頁規則解析工具，本專案不提供、不託管、不維護、不推薦、亦不分發任何小說內容或第三方書源。

使用者應自行確認其書源、檔案與內容的取得及使用方式符合所在地法律與相關授權條件。

不得利用本專案繞過 DRM、付費機制、登入驗證或其他存取控制措施。

第三方網站、第三方書源及其內容均不由 Night Reader 專案控制，其可用性、合法性與安全性由使用者自行判斷。

---

## License

Night Reader 以 [GNU General Public License v3.0](LICENSE) 授權釋出。
