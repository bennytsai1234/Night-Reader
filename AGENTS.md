# 專案規則

## 專案概觀

- 本專案為 Flutter/Dart 專案 `night_reader`，App 顯示名稱為 `夜讀`，發布目標是 Android `arm64-v8a`。
- 面向人類的產品說明在 `README.md`；視覺與互動設計系統在 `DESIGN.md`。

## 維護範圍

- 工作重心是打磨現有功能：功能改進、UI 修復與精修、體驗與互動優化、精簡、效能調校、相容性調整與重構。
- 全新的產品功能線，需要使用者明確提出。

## 工具鏈

- Flutter `3.47.0`，固定在 `.github/workflows/ci.yml` 與 `android-release.yml`；升級時兩處一起改。
- Dart SDK 約束以 `pubspec.yaml` 為準；CI 使用 Java 17（Temurin）。
- `third_party/` 是本專案自行維護的三個套件，以 path dependency 引用，不再追上游：`flutter_tts`（源自 4.2.5）、`flutter_js`（源自 0.8.7）、`file_picker`（源自 11.0.3）；各自的修補紀錄在套件內的 `PATCHES.md`。只保留 Android 實作；視同專案程式碼，套用同一套 lint 與格式檢查。測試在桌面上跑 QuickJS 用的橋接函式庫放在 `test/fixtures/quickjs/`。

## 驗證

- 自動化驗證就是 `.github/workflows/ci.yml`：`dart format`（不含 `*.g.dart`）、`flutter analyze`（`flutter_lints`）與 `flutter test` 全套，PR 合併前必須通過。本機先跑受影響責任的測試，推送前跑全套。
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

## Git 流程

- `main` 受分支保護：不能直接推送，所有改動都經 PR，`Analyze and test` 通過後才能合併。
- 一件工作一個分支（`feat/`、`fix/`、`refactor/`、`chore/`、`release/` 開頭），推上去開 PR，以 squash merge 合併；PR 標題就是 `main` 上的 commit message，用 Conventional Commits 格式（`fix(reader): …`）。
- PR 說明寫改了什麼、怎麼驗證；長期規則寫進本檔，不寫完工紀錄文件。

```bash
git switch -c fix/reader-something
# 修改、本機測試、commit
git push -u origin fix/reader-something
gh pr create --fill
gh pr merge --squash --auto --delete-branch
```

## 發布流程

- 採版本號驅動自動發布，由 `.github/workflows/android-release.yml` 全權處理：合併到 `main` 的 commit 若把 `pubspec.yaml` 的 `version: X.Y.Z+build` 升到尚未發布的版本，CI 會跑完整驗證、建置簽章 APK、在遠端建立 `vX.Y.Z` tag 並發布 GitHub Release。發布只看已合併的 commit，不從工作目錄另外打包或傳檔。
- 發版就是一個只改版號的 PR（分支 `release/X.Y.Z`，標題 `release: bump version to X.Y.Z+build`），照上面的 Git 流程合併。
- 切勿在本機建立或推送 `v*` tag；tag 的唯一擁有者是 CI。
- 合併後檢查一次 GitHub Actions，確認 Android Release 已開始建置即可結束，不必等建置完成。
- 手動 `workflow_dispatch` 與 `internal-test/**` 分支只建置測試 APK artifact，不打 tag、不發布。
- `website/` 推送到 `main` 時由 `.github/workflows/website-deploy.yml` 部署到 GitHub Pages；網站上的功能描述要與 App 實際行為一致。

## 保持 repo 整潔

- 根目錄只放：`AGENTS.md`、`README.md`、`DESIGN.md`、`LICENSE`、ignore 檔、Flutter 工具鏈要求的檔案（`pubspec.yaml`、`pubspec.lock`、`analysis_options.yaml`、`.metadata`、`flutter_native_splash.yaml`），以及 `android/`、`ios/`、`lib/`、`assets/`、`test/`、`third_party/`、`website/`、`.github/`。新檔案放進既有目錄；測試素材放 `test/fixtures/`。
