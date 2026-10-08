# 專案規則

## 專案概觀

- 本專案為 Flutter/Dart 專案 `night_reader`，App 顯示名稱為 `夜讀`，發布目標是 Android `arm64-v8a`。
- 面向人類的產品說明在 `README.md`；視覺與互動設計系統在 `DESIGN.md`。

## 語言

- 面向使用者的溝通與專案規則討論一律使用繁體中文。

## 維護範圍

- 工作重心是打磨現有功能：功能改進、UI 修復與精修、體驗與互動優化、精簡、效能調校、相容性調整與重構。
- 全新的產品功能線，需要使用者明確提出。

## 工具鏈

- Flutter `3.47.0`，固定在 `.github/workflows/android-release.yml` 與 `reader-v2.yml`；升級時兩處一起改。
- Dart SDK 約束以 `pubspec.yaml` 為準；CI 使用 Java 17（Temurin）。
- `third_party/` 是三個 path dependency 的實際依賴來源：`flutter_tts`（上游 4.2.5 + AGP 9 built-in Kotlin build patch）、`flutter_js`（上游 0.8.7 + 同一 patch）、`file_picker`（上游 11.0.3 + Win32 6／AGP 9 相容修補）。修補或同步上游只處理已成立的相容性問題，保留 path dependency，不在同一變更中順帶升級無關套件。

## 驗證

- 自動化驗證以 `flutter analyze` 與 `test/` 的契約／不變量測試為準：先跑受影響責任的測試，再視風險跑 `flutter test` 全套。CI 實際執行的契約套件列在 `.github/workflows/reader-v2.yml`。
- 不為了讓測試可觀測，在 production 程式碼新增 `debug*`、`*ForTesting`、測試專用 getter、靜態 hook 或 UI 狀態快照。
- 軟體建置與正式發布一律由 GitHub Actions 負責，本機不進行軟體建置與本機除錯執行。
- Android 實機與模擬器驗證（UI、手勢、滾動、動畫、生命週期、原生外掛、執行效能）是使用者的任務。Agent 不得主動要求、提及或承擔實機驗證，回報中也不列出實機行為相關的未驗證項目。

## 跨層規則

- 修改 `lib/core/database/tables/`、DAO 或 Drift annotation 後執行 `dart run build_runner build --delete-conflicting-outputs`；表結構變更必須在 `AppDatabase` 提供 schema migration，只更新 `.g.dart` 不代表既有使用者資料可升級。
- 新增會被 Model 或 Reader 直接讀取的偏好時，`SettingsProvider`、`AppConfig` 與 `PreferKey` 三者要一起檢查。
- Reader V2 的樣式會進入 layout signature 與 metrics cache key；字級、行高、字距、縮排、字型或內容轉換的改動要確認快取失效與閱讀位置恢復。
- `lib/main.dart` 與 Workmanager `callbackDispatcher()` 都會呼叫 `configureDependencies()`；背景 isolate 不共用主 isolate 的 GetIt 單例。
- 書源 HTTP 一律經 `NetworkService` 與其攔截器；需要使用者互動的驗證走 WebView，批次校驗不得要求 UI 互動。
- SQLite、SharedPreferences 與 App 私有檔案是三個不同的狀態來源；備份、還原、清理或遷移要逐一確認影響範圍。
- keystore、密碼與 token 不進 repo；release 簽章資料由 GitHub Actions secrets 提供。

## 發布流程

- 採版本號驅動自動發布，由 `.github/workflows/android-release.yml` 全權處理：推送到 `main` 的 commit 若把 `pubspec.yaml` 的 `version: X.Y.Z+build` 升到尚未發布的版本，CI 會跑契約測試、建置簽章 APK、在遠端建立 `vX.Y.Z` tag 並發布 GitHub Release。
- 標準流程：

```bash
# 更新 pubspec.yaml 的 version（例如 0.3.1+178）
flutter analyze
flutter test
git add pubspec.yaml
git commit -m "release: bump version to 0.3.1+178"
git push origin main
```

- 切勿在本機建立或推送 `v*` tag；tag 的唯一擁有者是 CI。
- 推送後檢查一次 GitHub Actions，確認 Android Release 已開始建置即可結束，不必等建置完成。
- 手動 `workflow_dispatch` 與 `internal-test/**` 分支只建置測試 APK artifact，不打 tag、不發布。
- `website/` 推送到 `main` 時由 `.github/workflows/website-deploy.yml` 部署到 GitHub Pages；網站上的功能描述要與 App 實際行為一致。

## 保持 repo 整潔

- 根目錄只放：`AGENTS.md`、`README.md`、`DESIGN.md`、`LICENSE`、ignore 檔、Flutter 工具鏈要求的檔案（`pubspec.yaml`、`pubspec.lock`、`.metadata`、`flutter_native_splash.yaml`），以及 `android/`、`ios/`、`lib/`、`assets/`、`test/`、`third_party/`、`website/`、`.github/`。新檔案放進既有目錄；測試素材放 `test/fixtures/`。
- 取代某樣東西時，同一個變更裡移除舊的：舊的 workflow、腳本、設定，以及指向它們的引用。
- 不建立 `docs/` 或其他文件：規則寫在這裡，行為規格寫成測試，工作歷程寫在 commit message。
- 暫存檔、下載物與交接檔放在 repo 外或 ignore 路徑，任務結束時刪掉。
- 回報完成前檢查 `git status` 與根目錄，沒有新增的雜檔。

## 交付流程（寫給 GPT／Codex；所有 agent 都照做）

1. 來源就是 commit：發布與 CI 都只看已推送的 commit，不從工作目錄另外打包或傳檔。
2. 版本只在 `pubspec.yaml`：發新版就是改版號推上 `main`，不另建 tag、不複製 release 腳本。
3. 歷史留在 git：不建立 `*.bak`、日期複本或備份資料夾；過程中真的需要暫存複本，同一步驟內刪掉。
4. 一件工作一份腳本：新的參數或版本是既有腳本的參數，不複製出 `xxx_v2`。
5. 紀錄：commit message 寫改了什麼、怎麼驗證；長期規則寫進本檔；不寫完工紀錄文件、不做只改文件的「紀錄」commit。
6. 回報簡短：改了什麼、怎麼驗證，不重述範圍、不逐步旁白。
