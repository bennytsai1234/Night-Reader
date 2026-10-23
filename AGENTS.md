# 專案規則

Flutter／Dart 專案 `night_reader`，App 名稱「夜讀」，發布 Android `arm64-v8a` APK，另附未簽章的 iOS IPA（ADR 0003）。這是使用者自己讀小說用的 App：目標是使用者自己的閱讀體驗，不是使用者數、星星或推廣；使用者自己用得滿意之前不會推薦給別人。

文件各管一件事，開工前照需要讀：

| 檔案 | 放什麼 |
|---|---|
| `README.md` | 給讀者看的產品說明 |
| `DESIGN.md` | 設計原則、否決過的方向、每個畫面與元件的規格 |
| `GLOSSARY.md` | 和使用者討論時用的詞 |
| `CODING_STANDARDS.md` | 寫碼規範，`codex-review` 依它審 |
| `docs/adr/` | 架構與產品決定：為什麼這樣定、否決過什麼；索引在 `docs/adr/README.md` |
| `CHANGELOG.md` | 給讀者看的更新說明（ADR 0010） |
| `HANDOFF.md` | 還沒收尾的事、等使用者決定的事 |
| 本檔 | 和使用者的工作默契、工具鏈、驗證、Git 與發布流程、環境上的坑 |

文件越少越短越好：能從程式、測試、git 歷史、PR 查到的不寫；同一件事只寫在一處，別處用一句話指過去；寫給人看的句子要讓使用者看得懂，不用抽象的工程語彙。

## 和使用者的工作默契

這些是使用者反覆講過、也反覆被漏掉的事，每一條都有過具體的糾正。

- **做到好，不要問**：目標做完、驗證過、沒有要使用者決定的事，就直接合併並回報結果，不問「要不要合併」。途中看到的警告、同一原因的其他問題一起收掉。使用者的話：「幫我把事情做到好，像許願機一樣」。
- **寫給使用者的字全是繁體中文**：對話、PR 標題與說明、審查摘要、commit 說明的本文都是。#93 的 PR 說明寫成英文，是失誤。
- **結果寫在對話裡**：使用者不看 PR 頁面與 GitHub Actions。審查發現、修了什麼、CI 與合併結果都寫進回覆，不寫「見 PR」；PR 留言是留給之後讀歷史的 agent 看的。
- **用使用者的詞，不丟代號**：用 `GLOSSARY.md` 的詞，第一次出現先解釋。不寫 P0／P2、`.g.dart`、pre-push 這類沒解釋的代號；不說「未驗證」「實機」。
- **視覺由使用者在圖上選**：改外觀或動畫前用 `test/support/screenshot.dart` 畫出候選，淺色、深色各一組，使用者選了就寫進 `DESIGN.md` 固定下來，不做成設定讓使用者再選一次（ADR 0030）。使用者說過版型與動畫已經很好，只要小修，不要大改。
- **淺色與深色一起看**：分析配色、框線、陰影與層次時兩邊都要寫、都要量，不只看淺色就假設深色一樣。
- **改之前查有沒有踩過**：先看 `docs/adr/` 與 git 歷史，使用者會問「會不會踩到以前的坑」。要推翻既有 ADR 就明說，不默默改回。
- **使用者說「(adr)」或「寫進 ADR」就當場寫**：這是使用者標記「這是定案、以後不要再提」的方式。
- **修到根**：使用者分得出補丁和根治（「你這只是打補丁而已」）。追到最初出錯的地方，同一原因的問題一次修掉，不加 workaround。
- **合併完就清**：合併後刪本機與遠端分支、`git worktree prune`，`%TEMP%` 裡自己的暫存檔刪掉。使用者每隔幾天就得自己來問一次 worktree 有沒有清，代表這件事常被漏掉。
- **子代理照全域指示**：只用 Haiku；平行開發寫一段話給使用者開新對話。曾經一次開 85 個把額度燒光；2026-10-22 兩個 Opus 實作子代理一起跑，78 分鐘燒完一個五小時額度。
- **審查意見自己核對**：Codex 或子代理的審查結果逐條打開程式核對，屬實才修；使用者說 Codex 的前端意見不可靠；不照對比度這類工具意見調色。

## 維護範圍

