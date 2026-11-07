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
| `CHANGELOG.md` | 給讀者看的正式版更新說明（ADR 0010；測試版說明是 PR 標題，ADR 0048） |
| `PRIVACY.md` | 公開的隱私權政策，Google 登入的同意畫面連到這裡；和 App 的「隱私說明」一起改 |
| `HANDOFF.md` | 還沒收尾的事、等使用者決定的事 |
| 本檔 | 和使用者的工作默契、工具鏈、驗證、Git 與發布流程、環境上的坑 |

文件越少越短越好：能從程式、測試、git 歷史、PR 查到的不寫；同一件事只寫在一處，別處用一句話指過去；寫給人看的句子要讓使用者看得懂，不用抽象的工程語彙。

## 和使用者的工作默契

這些是使用者反覆講過、也反覆被漏掉的事，每一條都有過具體的糾正。

- **做到好，做到可以合併就停**：交代的事自己做到好，途中看到的警告、同一原因的其他問題一起收掉，不為這些另外問。使用者的話：「幫我把事情做到好，像許願機一樣」。做到一段落問要不要收尾，收尾到「可以合併」就停，使用者說「合併」才合併（「Git 流程」，ADR 0047）。
- **寫給使用者的字全是繁體中文**：對話、PR 標題與說明、審查摘要、commit 說明的本文都是。#93 的 PR 說明寫成英文，是失誤。
- **結果寫在對話裡**：使用者不看 PR 頁面與 GitHub Actions。審查發現、修了什麼、CI 與合併結果都寫進回覆，不寫「見 PR」；PR 說明是留給之後讀歷史的 agent 看的。
- **用使用者的詞，不丟代號**：用 `GLOSSARY.md` 的詞，第一次出現先解釋。不寫 P0／P2、`.g.dart`、pre-push 這類沒解釋的代號；不說「未驗證」「實機」。
- **視覺由使用者在圖上選**：改外觀前用 `test/support/screenshot.dart` 畫出候選，淺色、深色各一組，使用者選了就寫進 `DESIGN.md` 固定下來，不做成設定讓使用者再選一次（ADR 0030）。使用者說過版型與動畫已經很好，只要小修，不要大改。
- **動畫用動畫儀表板說明**：說明動畫、轉場與時間軸，或給候選（含「目前」當對照）與改前改後時，照 `animation-dashboard` 技能（`.claude/skills/animation-dashboard/SKILL.md`）把儀表板放進對話，再補表格與判斷。使用者看儀表板的時間軸、畫面變化與主執行緒判斷問題在哪，實際效果在手機上看（2026-10-24 曾改成只給表格，是誤解，2026-10-26 改回）。
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

- 自動化驗證就是 `.github/workflows/ci.yml`：開 PR、PR 有新推送、推上 `beta` 時在 Linux 上執行（只改說明文件的推送不跑；做的途中推分支只是備份，不跑），結果顯示在 PR 上；發版前 Android Release 會再跑一次，沒通過就不發（ADR 0048）。本機只跑受影響的測試（加 `-r failures-only`，通過的不印，只印失敗的），全套測試只在 CI 跑（ADR 0014）。
- 本機 Git hook 在 `.githooks/`，clone 後執行 `git config core.hooksPath .githooks` 啟用：commit 前檢查暫存 Dart 檔的格式，push 前跑 `flutter analyze`（只改說明文件，即任何 `.md` 與 `docs/`，以及推的提交已經在本機記錄的 `origin/beta` 上時略過；套件設定檔不存在或比 `pubspec.yaml`、`pubspec.lock` 舊時先照 lock 檔裝好套件）。推送時看 hook 印的 `pre-push:` 開頭那一行是 `pre-push: analyze 通過（全套測試看 CI）`（只改說明文件時是略過的訊息）；Git 會在它後面再印遠端的訊息，只看最後幾行會漏掉它。
- 修改 `lib/core/database/tables/`、DAO 或 Drift annotation 後執行 `dart run build_runner build`，產生的 `.g.dart`（Drift 產生的資料庫程式）一起提交；CI 會重跑並擋下過時的產物。
- 軟體建置與正式發布一律由 GitHub Actions 負責，本機不進行軟體建置與本機除錯執行。要給使用者看畫面時，用 `test/support/screenshot.dart` 把元件測試畫成 PNG（用法寫在檔頭）；改介面前後要對照整個 App 時，重拍 `test/screens/` 那組固定畫面（平常的全套測試會跳過）。
- 改到轉場、骨架換場、開 App 進場、跳章，或宣稱某段工作已離開主執行緒時，用 `tool/frame_budget_compare.sh` 量前後，表寫進 commit message（`CODING_STANDARDS.md`「動畫」）。
- Android 實機與模擬器驗證（UI、手勢、滾動、動畫、生命週期、原生外掛、執行效能）是使用者的任務。Agent 不得主動要求、提及或承擔實機驗證，回報中也不列出實機行為相關的未驗證項目。

