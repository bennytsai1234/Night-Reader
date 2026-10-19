# 專案規則

Flutter／Dart 專案 `night_reader`，App 名稱「夜讀」，發布 Android `arm64-v8a` APK，另附未簽章的 iOS IPA（ADR 0003）。產品說明在 `README.md`，視覺與互動設計在 `DESIGN.md`。寫碼前查 `CODING_STANDARDS.md`（寫碼規範）、`GLOSSARY.md`（用語）與 `docs/adr/`（架構決定，例如為什麼自行維護 `third_party/`、只在 CI 建置發布）。專案現況看 `HANDOFF.md`。

## 維護範圍

- 工作重心是打磨現有功能：功能改進、UI 修復與精修、體驗與互動優化、精簡、效能調校、相容性調整與重構。
- 全新的產品功能線，需要使用者明確提出。

## 工具鏈

- Flutter `3.47.0`，固定在 `.github/workflows/ci.yml` 與 `android-release.yml`；升級時兩處一起改（CI 會檢查兩處一致）。
- `third_party/` 的三個 fork 各自的修補紀錄在套件內的 `PATCHES.md`。測試在桌面上跑 QuickJS 用的橋接函式庫放在 `test/fixtures/quickjs/`。

## 驗證

- 自動化驗證就是 `.github/workflows/ci.yml`，推上任何分支都會在 Linux 上執行，結果顯示在 PR 上；發版前 Android Release 會再跑一次，沒通過就不發。本機先跑受影響的測試，全套交給 pre-push hook。
- 本機 Git hook 在 `.githooks/`，clone 後執行 `git config core.hooksPath .githooks` 啟用：commit 前檢查暫存 Dart 檔的格式，push 前跑 `flutter analyze` 與全套測試（只改說明文件，即任何 `.md` 與 `docs/`，的推送略過）。推送時看 hook 輸出的最後幾行，確認全套通過。
- 修改 `lib/core/database/tables/`、DAO 或 Drift annotation 後執行 `dart run build_runner build`，產生的 `.g.dart` 一起提交；CI 會重跑並擋下過時的產物。
- 軟體建置與正式發布一律由 GitHub Actions 負責，本機不進行軟體建置與本機除錯執行。要給使用者看畫面時，用 `test/support/screenshot.dart` 把元件測試畫成 PNG（用法寫在檔頭）；改介面前後要對照整個 App 時，重拍 `test/screens/` 那組固定畫面（平常的全套測試會跳過）。
- Android 實機與模擬器驗證（UI、手勢、滾動、動畫、生命週期、原生外掛、執行效能）是使用者的任務。Agent 不得主動要求、提及或承擔實機驗證，回報中也不列出實機行為相關的未驗證項目。

## Git 流程

這一節與發布流程照 ADR 0027（PR 的審查與合併細節在 ADR 0014）；要改流程先改這兩份 ADR。