- 工作重心是打磨現有功能：功能改進、UI 修復與精修、體驗與互動優化、精簡、效能調校、相容性調整與重構。
- 全新的產品功能線，需要使用者明確提出。
- 設計上的取捨照 `DESIGN.md`「設計原則」與「否決過的方向」；要違反先改對應的 ADR。

## 工具鏈

- Flutter `3.47.0`，固定在 `.github/workflows/ci.yml` 與 `android-release.yml`；升級時兩處一起改（CI 會檢查兩處一致）。
- `third_party/` 的三個 fork 各自的修補紀錄在套件內的 `PATCHES.md`。測試在桌面上跑 QuickJS 用的橋接函式庫放在 `test/fixtures/quickjs/`。

## 驗證

- 自動化驗證就是 `.github/workflows/ci.yml`，推上任何分支都會在 Linux 上執行，結果顯示在 PR 上；發版前 Android Release 會再跑一次，沒通過就不發。本機先跑受影響的測試（加 `-r failures-only`，通過的不印，只印失敗的），全套交給 pre-push hook。
- 本機 Git hook 在 `.githooks/`，clone 後執行 `git config core.hooksPath .githooks` 啟用：commit 前檢查暫存 Dart 檔的格式，push 前跑 `flutter analyze` 與全套測試（只改說明文件，即任何 `.md` 與 `docs/`，的推送略過）。推送時看 hook 輸出的最後一行是 `pre-push: analyze 與全套測試通過`（只改說明文件時是略過的訊息）。
- 修改 `lib/core/database/tables/`、DAO 或 Drift annotation 後執行 `dart run build_runner build`，產生的 `.g.dart`（Drift 產生的資料庫程式）一起提交；CI 會重跑並擋下過時的產物。
- 軟體建置與正式發布一律由 GitHub Actions 負責，本機不進行軟體建置與本機除錯執行。要給使用者看畫面時，用 `test/support/screenshot.dart` 把元件測試畫成 PNG（用法寫在檔頭）；改介面前後要對照整個 App 時，重拍 `test/screens/` 那組固定畫面（平常的全套測試會跳過）。
- 改到轉場、骨架換場、開 App 進場、跳章，或宣稱某段工作已離開主執行緒時，用 `tool/frame_budget_compare.sh` 量前後，表寫進 commit message（`CODING_STANDARDS.md`「動畫」）。
- Android 實機與模擬器驗證（UI、手勢、滾動、動畫、生命週期、原生外掛、執行效能）是使用者的任務。Agent 不得主動要求、提及或承擔實機驗證，回報中也不列出實機行為相關的未驗證項目。

## Git 流程

這一節與發布流程照 ADR 0027（PR 的審查與合併細節在 ADR 0014）；要改流程先改這兩份 ADR。

