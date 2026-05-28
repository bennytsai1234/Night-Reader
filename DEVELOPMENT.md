# 墨頁 Inkpage Reader - 開發者說明文件

本文件包含 `墨頁` 閱讀器專案的技術架構、開發環境設定、測試與發布流程。

---

## 專案定位

- **專案名稱**：`night_reader`
- **App 顯示名稱**：`夜讀`（Night Reader）
- **技術棧**：Flutter、Dart、Provider、Drift、Dio、WebView
- **產品方向**：受 Legado 啟發的小說閱讀器
- **主要支援場景**：Android 小說閱讀與書源管理

---

## 技術架構

### UI 與狀態管理

- Flutter Material App
- `provider` 作為主要狀態管理
- 部分模組透過 `event_bus` 做事件溝通

### 資料與持久化

- `drift` + SQLite
- `shared_preferences` 儲存使用者偏好
- 本地檔案系統用於封面、章節內容、快取與備份

### 網路與解析

- `dio`、`cookie_jar`、`dio_cookie_manager`
- HTML / CSS / XPath / JSONPath / Regex / JavaScript 規則解析
- `flutter_js` 用於部分 JS 規則相容能力
- `webview_flutter` 處理需要互動登入或驗證的書源流程

### 閱讀器與媒體

- 自製 Reader V2 排版、渲染、viewport 與 runtime
- `flutter_tts`、`audio_service`、`just_audio` 提供朗讀相關能力

---

## 專案結構

```text
.
├── lib/
│   ├── core/                  # 核心模型、資料庫、規則引擎、服務、工具
│   ├── features/              # 各功能模組
│   │   ├── about/             # 關於頁面、更新檢查
│   │   ├── association/       # 檔案關聯與深連結處理
│   │   ├── book_detail/       # 書籍詳情
│   │   ├── bookshelf/         # 書架
│   │   ├── cache_manager/     # 下載管理頁面
│   │   ├── explore/           # 探索
│   │   ├── reader_v2/         # 閱讀器主流程
│   │   ├── replace_rule/      # 全域替換規則
│   │   ├── search/            # 搜尋
│   │   ├── settings/          # 設定
│   │   ├── source_manager/    # 書源管理
│   │   └── welcome/           # 啟動畫面
│   ├── app_providers.dart
│   └── main.dart
├── test/                      # 單元測試、Widget 測試、重點回歸測試
├── docs/                      # 專案架構與模組導覽文件
├── assets/                    # 預設資源、預設書源、opencc 資料
└── .github/workflows/         # CI / release workflow
```

---

## 開發環境需求

建議環境：

- Flutter `3.41.6`
- Dart SDK `^3.7.0`
- Java `17`
- Android SDK 與可用裝置 / 模擬器

---

## 快速開始

### 1. 安裝依賴

```bash
flutter pub get
```

### 2. 啟動專案

```bash
flutter run
```

如果要指定裝置：

```bash
flutter devices
flutter run -d <device-id>
```

### 3. 靜態分析

```bash
flutter analyze
```

---

## 測試

執行全部測試：

```bash
flutter test
```

---

## Release 流程

Android release 由 GitHub Actions workflow `.github/workflows/android-release.yml` 處理。

### 觸發方式

- 推送符合 `v*` 的 tag
- 手動執行 `workflow_dispatch`（可透過 GitHub CLI `gh workflow run android-release.yml --ref <ref>` 觸發）

### 標準發布流程

```bash
flutter pub get
flutter analyze
flutter test
git push origin HEAD
git tag vX.Y.Z
git push origin vX.Y.Z
```

### 發布規則

- 如果需要改版號，先更新 `pubspec.yaml`
- 先推送 branch / commit，再建立與推送 release tag
- 不要替尚未推送的本地 commit 建立 tag
- tag 推上去後，要確認 GitHub Actions 的 `Android Release` workflow 已經開始執行
- 看到遠端 workflow 已進入建置階段後，可以結束本次 release 任務，不必等待整個 build 完成

### Release workflow 目前會做的事

- checkout 原始碼
- 安裝 Java 17
- 安裝 Flutter `3.41.6`
- `flutter pub get`
- 執行關鍵 analyze / test
- 解出 Android release keystore
- 建置 `arm64-v8a` release APK
- 驗證 manifest
- 發佈 GitHub Release 與 APK 附件

---

## 重要相依套件

完整依賴請參考 [pubspec.yaml](file:///home/benny/projects/reader/pubspec.yaml)。關鍵依賴如下：

- `provider`、`event_bus`（狀態管理與事件通訊）
- `dio`、`cookie_jar`、`dio_cookie_manager`（網路請求）
- `drift`、`drift_flutter`（SQLite 資料庫）
- `flutter_js`（JS 規則引擎）
- `webview_flutter`（headless WebView）
- `flutter_tts`、`audio_service`、`just_audio`（語音朗讀）
- `cached_network_image`、`flutter_cache_manager`（圖片快取）
- `shared_preferences`（使用者偏好）
- `workmanager`（背景任務）
- `app_links`、`receive_sharing_intent`（深連結與分享接收）
- `shelf`、`shelf_router`、`shelf_static`、`network_info_plus`（區域網路傳書伺服器）
- `home_widget`（桌面小工具）
- `fast_gbk`（GB 編碼支援）

---

## 文件導覽

`docs/` 目錄包含專案的模組導覽與設計地圖，適合在修改功能前先閱讀。

- [Atlas 索引](docs/night_reader_index.md)
- [主工作流程](docs/night_reader_main_workflow.md)
- [規則引擎](docs/night_reader/rule_engine.md)
- [書源管理](docs/night_reader/source_manager.md)
- [閱讀器 V2](docs/night_reader/reader_v2.md)
- [書架與書籍](docs/night_reader/bookshelf.md)
- [搜尋與探索](docs/night_reader/search_explore.md)
- [下載與快取](docs/night_reader/download_cache.md)
- [瀏覽器驗證](docs/night_reader/browser.md)
- [設定與備份](docs/night_reader/settings_backup.md)
- [應用基礎設施](docs/night_reader/infrastructure.md)

---

## 開發注意事項

- 這是小說閱讀器，不要把 Legado 的其他產品線功能（如漫畫、RSS）直接帶進來。
- 書源、閱讀器、下載、快取與備份彼此有關聯，修改其中一塊通常要檢查其他流程。
- Reader V2 與 Source Manager 是 release 的重點回歸區域。
- 書源驗證流程涉及 WebView、Cookie 與實際網站互動，容易出現只有真機或真實網站才會發生的問題。
