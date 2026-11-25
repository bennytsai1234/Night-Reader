# 專案規則

Flutter／Dart 專案 `night_reader`，App 名稱「夜讀」，發布 Android `arm64-v8a` APK，另附未簽章的 iOS IPA（ADR 0003）。產品取捨與外觀規則在 `DESIGN.md`，各元件與畫面的規格在 `docs/design/`，改哪裡讀哪份。`PRIVACY.md` 和 App 的「隱私說明」一起改。

## 和使用者的工作默契

- **做到好，自己合併**：交代的事自己做到好，途中看到的警告、同一原因的其他問題一起收掉，不另外問；清單上已拍板、審查與 CI 全過且無未決視覺改動的 `feat/` 一樣驗收完直接收尾、自己合併，只有使用者要反覆打磨的新功能才停在分支等說沒問題再收尾（ADR 0049）。
- **結果寫在對話裡**：使用者不看 PR 與 GitHub Actions，審查發現、修了什麼、CI 與合併結果都寫進回覆。
- **視覺由使用者在圖上選**：全新頁面、改版型、動到 `DESIGN.md` 配色或新視覺風格，改前才用 `test/support/screenshot.dart` 畫候選（淺色、深色各一組），選了寫進 `docs/design/`；沿用現有元件與配色的小畫面或微調（加開關、補圖示、既有彈窗組合）直接照 ADR 0030 選最克制的做完、回報附圖即可。要不要做成讀者自己選的設定由使用者決定，預設選最克制的那一種（ADR 0030）。系統畫的畫面與並排比較的做法在 `docs/agents/candidates.md`。版型與動畫只小修，不大改。
- **淺色與深色一起看**：分析配色、框線、陰影與層次時兩邊都寫、都量。
- **使用者說「(adr)」或「寫進 ADR」就當場寫**：這是「定案、以後不要再提」的標記。
- **Codex 的前端意見不可靠**；不照對比度這類工具意見調色。

## 維護範圍

工作重心是打磨現有功能（改進、UI 精修、互動、精簡、效能、相容性、重構）；全新的功能線要使用者明確提出，談定案時照 `docs/agents/new-feature.md` 走一遍觸點。取捨照 `DESIGN.md`，要違反先改對應的 ADR。評估需求時考量所有讀者，不以使用者本人需不需要為依據。
書源、校驗、規則引擎該怎麼表現拿不準時，照 Legado 原始碼做（位置在 `docs/agents/environment.md`），不自己定標準；夜讀刻意不同的寫在 ADR。
**到下一個正式版只收穩**：使用者提的新功能與新設定只在 `PLAN.md`「正式版之後」記一行、不開工，回覆裡說這是新功能；修錯、流暢、外觀的小修照做，使用者在對照 Legado 的清單上勾的選項也照做。階段在 `PLAN.md`，每一項定了什麼在 `docs/proposals/roadmap.md`。

## 開發設定

- 快測：`tool/flutter_test.sh {target}`（`{target}` 是測試檔或資料夾，`--run-skipped -t …` 這類參數照接；錯誤一定印出，輸出整份看）
- 合併前檢查：PR 的 CI（`.github/workflows/ci.yml`）
- 高風險：`lib/core/database/`、`lib/core/backup/`、`lib/core/sync/`、`lib/core/storage/`、`lib/core/local_book/`、`lib/core/background_work/`、`lib/core/download/`、`lib/core/source_check/`、`lib/core/source_switch/`、`lib/core/playback/`、`lib/core/comic/`、`lib/core/engine/`、`lib/core/source/`、`lib/core/network/`、`lib/core/ai_repair/`、`lib/core/ai_find/`、`lib/core/diagnostics/`
- 不能改：`lib/**/*.g.dart`

## 驗證