- 兩條長期分支：`beta` 是預設分支，日常的改動都進這裡；`main` 只快轉到 `beta` 上使用者用過沒問題的提交，用來發正式版，不在 `main` 上提交。
- 只改說明文件（`README.md`、`DESIGN.md`、`GLOSSARY.md`、`CODING_STANDARDS.md`、`AGENTS.md`、`HANDOFF.md`、`docs/`）時，先 `git pull --ff-only`，直接在 `beta` 上改、提交、推上去，不開分支、不審。
- 新功能與維護（程式、測試、CI、hook、`pubspec.yaml`、`website/`）在從 `beta` 開的分支上做，照下面的流程開 PR 合併進 `beta`；跟著功能一起改的文件放在同一個 PR。
- 使用者說合併時，把這次要合併的分支併成一條、推上去、開一個以 `beta` 為目標的 PR（PR 說明照 `pr` 技能寫）。開 PR 後派 Codex 審整個 PR 一次（`codex-review` 技能），核對屬實的問題修在同一個 PR，再用 `gh pr comment` 把審查摘要貼成 PR 留言（發現了什麼、核對結果、修了哪些、沒修的為什麼）；在同一個 PR 把 `HANDOFF.md` 改成合併後的狀態，合併後不另外補交接；合併前 `git fetch` 把最新的 `beta` 併進分支，有新提交就解完衝突推上去，讓 CI 在合併後的狀態重跑；CI 通過（`gh pr checks <PR> --watch` 等結果）後用 `gh pr merge <PR> --squash` 合併，squash commit 的標題與說明取 PR 的標題與說明，PR 的分支由 GitHub 自動刪除。合併後 `git pull --ff-only` 更新本機 `beta`，刪掉本機分支，併進這個 PR 的其他分支也連同遠端一起刪掉。
- `HANDOFF.md` 只寫查不到的事：還沒合併的工作在哪、等使用者決定的事、還沒寫進其他文件的決定、環境上的坑；合併了什麼看 PR，發版看 GitHub Actions。
- 原型分支不合併；使用者選定、結果寫進 `DESIGN.md` 或 ADR 後就刪掉。
- commit 與 PR 標題用 Conventional Commits 格式（`fix(reader): …`）。
- 改到 App 內容的 PR，在同一個 PR 裡把變化寫進 `CHANGELOG.md` 的 `## 未發布`：一般讀者看得懂的中文，一兩句介紹加條列，不寫內部實作與 commit 前綴；寫的是和上一個正式版相比的最後結果，改到已經寫過的事就改原本那一條，不另外加（ADR 0010）。App 行為沒變的提交（例如只改註解）不寫，改在 commit message 結尾的 trailer 寫 `Release-Notes: none`。
- `beta` 與 `main` 的分支保護只禁止強制推送與刪除，不強制走 PR：versionCode 取發版那個提交的提交數，改寫歷史會讓它變小，已安裝的 App 就無法升級（ADR 0004、0027）。
- 長期有效的內容依性質放：架構決定寫成 `docs/adr/` 的 ADR，寫碼規範寫進 `CODING_STANDARDS.md`，用語寫進 `GLOSSARY.md`；本檔只放從 repo 查不到的事實。

## 發布流程

- 發布由 `.github/workflows/android-release.yml` 全權處理（見 ADR 0002、0004、0027）。`pubspec.yaml` 的 `version` 只寫 `X.Y.Z`，build number（Android versionCode）由 CI 取發版那個提交的提交數。
- 測試版：推上 `beta`（合併 PR 或直接推）時自動把上一個發布之後累積的 App 改動發成 GitHub 預發布版 `vX.Y.(Z+1)-beta.N`（`X.Y.Z` 是目前已發布的正式版，`N` 是之後的提交數），說明取 `CHANGELOG.md` 的 `## 未發布` 裡上一個發布之後新增或改寫的條列。沒有 App 改動就不發；改了 App 卻沒寫「未發布」時這次執行失敗。自動那次沒發出去時，補上原因後執行 `gh workflow run android-release.yml --ref beta -f channel=beta` 補發。日常改進不用升版號。
- 正式版（使用者說要發才做）：在 `beta` 推一個只改版號的 commit（`release: bump version to X.Y.Z`），把 `version` 升到尚未發布的版本，同時把 `CHANGELOG.md` 的 `## 未發布` 改成 `## X.Y.Z`、上面留一個空的 `## 未發布`；這個提交的 CI 通過後，`git push origin <這個提交>:main` 把 `main` 快轉過去。CI 會建置簽章 APK、建立 `vX.Y.Z` tag，並以 `## X.Y.Z` 段落當說明發布 GitHub Release。`main` 收到不在 `beta` 上的提交時 CI 直接失敗。
- 切勿在本機建立或推送 `v*` tag；tag 的唯一擁有者是 CI。
- 推上 `beta` 或快轉 `main` 後，檢查一次 GitHub Actions，確認 Android Release 已開始建置即可結束，不必等建置完成。
- `channel=test` 的手動執行與 `internal-test/**` 分支只建置測試 APK artifact，不打 tag、不發布。
- `website/` 隨 `main` 快轉時由 `.github/workflows/website-deploy.yml` 部署到 GitHub Pages，內容跟著正式版走；網站上的功能描述要與正式版的實際行為一致。

## Agent skills

### Issue tracker

Issue 放在本 repo 的 GitHub Issues，用 `gh` 操作。見 `docs/agents/issue-tracker.md`。

### Triage labels

使用預設的五個 triage 標籤（`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`）。見 `docs/agents/triage-labels.md`。

### Domain docs

單一 context：根目錄 `GLOSSARY.md` 加 `docs/adr/`。見 `docs/agents/domain.md`。
