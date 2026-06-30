# 夜讀 Night Reader — 開發者說明文件

本文件包含 `夜讀` 閱讀器專案的技術架構、開發環境設定、測試與發布流程。

---

## 專案定位

- **專案名稱**：`night_reader`
- **App 顯示名稱**：`夜讀`（Night Reader）
- **技術棧**：Flutter、Dart、Provider、Drift、Dio、WebView
- **產品方向**：小說閱讀器
- **主要支援場景**：Android 小說閱讀與書源管理
- **維護政策**：feature freeze（功能凍結）。以維護、修 bug、效能調校、重構、既有功能內部改進為主；不新增產品線功能。

---

## 技術架構

### UI 與狀態管理

- Flutter Material App
- `provider` 作為主要狀態管理；Provider 基類 `core/base/base_provider.dart`
- 部分模組透過 `event_bus`（`core/engine/app_event_bus.dart`）做事件溝通

### 資料與持久化

- `drift` + SQLite（`core/database`，20 個 DAO，生成檔 `.g.dart`）
- `shared_preferences` 儲存使用者偏好（key 集中於 `core/constant/prefer_key.dart`）
- 全域配置鏡像 `core/config/app_config.dart`，與 `SettingsProvider` 雙向同步
- 本機檔案系統用於封面、章節內容、快取與備份（路徑於 `core/storage/app_storage_paths.dart`）

### 網路與解析

- `dio`、`cookie_jar`、`dio_cookie_manager`（`core/network` 攔截器 + `core/services/network_service.dart`、`http_client.dart`）
- HTML / CSS / XPath / JSONPath / Regex / JavaScript 規則解析（`core/engine`）
- `flutter_js` 用於 JS 規則相容（`core/engine/js`，因 FFI 無法跨 isolate）
- `webview_flutter` 處理需要互動登入或驗證的書源流程（`core/engine/web_book/headless_webview_service.dart`）

### 閱讀器與媒體

- 自製 Reader V2，八層架構（`features/reader_v2`：shell / application / runtime / content / layout / render / viewport / features）
- `flutter_tts`、`audio_service`、`just_audio` 提供朗讀相關能力（`core/services/tts_service.dart`）

---

## 專案結構

```text
.
├── lib/
│   ├── main.dart                # 應用進入點（DI、crash handler、Workmanager、SplashPage）
│   ├── app_providers.dart       # 全域 Provider 註冊
│   ├── shared/                  # 跨 feature 共用 UI（theme、widgets、navigation）
│   ├── core/
│   │   ├── base/                # Provider 基類
│   │   ├── config/              # 全域配置鏡像
│   │   ├── constant/            # 常數/列舉/Preference key
│   │   ├── database/            # Drift 主庫、tables、20 個 DAO
│   │   ├── di/                  # GetIt 依賴注入
│   │   ├── engine/              # 規則引擎（AnalyzeRule/AnalyzeUrl/JS/WebBook/EventBus）
│   │   ├── exception/           # 應用例外
│   │   ├── local_book/          # TXT/EPUB 本地書格式偵測與解析
│   │   ├── models/              # 資料契約層（Book/BookSource/Chapter...）
│   │   ├── network/             # Dio 攔截器、StrResponse
│   │   ├── services/            # 業務服務層（書源調度/下載/TTS/備份/校驗/日誌...）
│   │   ├── storage/             # 磁碟快取、儲存路徑、用量統計
│   │   ├── utils/               # 工具函式
│   │   └── widgets/             # 共用 widget（書封）
│   └── features/                # 各功能模組
│       ├── about/               # 關於、版本更新、崩潰日誌
│       ├── association/         # 深連結與檔案分享外部意圖
│       ├── book_detail/         # 書籍詳情、目錄、換源、封面
│       ├── bookshelf/           # 書架、批次更新/匯入
│       ├── cache_manager/       # 下載佇列管理頁
│       ├── explore/             # 發現分類瀏覽
│       ├── reader_v2/          # 閱讀器主流程（八層架構）
│       ├── replace_rule/        # 全域替換規則
│       ├── search/             # 多書源搜尋
│       ├── settings/           # 設定頁群
│       ├── source_manager/     # 書源管理、校驗、偵錯、編輯
│       └── welcome/            # 啟動閃屏、底部導航殼
├── test/                        # 單元測試、Widget 測試、重點回歸回歸測試
├── tool/                        # 書源驗證/偵錯腳本（真實書源回歸用）
├── docs/                        # Codebase Atlas 導航地圖與變更紀錄
│   ├── night_reader_index.md    # atlas 索引（入口）
│   ├── night_reader_adapter.md  # 通用 adapter
│   └── night_reader/            # 各模組文件
└── .github/workflows/          # CI / release workflow
```