- 兩條長期分支：`beta` 是預設分支，日常的改動都進這裡；`main` 只快轉到 `beta` 上使用者用過沒問題的提交，用來發正式版，不在 `main` 上提交。
- 只改說明文件（`README.md`、`DESIGN.md`、`GLOSSARY.md`、`CODING_STANDARDS.md`、`AGENTS.md`、`HANDOFF.md`、`docs/`）時，先 `git pull --ff-only`，直接在 `beta` 上改、提交、推上去，不開分支、不審。
- 新功能與維護（程式、測試、CI、hook、`pubspec.yaml`、`website/`）在從 `beta` 開的分支上做，照下面的流程開 PR 合併進 `beta`；跟著功能一起改的文件放在同一個 PR。
- 交代的目標做完、驗證過，也沒有等使用者決定的事，就是告一段落：直接合併，不問使用者要不要合併。合併時把這次要合併的分支併成一條、推上去、開一個以 `beta` 為目標的 PR（PR 說明照 `pr` 技能寫，用繁體中文）。開 PR 後派 Codex 審整個 PR 一次（`codex-review` 技能；沒有 Codex 的環境改派另一個子代理審），核對屬實的問題修在同一個 PR，再用 `gh pr comment` 把審查摘要貼成 PR 留言（發現了什麼、核對結果、修了哪些、沒修的為什麼）；在同一個 PR 把 `HANDOFF.md` 改成合併後的狀態，合併後不另外補交接；合併前 `git fetch` 把最新的 `beta` 併進分支，有新提交就解完衝突推上去，讓 CI 在合併後的狀態重跑；CI 通過（`gh pr checks <PR> --watch` 等結果）後用 `gh pr merge <PR> --squash` 合併，squash commit 的標題與說明取 PR 的標題與說明，PR 的分支由 GitHub 自動刪除。合併後 `git pull --ff-only` 更新本機 `beta`，刪掉本機分支，併進這個 PR 的其他分支也連同遠端一起刪掉，`git worktree prune`。
- `HANDOFF.md` 只寫查不到的事：還沒合併的工作在哪、等使用者決定的事、還沒寫進其他文件的決定；合併了什麼看 PR，發版看 GitHub Actions，環境上的坑寫在本檔「環境」。
- 原型分支不合併；使用者選定、結果寫進 `DESIGN.md` 或 ADR 後就刪掉。
- commit 與 PR 標題用 Conventional Commits 格式（`fix(reader): …`）。
- 改到 App 內容的 PR，在同一個 PR 裡把變化寫進 `CHANGELOG.md` 的 `## 未發布`：一般讀者看得懂的中文，一兩句介紹加條列，不寫內部實作與 commit 前綴；寫的是和上一個正式版相比的最後結果，改到已經寫過的事就改原本那一條，不另外加（ADR 0010）。App 行為沒變的提交（例如只改註解）不寫，改在 commit message 結尾的 trailer 寫 `Release-Notes: none`。
- `beta` 與 `main` 的分支保護只禁止強制推送與刪除，不強制走 PR：versionCode 取發版那個提交的提交數，改寫歷史會讓它變小，已安裝的 App 就無法升級（ADR 0004、0027）。
- 長期有效的內容依性質放：架構與產品決定寫成 `docs/adr/` 的 ADR（並加進 `docs/adr/README.md` 的索引），寫碼規範寫進 `CODING_STANDARDS.md`，用語寫進 `GLOSSARY.md`，畫面與元件規格寫進 `DESIGN.md`；本檔只放從 repo 查不到的事實。

## 發布流程

- 發布由 `.github/workflows/android-release.yml` 全權處理（見 ADR 0002、0004、0027）。`pubspec.yaml` 的 `version` 只寫 `X.Y.Z`，build number（Android versionCode）由 CI 取發版那個提交的提交數。
- 測試版：推上 `beta`（合併 PR 或直接推）時自動把上一個發布之後累積的 App 改動發成 GitHub 預發布版 `vX.Y.(Z+1)-beta.N`（`X.Y.Z` 是目前已發布的正式版，`N` 是之後的提交數），說明取 `CHANGELOG.md` 的 `## 未發布` 裡上一個發布之後新增或改寫的條列。沒有 App 改動就不發；改了 App 卻沒寫「未發布」時這次執行失敗。自動那次沒發出去時，補上原因後執行 `gh workflow run android-release.yml --ref beta -f channel=beta` 補發。日常改進不用升版號。
- 正式版（使用者說要發才做）：在 `beta` 推一個只改版號的 commit（`release: bump version to X.Y.Z`），把 `version` 升到尚未發布的版本，同時把 `CHANGELOG.md` 的 `## 未發布` 改成 `## X.Y.Z`、上面留一個空的 `## 未發布`；這個提交的 CI 通過後，`git push origin <這個提交>:main` 把 `main` 快轉過去。CI 會建置簽章 APK、建立 `vX.Y.Z` tag，並以 `## X.Y.Z` 段落當說明發布 GitHub Release。`main` 收到不在 `beta` 上的提交時 CI 直接失敗。
- 切勿在本機建立或推送 `v*` tag；tag 的唯一擁有者是 CI。
- 推上 `beta` 或快轉 `main` 後，檢查一次 GitHub Actions，確認 Android Release 已開始建置即可結束，不必等建置完成。
- `channel=test` 的手動執行與 `internal-test/**` 分支只建置測試 APK artifact，不打 tag、不發布。
- `website/` 隨 `main` 快轉時由 `.github/workflows/website-deploy.yml` 部署到 GitHub Pages，內容跟著正式版走；網站上的功能描述要與正式版的實際行為一致。

## 環境

從 repo 查不到、踩過才知道的事。

