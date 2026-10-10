# 專案規則

Flutter／Dart 專案 `night_reader`，App 名稱「夜讀」。產品說明在 `README.md`，視覺與互動設計在 `DESIGN.md`。寫碼前查 `CODING_STANDARDS.md`（寫碼規範）、`GLOSSARY.md`（用語）與 `docs/adr/`（架構決定，例如為什麼自行維護 `third_party/`、只在 CI 建置發布）。

## 維護範圍

- 工作重心是打磨現有功能：功能改進、UI 修復與精修、體驗與互動優化、精簡、效能調校、相容性調整與重構。
- 全新的產品功能線，需要使用者明確提出。

## 工具鏈

- Flutter `3.47.0`，固定在 `.github/workflows/ci.yml` 與 `android-release.yml`；升級時兩處一起改。
- `third_party/` 的三個 fork 各自的修補紀錄在套件內的 `PATCHES.md`。測試在桌面上跑 QuickJS 用的橋接函式庫放在 `test/fixtures/quickjs/`。

## 驗證

- 自動化驗證就是 `.github/workflows/ci.yml`，PR 合併前必須通過。本機先跑受影響的測試，推送前跑全套。
- 修改 `lib/core/database/tables/`、DAO 或 Drift annotation 後執行 `dart run build_runner build --delete-conflicting-outputs`，產生的 `.g.dart` 一起提交。
- 軟體建置與正式發布一律由 GitHub Actions 負責，本機不進行軟體建置與本機除錯執行。
- Android 實機與模擬器驗證（UI、手勢、滾動、動畫、生命週期、原生外掛、執行效能）是使用者的任務。Agent 不得主動要求、提及或承擔實機驗證，回報中也不列出實機行為相關的未驗證項目。

## Git 流程

- `main` 受分支保護：不能直接推送，所有改動都經 PR，`Analyze and test` 通過後才能合併。
- 一件工作一個分支（`feat/`、`fix/`、`refactor/`、`chore/`、`release/` 開頭），推上去開 PR，以 squash merge 合併；PR 標題就是 `main` 上的 commit message，用 Conventional Commits 格式（`fix(reader): …`）。同一次對話的改動合成一個 PR，不每個小改動各開一個。
- PR 說明寫改了什麼、怎麼驗證。長期有效的內容依性質放：架構決定寫成 `docs/adr/` 的 ADR，寫碼規範寫進 `CODING_STANDARDS.md`，用語寫進 `GLOSSARY.md`；本檔只放從 repo 查不到的事實。

```bash
git switch -c fix/reader-something
# 修改、本機測試、commit
git push -u origin fix/reader-something
gh pr create --fill
gh pr merge --squash --auto --delete-branch
```

## 發布流程

- 發布由 `.github/workflows/android-release.yml` 全權處理（見 ADR 0002）：合併到 `main` 的 commit 若把 `pubspec.yaml` 的 `version: X.Y.Z+build` 升到尚未發布的版本，CI 會建置簽章 APK、建立 `vX.Y.Z` tag 並發布 GitHub Release。
- 發版就是一個只改版號的 PR（分支 `release/X.Y.Z`，標題 `release: bump version to X.Y.Z+build`），照上面的 Git 流程合併。
- 切勿在本機建立或推送 `v*` tag；tag 的唯一擁有者是 CI。
- 合併後檢查一次 GitHub Actions，確認 Android Release 已開始建置即可結束，不必等建置完成。
- 手動 `workflow_dispatch` 與 `internal-test/**` 分支只建置測試 APK artifact，不打 tag、不發布。
- `website/` 推送到 `main` 時由 `.github/workflows/website-deploy.yml` 部署到 GitHub Pages；網站上的功能描述要與 App 實際行為一致。

## Agent skills

### Issue tracker

Issue 放在本 repo 的 GitHub Issues，用 `gh` 操作。見 `docs/agents/issue-tracker.md`。

### Triage labels

使用預設的五個 triage 標籤（`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`）。見 `docs/agents/triage-labels.md`。

### Domain docs

單一 context：根目錄 `GLOSSARY.md` 加 `docs/adr/`。見 `docs/agents/domain.md`。
