# 專案規則

Flutter／Dart 專案 `night_reader`，App 名稱「夜讀」，發布 Android `arm64-v8a` APK，另附未簽章的 iOS IPA（ADR 0003）。

| 檔案 | 放什麼 |
|---|---|
| `README.md`、`CHANGELOG.md`、`PRIVACY.md` | 給讀者看的產品說明、正式版更新說明、隱私權政策（`PRIVACY.md` 和 App 的「隱私說明」一起改） |
| `DESIGN.md` | 產品界線、設計原則、否決過的方向；各元件與畫面的規格照區域放在 `docs/design/`，改哪裡讀哪份 |
| `GLOSSARY.md` | 和使用者討論時用的詞 |
| `CODING_STANDARDS.md` | 寫碼規範，`codex-review` 依它審 |
| `docs/adr/` | 決定與理由、否決過什麼；索引在 `docs/adr/README.md` |
| `docs/agents/` | 只在特定情況用到的做法與坑，下面寫明什麼時候讀哪份 |
| `PLAN.md` | 想好了、還沒開工的計畫；開工時搬走 |
| `HANDOFF.md` | 對話之間接手用的交接，只在做到一半要換對話時才有（`handoff` 技能），做完就刪 |

## 和使用者的工作默契

- **做到好，做到可以合併就停**：交代的事自己做到好，途中看到的警告、同一原因的其他問題一起收掉，不為這些另外問（使用者的話：「像許願機一樣」）。全部做完才問要不要收尾，收尾到「可以合併」就停，使用者說「合併」才合併（ADR 0049）。
- **結果寫在對話裡**：使用者不看 PR 與 GitHub Actions。審查發現、修了什麼、CI 與合併結果都寫進回覆，不寫「見 PR」。
- **視覺由使用者在圖上選**：改外觀前用 `test/support/screenshot.dart` 畫出候選，淺色、深色各一組，選了就寫進 `docs/design/` 對應的那份，不做成設定（ADR 0030）。系統畫的畫面（通知、鎖定畫面）與並排比較的做法在 `docs/agents/candidates.md`。版型與動畫只要小修，不要大改。
- **動畫用動畫儀表板說明**：說明動畫、轉場與時間軸，或給候選與改前改後時，照 `animation-dashboard` 技能把儀表板放進對話，再補判斷。
- **淺色與深色一起看**：分析配色、框線、陰影與層次時兩邊都要寫、都要量。
- **使用者說「(adr)」或「寫進 ADR」就當場寫**：這是「定案、以後不要再提」的標記。
- **審查意見**：Codex 的前端意見不可靠；不照對比度這類工具意見調色。

## 維護範圍

工作重心是打磨現有功能（改進、UI 精修、互動、精簡、效能、相容性、重構）；全新的功能線要使用者明確提出，談定案時照 `docs/agents/new-feature.md` 走一遍觸點。取捨照 `DESIGN.md`「產品界線」「設計原則」與「否決過的方向」，要違反先改對應的 ADR。
書源、校驗、規則引擎該怎麼表現拿不準時，照 Legado 原始碼做（位置在 `docs/agents/environment.md`），不自己定標準；夜讀刻意不同的寫在 ADR。
評估需求時考量所有讀者的需求與實際效益，不以使用者本人是否需要為取捨依據。

## 驗證