- 本機只跑受影響的測試，全套測試只在 CI 跑：在整個 `test/` grep 改到的類別與函式，拿掉的輸出文字也 grep 那段字（測試常直接比對它）；測試常放在別的資料夾，例如書源引擎的解析在 `test/core/engine/` 各處都有。
- CI 在開 PR、PR 有新推送、推上 `beta` 時跑；做到一半推分支不會跑。
- 推送前的 hook 看 `pre-push:` 開頭那一行，Git 會在它後面再印遠端訊息。
- 給使用者看畫面：小調整用模擬器的開發模式跑分支、改了就熱重載（`docs/agents/emulator.md`「開發模式」）；候選並排、淺深一起看時用 `test/support/screenshot.dart` 畫成 PNG，對照整個 App 時重拍 `test/screens/`。模擬器只看版面。
- 改到轉場、骨架換場、開 App 進場、跳章，或宣稱某段工作已離開主執行緒時，用 `tool/frame_budget_compare.sh` 量前後，表寫進 commit message。
- 手機上的驗證是使用者的事，不要求、不提及，回報也不列。模擬器由 agent 自己用：發測試版前，與只有正式版才出錯時（`docs/agents/emulator.md`）。
- `third_party/` 是改過的套件，改了記進各自的 `PATCHES.md`。

## Git 與發版

- `beta` 是預設分支，日常改動都進這裡；`main` 只快轉到 `beta` 上使用者用過沒問題的提交，用來發正式版（ADR 0049）。不改寫歷史：versionCode 靠提交數只增不減。
- 只改說明文件（`.md`、`docs/`）時，`git pull --ff-only` 後直接在 `beta` 上改、推，不開分支、不審。
- 程式、測試、CI、hook、`pubspec.yaml`、`website/` 在從 `beta` 開的分支上做，跟著改的文件放同一條分支、一個 PR。發正式版的升版號提交例外（`docs/agents/release.md`）。
- commit 與 PR 標題用 Conventional Commits 格式（`fix(reader): …`），本文用繁體中文。
- **收尾**前讀 `docs/agents/finish.md`，CI 通過要**合併**前讀 `docs/agents/merge.md`；使用者說要**發測試版**或**發正式版**時讀 `docs/agents/release.md`。

## 環境

- **同一個資料夾常有好幾個 session**：自己的工作開 repo 外的 worktree，開工前 `git branch --show-current` 確認。預覽伺服器的 port 被佔用就換一個，不結束別人的程序。
- **開分支加 `--no-track`**：這台的 `push.default=upstream`，從 `origin/beta` 開的分支沒加會直接推進 `beta`。
- **新 worktree 的 sqlite3**：公司網路會改掉 sqlite3 套件下載的 `sqlite3.dll`，雜湊核對不過就建不起來。`.githooks/post-checkout` 會從主資料夾複製核對過的一份；建置仍報雜湊不符時，手動複製主資料夾 `.dart_tool\hooks_runner\shared\sqlite3\build\download-*\` 裡最新的那份到 worktree 的同一個位置。
- 碰到這些情況先讀對應的文件：
  - 使用者說「處理巡檢」、處理標 `auto-audit` 的 issue：`docs/agents/audit-triage.md`
  - 判斷掉幀是誰造成的、某件工作佔不佔主執行緒：`docs/agents/main-thread.md`
  - 幾個旗標互相牽動、要改成狀態機：`docs/state-machines.md`「做法」，做完在那裡加一列
  - 連手機、拿崩潰日誌或書源、在手機上量效能：`docs/agents/phone.md`
  - 重拍網站畫面或短片、改 README 卡片：`docs/agents/website.md`
  - 用真的書源實跑 AI 修復、回報實跑結果：`docs/agents/ai-repair-runs.md`
  - 用真的書源實跑 AI 找書、回報實跑結果：`docs/agents/ai-find-runs.md`
  - 子代理 worktree 或 T3、Linux 上跑字型或幀預算測試、改 CI 全套測試的跑法、Codex 審查、Python 或 `jq`、重新產生標點字型、對照 Legado、連真網站校驗書源或抓正文：`docs/agents/environment.md`

## Agent skills

### Issue tracker

Issue 放在本 repo 的 GitHub Issues，用 `gh` 操作。見 `docs/agents/issue-tracker.md`。

### Triage labels

使用預設的五個 triage 標籤（`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`）。見 `docs/agents/triage-labels.md`。

### Domain docs

單一 context：根目錄 `GLOSSARY.md` 加 `docs/adr/`。見 `docs/agents/domain.md`。