- **同一個資料夾常有好幾個 session**：切分支會影響別人。自己的工作開 repo 外的 worktree 做，開工前 `git branch --show-current` 確認。本機預覽伺服器的 port（例如 8765）被佔用時換一個，不要結束別人的程序。
- **從 `origin/beta` 開分支會推進 `beta`**：家裡這台的全域設定是 `push.default=upstream`，`git worktree add -b <分支> <路徑> origin/beta` 會把上游設成 `beta`，之後 `git push -u origin <分支>` 直接推進 `beta`，不會建同名分支（2026-10-23 踩過）。開分支加 `--no-track`。
- **Claude Code 子代理的 worktree**（`isolation: "worktree"`）放在主資料夾的 `.claude/worktrees/`，起點是主資料夾目前的 commit（通常是 `beta`），不是呼叫端所在的分支；要疊在別的分支上，合併時得自己解衝突，或先把那條分支併進 `beta`。
- **T3 的自動拉取與 worktree 都認 `origin/HEAD`**，`git fetch` 不會更新它。資料夾還停在 `main` 的電腦開工前先 `git fetch`、`git switch beta`、`git remote set-head origin -a`。這台已經是 `beta`，`core.hooksPath` 是相對的 `.githooks`（每個 worktree 跑自己那份 hook）。`main` 收到不在 `beta` 上的提交就讓 Android Release 失敗的檢查，要等 `main` 第一次快轉到 `beta` 才生效。
- **新 worktree 的 sqlite3**：`flutter test` 要下載 sqlite3 的 native asset，公司網路會改掉檔案讓雜湊不符；把主資料夾 `.dart_tool\hooks_runner\shared\sqlite3\build\download-98b4be67\sqlite3.dll` 複製到 worktree 的同一個位置就直接用快取。
- **Linux（雲端 session）跑要字型的測試**（`test/screens`、`test/frame_budget`）：先 `apt-get install fonts-noto-cjk`。一般測試（含打開真的閱讀器的）用測試預設字型，CI 不裝中文字型。雲端機器比 Windows 那台慢約一倍，frame budget 的數字只能同一台交錯比；量不到手機上的合成（raster）成本，測試的資料庫與書源解析在主執行緒，「幀前」數字比手機上重。
- **測試字型每個字一樣寬**，量不出英數字補半格；用 `test/fixtures/fonts/mixed_width_test.ttf`（以 `FontLoader(kReaderV2PunctFontFamily)` 載入，範例在 `test/features/reader_v2/hybrid/half_cell_layout_test.dart`）。
- **`download_service_test` 的「`_dio` 尚未初始化」日誌**不是警告：測試沒準備網路層，只檢查排隊與範圍。
- **Codex 審查的暫存** `%TEMP%\night-reader-codex-out` 是共用的，收尾只刪自己那一輪（`<tag>-*`）的檔案。公司網路的 McAfee 有時擋掉 Codex 最後一次連線，`codex exec` 回非零但報告通常已經寫好；先看報告檔再決定要不要重跑。
- **Windows 上用 Python 寫檔**要給 `newline='\n'`，不然會寫成 CRLF。
- **重新產生 `NightReaderPunct`**：思源黑體繁中版從 `https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/OTF/TraditionalChinese/NotoSansCJKtc-{Regular,Bold}.otf` 下載，fontTools 用 pip 在 repo 外的 venv 安裝；`assets/fonts/generate_punct_font.py` 產出與 repo 內字型只差 `head` 的時間戳。
- **使用者的手機不拿來量測**（2026-10-14 定的）。若使用者日後同意：profile 建置用一個不提交的入口（`main()` 之後把 `developer.Service.getInfo()` 的 ws 位址寫進 `getExternalStorageDirectory()`，vivo 會把 logcat 裡的位址遮掉、intent 參數也不生效），電腦用 `vm_service` 連上後 `setFlag('profiler','true')`，收 `Flutter.Frame` 與 `getCpuSamples`，把 UI isolate 連續忙碌超過 8 ms 的區段依堆疊歸類；vivo 用 adb 安裝會跳確認頁。

## Agent skills

### Issue tracker

Issue 放在本 repo 的 GitHub Issues，用 `gh` 操作。見 `docs/agents/issue-tracker.md`。

### Triage labels

使用預設的五個 triage 標籤（`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`）。見 `docs/agents/triage-labels.md`。

### Domain docs

單一 context：根目錄 `GLOSSARY.md` 加 `docs/adr/`。見 `docs/agents/domain.md`。