---

## 開發環境需求

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

### 2. 靜態分析與測試

本機僅做靜態分析與測試，不做 build。APK 建置與發布一律由 GitHub Actions 處理（見 Release 流程）。

```bash
flutter analyze
flutter test
```

### 3. Drift 生成（改過 table/DAO 才需要）

```bash
dart run build_runner build --delete-conflicting-outputs
```

---

## 測試

執行全部測試：

```bash
flutter test
```

書源規則相關變更的回歸，優先用 `tool/` 下的腳本在真實書源上驗證：

- `tool/source_single_debug_test.dart` — 單一書源逐階段偵錯
- `tool/source_batch_validation_test.dart` / `live_source_validation_test.dart` — 批次校驗
- `tool/explore_batch_validation_test.dart` — 發現分類驗證
- 搭配 shell：`tool/run_source_validation.sh`、`tool/flutter_test_with_quickjs.sh`

---

## Release 流程

Android release 由 GitHub Actions workflow `.github/workflows/android-release.yml` 處理。

### 觸發方式

- 推送符合 `v*` 的 tag
- 手動執行 `workflow_dispatch`（`gh workflow run android-release.yml --ref <ref>`）

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

- 如需改版號，先更新 `pubspec.yaml` 並先提交該變更
- 先推送 branch / commit，再建立與推送 release tag
- 不要替尚未推送的本地 commit 建立 tag
- tag 推上去後，確認 GitHub Actions 的 `Android Release` workflow 已開始建置
- 看到遠端 workflow 進入建置階段後，即可結束本次 release 任務，不必等待 build 完成

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

完整依賴請參考 `pubspec.yaml`。關鍵依賴如下：

- `provider`、`event_bus`（狀態管理與事件通訊）
- `dio`、`cookie_jar`、`dio_cookie_manager`（網路請求）
- `drift`、`drift_flutter`（SQLite 資料庫）
- `flutter_js`（JS 規則引擎，FFI 無法跨 isolate）
- `webview_flutter`（headless WebView）
- `flutter_tts`、`audio_service`、`just_audio`（語音朗讀）
- `cached_network_image`、`flutter_cache_manager`（圖片快取）
- `shared_preferences`（使用者偏好）
- `workmanager`（背景任務，Isolate 內需重新初始化 DI，不可執行 JS 規則）
- `app_links`、`receive_sharing_intent`（深連結與分享接收）
- `shelf`、`shelf_router`、`shelf_static`、`network_info_plus`（區域網路傳書伺服器）
- `home_widget`（桌面小工具）
- `fast_gbk`（GB 編碼支援）
- `get_it`、`logger`（依賴注入與日誌）

---

## 文件導覽

本專案的導航地圖位於 `docs/night_reader_index.md`（Codebase Atlas 索引），適合在修改功能前先閱讀。日常工作從 atlas 入口 skill 進入：讀索引、挑相關模組文件、自帶變更/調查紀律。

---

## 開發注意事項

- 本機不做 build；APK 建置與發布一律在 GitHub Actions。
- 書源、閱讀器、下載、快取與備份彼此有關聯，修改其中一塊通常要檢查其他流程。
- Reader V2 與 Source Manager 是 release 的重點回歸區域，變更後需加強驗證。
- 書源驗證流程涉及 WebView、Cookie 與真實網站互動，容易出現只有真機或真實網站才會發生的問題；優先用 `tool/` 腳本重現。
- 後台任務（`main.dart callbackDispatcher`）在 Isolate 跑，需重新初始化 DI，且不可執行 JS 規則。
- 改 Drift table/DAO 必須跑 `build_runner` 重新生成 `.g.dart`，並處理 schema migration。
- `SettingsProvider` ↔ `AppConfig` ↔ `PreferKey` 三方需保持一致，否則 reader/models 會讀到舊值。