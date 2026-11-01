# 環境上的坑

從 repo 查不到、踩過才知道的事，只在碰到對應情況時用得到。每件工作都用得到的（開 worktree、`--no-track`、sqlite3）在 `AGENTS.md`「環境」。

## Git 與 worktree

- **Claude Code 子代理的 worktree**（`isolation: "worktree"`）放在主資料夾的 `.claude/worktrees/`，起點是主資料夾目前的 commit（通常是 `beta`），不是呼叫端所在的分支；要疊在別的分支上，合併時得自己解衝突，或先把那條分支併進 `beta`。
- **T3 的自動拉取與 worktree 都認 `origin/HEAD`**，`git fetch` 不會更新它。資料夾還停在 `main` 的電腦開工前先 `git fetch`、`git switch beta`、`git remote set-head origin -a`。家裡這台已經是 `beta`，`core.hooksPath` 是相對的 `.githooks`（每個 worktree 跑自己那份 hook）。`main` 收到不在 `beta` 上的提交就讓 Android Release 失敗的檢查，要等 `main` 第一次快轉到 `beta` 才生效。

## 測試

- **Linux（雲端 session）跑要字型的測試**（`test/screens`、`test/frame_budget`、`test/polish`）：先 `apt-get install fonts-noto-cjk`。一般測試（含打開真的閱讀器的）用測試預設字型，CI 不裝中文字型。雲端機器比 Windows 那台慢約一倍，frame budget 的數字只能同一台交錯比；量不到手機上的合成（raster）成本，測試的資料庫與書源解析在主執行緒，「幀前」數字比手機上重。
- **測試字型每個字一樣寬**，量不出英數字補半格；用 `test/fixtures/fonts/mixed_width_test.ttf`（以 `FontLoader(kReaderV2PunctFontFamily)` 載入，範例在 `test/features/reader_v2/hybrid/half_cell_layout_test.dart`）。
- **`download_service_test` 的「`_dio` 尚未初始化」日誌**不是警告：測試沒準備網路層，只檢查排隊與範圍。

## 工具

- **Codex 審查的暫存** `%TEMP%\night-reader-codex-out` 是共用的，收尾只刪自己那一輪（`<tag>-*`）的檔案。公司網路的 McAfee 有時擋掉 Codex 最後一次連線，`codex exec` 回非零但報告通常已經寫好；先看報告檔再決定要不要重跑。
- **Windows 上用 Python 寫檔**要給 `newline='\n'`，不然會寫成 CRLF。
- **家裡這台沒有 `jq`**：查 PR 與 Actions 狀態用 `gh` 內建的 `--jq`（例如 `gh run list --json name,conclusion --jq '.[]'`）；腳本裡接 `| jq` 會靜靜地失敗，監看迴圈永遠等不到結束。
- **重新產生 `NightReaderPunct`**：思源黑體繁中版從 `https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/OTF/TraditionalChinese/NotoSansCJKtc-{Regular,Bold}.otf` 下載，fontTools 用 pip 在 repo 外的 venv 安裝；`assets/fonts/generate_punct_font.py` 產出與 repo 內字型只差 `head` 的時間戳。

## 書源

- **Legado 原始碼**：對照 Legado 的做法時讀 `C:\Users\benny\Desktop\Folder\projects\legado`（使用者的 fork）；GitHub 上的 `gedoor/legado` 已經清空。
- **用真的網站校驗書源**：`test/live/`，用法寫在檔頭。源倉庫（yckceo.com）的書源可以照清單頁收集 id，再從 `https://www.yckceo.com/yuedu/shuyuan/json/id/<id>.json` 下載。