## Git 流程

這一節與發布流程照 ADR 0027；分支什麼時候收尾、什麼時候合併照 ADR 0047，squash、審查範圍與原型分支照 ADR 0014。要改流程先改這三份 ADR。

- 兩條長期分支：`beta` 是預設分支，日常的改動都進這裡；`main` 只快轉到 `beta` 上使用者用過沒問題的提交，用來發正式版，不在 `main` 上提交。
- 只改說明文件（`README.md`、`DESIGN.md`、`GLOSSARY.md`、`CODING_STANDARDS.md`、`AGENTS.md`、`HANDOFF.md`、`docs/`）時，先 `git pull --ff-only`，直接在 `beta` 上改、提交、推上去，不開分支、不審；分支上的工作的交接例外，改在那條分支上。
- 新功能與維護（程式、測試、CI、hook、`pubspec.yaml`、`website/`）在從 `beta` 開的分支上做（repo 外的 worktree，見「環境」），跟著功能一起改的文件放在同一條分支。一件事一條分支、一個 PR，途中的修正與小改動疊在同一條分支上。
- 開工時先看兩件事：`gh pr list` 有沒有開好、等合併的 PR（有就提醒使用者一次）；`beta` 上最近一次 CI 與 Android Release 有沒有失敗（失敗就先告訴使用者並修）。
- 做的途中每段驗證過就 commit 並推上；推分支只是備份，這時不跑 CI。交代的事全部做完、驗證過，手上沒有待辦、也沒有要問使用者的事，才回報做了什麼、問要不要收尾：「Codex 審查後收尾」「不審直接收尾」「繼續改」。還有待辦就繼續做，有要使用者決定的事先問那件事；不是做完一步就問。做到一半先停下的工作，交接寫在那條分支自己的 `HANDOFF.md`，`beta` 的不寫（全域指示「交接跟著分支」）。
- 收尾（ADR 0047），做到「可以合併」就停，不合併：
  1. 使用者選了審查，而且改到 App 內容（`sh tool/changelog.sh app-files origin/beta HEAD` 有輸出），就派 Codex 審整條分支一次（`codex-review` 技能；沒有 Codex 的環境改派另一個子代理審）。只改網站、CI、hook、工具腳本、測試，或只是還原（revert）先前提交的不審。核對屬實的問題修掉，修完只重跑這次修正改到的測試檔。
  2. 把 `HANDOFF.md` 改成合併後的狀態：以 `beta` 那份為底、拿掉這條分支的交接；要留給以後的事（等使用者決定、先不做）加進 `beta` 那份的內容。
  3. `git fetch` 把最新的 `beta` 併進來、解完衝突，推上去，開以 `beta` 為目標的 PR（標題照下面「PR 標題」；說明照 `pr` 技能寫，用繁體中文，有審查就寫一段「審查」：發現了什麼、核對結果、修了哪些、沒修的為什麼）。
  4. `gh pr checks --watch --fail-fast` 等 CI 與標題檢查（有一項失敗就馬上停下來看原因、修好重推）。
  5. 刪掉 worktree 與本機分支（遠端分支留著給合併用），回報「可以合併」；別的分支要用到這條的修正時，說明「這條要先合」。
