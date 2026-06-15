# 夜讀 Night Reader Atlas 索引

這是本專案的導航地圖。日常工作透過 atlas 入口技能進入：它會先讀取這份索引，選擇相關模組，並自帶變更/調查紀律——這份索引只放地圖，不放流程。

- 在查看程式碼之前，先用它定位相關模組；細節保留在模組文檔中。
- Codebase Atlas 只執行一次來建立這份地圖。只有在明確要求重建／刷新／重新掃描時才重新執行——那是從當前 repo 現實重新建立這份索引的完整掃描。

工作語言：繁體中文 · 交付方式：commit 並 push · 回報方式：純白話

## 專案操作約束

從既有專案指引繼承的規則。所有工作必須遵守：

- **語言**：使用者面向溝通與專案規則討論使用繁體中文。
- **專案定位**：這是 Flutter/Dart 專案 `night_reader`，App 顯示名稱為「夜讀」，是一款受 Legado 啟發的小說閱讀器，主要支援 Android。
- **技術棧**：Flutter + Dart + Provider（狀態管理）+ Drift（SQLite）+ Dio（網路）+ WebView + flutter_js（JS 規則引擎）。
- **發佈流程**：由 `.github/workflows/android-release.yml` 處理。tag 格式為 `v*`。標準流程：`flutter pub get` → `flutter analyze` → `flutter test` → `git push origin HEAD` → `git tag vX.Y.Z` → `git push origin vX.Y.Z`。如需改版號先更新 `pubspec.yaml`。不可對未推送的本地 commit 打 tag。tag 推送後確認 GitHub Actions 的 Android Release workflow 已啟動。
- **產品邊界**：這是小說閱讀器，不要把 Legado 的其他產品線功能（如漫畫、RSS）直接帶進來。
- **回歸重點**：Reader V2 與 Source Manager 是 release 的重點回歸區域。
- **關聯影響**：書源、閱讀器、下載、快取與備份彼此有關聯，修改其中一塊需檢查其他流程。

## 架構決策

開發過程中記錄的跨模組決策。模組層級決策記錄在各模組的已知風險或禁止事項中。

| 標題 | 選擇 | 受影響模組 | 理由 |
|------|------|-----------|------|
| — | — | — | — |

## 模組清單

- [基礎設施](night_reader/infrastructure.md)
- [資料庫與模型](night_reader/database_models.md)
- [規則引擎](night_reader/rule_engine.md)
- [核心服務](night_reader/core_services.md)
- [閱讀器 V2](night_reader/reader_v2.md)
- [書源管理](night_reader/source_manager.md)
- [書架](night_reader/bookshelf.md)
- [搜尋與探索](night_reader/search_explore.md)
- [設定與其他功能](night_reader/settings_features.md)

## 模組摘要

### 基礎設施
擁有 App 入口、依賴注入、設定、常數、工具函式、例外處理、共用 UI（主題／導航／元件）。任何新功能從這裡掛入 Provider 與路由，或當你需要加入新的共用元件、工具函式、全域常數時從這裡開始。

### 資料庫與模型
擁有 Drift SQLite 資料庫、DAO、資料表定義與所有資料模型。當你需要新增或修改資料表、查詢、資料結構，或排查資料持久化相關問題時從這裡開始。變更會影響所有使用這些模型的服務與 UI。

### 規則引擎
擁有書源規則解析的全部能力：analyze_rule（CSS/JSONPath/Regex/XPath 解析）、JS 腳本引擎、Web Book 解析（書單／書資訊／章節列表／內容）、URL 分析。當你需要修改書源解析邏輯、新增解析器、調整 JS 規則相容性時從這裡開始。

### 核心服務
擁有所有業務邏輯服務：網路層（HTTP、Cookie、速率限制）、下載、備份與還原、TTS 朗讀、音訊、快取管理、匯出、本地書籍、書源檢查與驗證、章節內容管線、儲存路徑。當你需要修改下載流程、備份邏輯、快取策略、網路請求處理時從這裡開始。

### 閱讀器 V2
擁有自製閱讀器渲染引擎：版面佈局（layout）、文字渲染（render）、視埠（viewport）、執行時期（runtime）、頁面殼層（shell）。當你需要修改閱讀器排版、翻頁行為、文字樣式、朗讀標示時從這裡開始。這是 release 的重點回歸區域。

### 書源管理
擁有書源的 CRUD 介面、除錯、驗證、分組管理、訂閱、書源切換。當你需要修改書源管理 UI、書源驗證流程、書源編輯器時從這裡開始。與規則引擎和核心服務中的書源檢查服務緊密相關。

### 書架
擁有書架頁面與書籍詳情頁面。當你需要修改書籍展示、書架佈局、書籍資訊顯示、分組管理時從這裡開始。

### 搜尋與探索
擁有搜尋頁面與探索／發現頁面。當你需要修改搜尋流程、搜尋結果顯示、探索頁面佈局時從這裡開始。依賴規則引擎執行實際搜尋與內容解析。

### 設定與其他功能
擁有多個較小的功能模組：設定頁面（閱讀設定、TTS 設定、備份設定、隱私設定、其他設定）、關於頁面、歡迎頁、檔案關聯與深連結、替換規則、快取管理頁面。當你需要修改這些輔助功能時從這裡開始。