- CI（`.github/workflows/ci.yml`）在開 PR、PR 有新推送、推上 `beta` 時跑；做的途中推分支只是備份，不跑。本機只跑受影響的測試：在整個 `test/` grep 改到的類別與函式，引用到的檔都算（測試常放在別的資料夾，例如書源引擎的解析在 `test/core/engine/` 各處都有）。用 `tool/flutter_test.sh <測試路徑>`（`--run-skipped -t …` 這類參數照接）：錯誤一定印出、進度行與套件清單濾掉，輸出整份看。全套測試只在 CI 跑。
- 改 `lib/core/database/tables/`、DAO 或 Drift annotation 後執行 `dart run build_runner build`，產生的 `.g.dart` 一起提交。
- 推送前的 hook 跑 `flutter analyze`，看 `pre-push:` 開頭那一行（通過是 `pre-push: analyze 通過（全套測試看 CI）`）；Git 會在它後面再印遠端訊息，只看最後幾行會漏掉。
- 本機不建置、不除錯執行。給使用者看畫面用 `test/support/screenshot.dart` 畫成 PNG；對照整個 App 時重拍 `test/screens/`。
- 改到轉場、骨架換場、開 App 進場、跳章，或宣稱某段工作已離開主執行緒時，用 `tool/frame_budget_compare.sh` 量前後，表寫進 commit message。
- 手機與模擬器上的驗證是使用者的事，不要求、不提及，回報也不列。
- Flutter `3.47.0` 固定在 `ci.yml` 與 `android-release.yml`，升級時兩處一起改。`third_party/` 三個 fork 的修補紀錄在各自的 `PATCHES.md`。

## Git 與發版

- `beta` 是預設分支，日常改動都進這裡；`main` 只快轉到 `beta` 上使用者用過沒問題的提交，用來發正式版（ADR 0049）。分支保護只禁止強制推送與刪除；不改寫歷史，versionCode 靠提交數只增不減。
- 只改說明文件（`.md`、`docs/`）時，`git pull --ff-only` 後直接在 `beta` 上改、推，不開分支、不審。
- 程式、測試、CI、hook、`pubspec.yaml`、`website/` 在從 `beta` 開的分支上做，一件事一條分支、一個 PR，跟著改的文件放同一條分支。發正式版的升版號提交例外，照 `docs/agents/release.md` 直接推上 `beta`。
- commit 與 PR 標題用 Conventional Commits 格式（`fix(reader): …`），本文用繁體中文。
- **收尾**時讀 `docs/agents/finish.md`；使用者說**合併**時讀 `docs/agents/merge.md`；使用者說要**發正式版**時讀 `docs/agents/release.md`。
- 長期有效的內容依性質放：決定寫 ADR（加進索引），寫碼規範寫 `CODING_STANDARDS.md`，用語寫 `GLOSSARY.md`，畫面規格寫 `docs/design/`；本檔只放每件工作都用得到的規則。

## 環境

- **同一個資料夾常有好幾個 session**：切分支會影響別人。自己的工作開 repo 外的 worktree，開工前 `git branch --show-current` 確認。預覽伺服器的 port 被佔用就換一個，不要結束別人的程序。
- **開分支加 `--no-track`**：這台的 `push.default=upstream`，從 `origin/beta` 開的分支沒加會直接推進 `beta`。
- **新 worktree 的 sqlite3**：把主資料夾 `.dart_tool\hooks_runner\shared\sqlite3\build\download-98b4be67\sqlite3.dll` 複製到 worktree 的同一個位置（公司網路會改掉下載的檔案）。
- 碰到這些情況先讀對應的文件：
  - 判斷掉幀是誰造成的、某件工作佔不佔主執行緒：`docs/agents/main-thread.md`
  - 連手機、拿崩潰日誌或書源、在手機上量效能：`docs/agents/phone.md`
  - 重拍網站畫面或短片、改 README 卡片：`docs/agents/website.md`
  - 用真的書源實跑 AI 修復、回報實跑結果：`docs/agents/ai-repair-runs.md`
  - 子代理 worktree 或 T3、Linux 上跑字型或幀預算測試、Codex 審查、Python 或 `jq`、重新產生標點字型、對照 Legado、連真網站校驗書源：`docs/agents/environment.md`

## Agent skills

### Issue tracker

Issue 放在本 repo 的 GitHub Issues，用 `gh` 操作。見 `docs/agents/issue-tracker.md`。

### Triage labels

使用預設的五個 triage 標籤（`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`）。見 `docs/agents/triage-labels.md`。

### Domain docs

單一 context：根目錄 `GLOSSARY.md` 加 `docs/adr/`。見 `docs/agents/domain.md`。