- 合併（使用者說「合併」才做，ADR 0047）：一次只有一個 Agent 合併。`gh pr list` 列出可以合併的 PR，一個一個來：
  1. `git fetch`；`beta` 在這條 PR 最後一次 CI 之後有新提交，就在 worktree 裡把 `beta` 併進來、解衝突、推上去、等 CI 通過；沒有就跳過這步。
  2. `gh pr merge <PR> --squash`，squash commit 的標題與說明取 PR 的標題與說明，GitHub 自動刪掉遠端分支。
  3. 全部合完：`git pull --ff-only` 更新本機 `beta`、`git worktree prune`，等 `beta` 上最後一次 CI 跑完（中間幾次合併各自的 CI 會被下一次取消）。
  4. 通過了就執行 `gh workflow run android-release.yml --ref beta -f channel=beta` 發這一批的測試版（沒有 App 改動時它照常結束、不發），確認開始建置就結束，不等 APK。沒通過就留下來修：開小分支修、開 PR、等 CI、合併，再回到第 3 步；某個 PR 本身的邏輯一時修不好，就 `git revert` 它的合併提交推上 `beta`，告訴使用者它要回去重做。
  5. 回報合了哪些、測試版發了沒。合併 Agent 不審查，除了解衝突與修 `beta` 的 CI 也不改程式；衝突牽涉到邏輯、自己判斷不了時，停下來問使用者。
- `beta` 的 `HANDOFF.md` 只寫查不到的事：等使用者決定的事、還沒寫進其他文件的決定；分支上的工作看那條分支的 `HANDOFF.md`（`git branch -a` 列出所有分支），合併了什麼看 PR，發版看 GitHub Actions，環境上的坑寫在本檔「環境」。
- 原型分支不合併；使用者選定、結果寫進 `DESIGN.md` 或 ADR 後就刪掉。
- commit 與 PR 標題用 Conventional Commits 格式（`fix(reader): …`）。
- PR 標題：改到 App 內容的 PR，標題去掉前綴就是測試版說明的一行（ADR 0048）。寫一般讀者看得懂的一句，不寫內部實作、具名書源與網址，145 字以內；`pr-title.yml` 會檢查。App 行為沒變的改動（例如只改註解）在 PR 說明（也就是 squash 後的 commit message）裡單獨一行寫 `Release-Notes: none`，這種提交不算 App 改動，不進測試版說明。
- `beta` 與 `main` 的分支保護只禁止強制推送與刪除，不強制走 PR：versionCode 取發版那個提交的提交數，改寫歷史會讓它變小，已安裝的 App 就無法升級（ADR 0004、0027）。
- 長期有效的內容依性質放：架構與產品決定寫成 `docs/adr/` 的 ADR（並加進 `docs/adr/README.md` 的索引），寫碼規範寫進 `CODING_STANDARDS.md`，用語寫進 `GLOSSARY.md`，畫面與元件規格寫進 `DESIGN.md`；本檔只放從 repo 查不到的事實。

## 發布流程

- 發布由 `.github/workflows/android-release.yml` 全權處理（見 ADR 0002、0004、0027）。`pubspec.yaml` 的 `version` 只寫 `X.Y.Z`，build number（Android versionCode）由 CI 取發版那個提交的提交數。
- 測試版：合併的人合完一批、`beta` 的 CI 通過後執行 `gh workflow run android-release.yml --ref beta -f channel=beta`，把上一個發布之後累積的 App 改動發成 GitHub 預發布版 `vX.Y.(Z+1)-beta.N`（`X.Y.Z` 是目前已發布的正式版，`N` 是之後的提交數），說明是這段期間改到 App 的 PR 標題，一個一行（ADR 0048）。推上 `beta` 不會自動發；沒有 App 改動就不發。日常改進不用升版號。
- 正式版（使用者說要發才做）：先用 `sh tool/changelog.sh titles v<上一個正式版> origin/beta` 列出上一個正式版之後的改動，再用 `codex-review` 拿 `website/index.html` 逐段對照這份清單與程式，不符的照一般流程開 PR 修好（網站隨 `main` 部署）。接著在 `beta` 推一個只改版號的 commit（`release: bump version to X.Y.Z`），把 `version` 升到尚未發布的版本，同時在 `CHANGELOG.md` 最上面加上 `## X.Y.Z`：從那份清單整理成一兩句介紹加最多八條平鋪條列，一般讀者看得懂，不寫具名書源與網址（ADR 0010）；這個提交的 CI 通過後，`git push origin <這個提交>:main` 把 `main` 快轉過去。CI 會建置簽章 APK、建立 `vX.Y.Z` tag，並以 `## X.Y.Z` 段落當說明發布 GitHub Release。`main` 收到不在 `beta` 上的提交時 CI 直接失敗。
- 切勿在本機建立或推送 `v*` tag；tag 的唯一擁有者是 CI。
- 發測試版或快轉 `main` 後，檢查一次 GitHub Actions，確認 Android Release 已開始建置即可結束，不必等建置完成。
- `channel=test` 的手動執行與 `internal-test/**` 分支只建置測試 APK artifact，不打 tag、不發布。
- `website/` 隨 `main` 快轉時由 `.github/workflows/website-deploy.yml` 部署到 GitHub Pages，內容跟著正式版走；網站上的功能描述要與正式版的實際行為一致。

## 環境

從 repo 查不到、踩過才知道的事。

- **同一個資料夾常有好幾個 session**：切分支會影響別人。自己的工作開 repo 外的 worktree 做，開工前 `git branch --show-current` 確認。本機預覽伺服器的 port（例如 8765）被佔用時換一個，不要結束別人的程序。
- **從 `origin/beta` 開分支會推進 `beta`**：家裡這台的全域設定是 `push.default=upstream`，`git worktree add -b <分支> <路徑> origin/beta` 會把上游設成 `beta`，之後 `git push -u origin <分支>` 直接推進 `beta`，不會建同名分支（2026-10-23 踩過）。開分支加 `--no-track`。
- **新 worktree 的 sqlite3**：`flutter test` 要下載 sqlite3 的 native asset，公司網路會改掉檔案讓雜湊不符；把主資料夾 `.dart_tool\hooks_runner\shared\sqlite3\build\download-98b4be67\sqlite3.dll` 複製到 worktree 的同一個位置就直接用快取。
- **哪些工作會卡動畫**：判斷掉幀是誰造成的、說某件工作會不會佔主執行緒之前，先讀 `docs/agents/main-thread.md`。檢查書架更新、書架自動下載這些在背景 isolate 跑，曾經被誤當成卡頓的嫌疑。
- **使用者的手機**：連手機、從手機拿崩潰日誌或書源、在手機上量效能時，先讀 `docs/agents/phone.md`。
- **網站與 README**：重拍網站上的 App 畫面或短片、改 README 的卡片時，先讀 `docs/agents/website.md`。
- **其他情況的坑**：用到子代理 worktree 或 T3、在 Linux 跑字型或幀預算測試、Codex 審查、用 Python 或 `jq`、重新產生標點字型、對照 Legado 原始碼、連真網站校驗書源時，先讀 `docs/agents/environment.md`。

## Agent skills

### Issue tracker

Issue 放在本 repo 的 GitHub Issues，用 `gh` 操作。見 `docs/agents/issue-tracker.md`。

### Triage labels

使用預設的五個 triage 標籤（`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`）。見 `docs/agents/triage-labels.md`。

### Domain docs

單一 context：根目錄 `GLOSSARY.md` 加 `docs/adr/`。見 `docs/agents/domain.md`。
