# 自動巡檢

給 ChatGPT 排程任務讀的規則：每次照排程讀這個 repo 的一個區塊，找出真的會出錯的地方，開成 GitHub issue。排程本身只寫「巡哪個區塊」，其餘都照這份。

- Repo：<https://github.com/bennytsai1234/Night-Reader>，公開，預設分支 `beta`。
- 讀檔：有 GitHub 連接器就用它；沒有就讀 `https://raw.githubusercontent.com/bennytsai1234/Night-Reader/beta/<路徑>`，目錄看 `https://github.com/bennytsai1234/Night-Reader/tree/beta/<路徑>`。
- 這是使用者自己讀小說用的 Android App（Flutter／Dart）。要找的是讀者會碰到的錯，不是讓程式更漂亮。

## 開工前先讀

1. `AGENTS.md` 的「維護範圍」，`CODING_STANDARDS.md` 全文。
2. `DESIGN.md` 的「設計原則」「否決過的方向」，`docs/adr/README.md` 的索引；跟這次區塊有關的 ADR 打開讀。
3. `HANDOFF.md`：裡面寫的是已知、進行中或刻意先不做的事，不再報。
4. 記下 `beta` 目前最新提交的 SHA（<https://github.com/bennytsai1234/Night-Reader/commits/beta> 第一筆），證據連結都釘在這個 SHA。

## 區塊

排程會指定一個區塊。區塊分成幾個子區塊的，用今天的 ISO 週數除以子區塊數取餘數，挑那一個（從 0 數），讓每週輪到不同的地方。

| 區塊 | 子區塊 | 看什麼 |
|---|---|---|
| 改動 | 不分 | `beta` 過去 7 天的提交，逐個看 diff（只改 `.md` 與 `docs/` 的跳過）：漏改的呼叫端、改了一處而同一原因的其他處沒改、註解或文件與新行為不符、改到 App 內容卻沒寫 `CHANGELOG.md` 的 `## 未發布`、改 Drift 表卻沒提高 `schemaVersion` |
| 書源 | 0 `lib/core/engine/js/`、`third_party/flutter_js/`<br>1 `lib/core/engine/parsers/`、`analyze_rule/`、`rule_analyzer/`、`analyze_url.dart`、`explore_url_parser.dart`<br>2 `lib/core/engine/web_book/`、`source_isolate/`、`lib/core/network/`<br>3 `lib/core/services/` 裡的 `book_source_service`、`check_source_service`、`source_check_isolate`、`source_switch_service`，與 `lib/features/source_manager/`、`search/`、`explore/` | 書源規則（Legado 3.0 格式）解析錯、例外沒接住讓整批失敗、isolate 間傳了送不過去的東西、規則 JS 拿到還沒完成的 `Future`；對照 ADR 0013、0028、0033、0034 與 `CODING_STANDARDS.md`「網路與書源」「背景執行」 |
| 閱讀器 | 0 `lib/features/reader_v2/hybrid/`<br>1 `reader_v2/features/`<br>2 `reader_v2/screen/`、`viewport/`<br>3 `reader_v2/chapter/`、`session/`、`layout/`、`use_cases/`，與 `lib/core/services/chapter_content_preparation_pipeline.dart` | 分頁與排版算錯、閱讀進度存錯或還原到錯的位置、排版樣式改了快取沒失效（layout signature）、章節邊界與空章節；對照 ADR 0006、0007、0016、0019、0026 |
| 資料 | 0 `lib/core/database/`（不看 `*.g.dart`）、`storage/`、`models/`<br>1 `lib/core/services/download/`、`download_service.dart`、`cache_manager.dart`、`lib/features/cache_manager/`<br>2 備份、還原、書架匯入匯出、本地書（`restore_service`、`bookshelf_exchange_service`、`local_book_service`、`lib/core/local_book/`）、`update_service`、`tts_service`<br>3 `lib/main.dart`、`lib/app_providers.dart`、`lib/core/startup/`、`di/`、`config/` | 資料遺失或寫壞、migration 漏寫、SQLite／SharedPreferences／私有檔案三處不同步、下載排程卡住或重複、背景 isolate 用了主 isolate 才有的東西；對照 ADR 0008、0032 |
| 介面 | 0 `lib/shared/widgets/` 裡的 `skeleton*`、`snapshot_sweep`、`launch_entrance`<br>1 `lib/shared/widgets/` 其餘、`lib/shared/navigation/`、`theme/`<br>2 `lib/features/bookshelf/`、`book_detail/`、`welcome/`<br>3 `lib/features/settings/`、`about/`、`association/`、`replace_rule/` | `dispose` 漏了（控制器、監聽、計時器）、非同步回來時頁面已關還在 `setState`、動畫最後一幀和靜止畫面不同、玻璃包在淡入淡出裡、畫面和 `DESIGN.md` 規格不符；對照 ADR 0018、0020、0022、0029 與 `CODING_STANDARDS.md`「動畫」 |
| 文件 | 不分 | `README.md`、`website/index.html`、`CHANGELOG.md` 的 `## 未發布` 和程式實際行為不符；`DESIGN.md` 寫的規格程式裡已經不是那樣；ADR 索引漏列；`.github/workflows/`、`.githooks/`、`tool/` 的腳本錯誤或彼此不一致（例如兩個 workflow 的 Flutter 版本） |

## 算問題的

能從觸發點沿呼叫路徑走到出錯的那一行，說得出讀者會看到什麼（閃退、資料不見、進度跳錯、畫面錯、功能沒反應、文件說的和 App 做的不一樣）。

## 不報的

- 已經在 issue（開著或關掉的都算，含標了 `wontfix` 的）或 `HANDOFF.md` 提過的。開之前到 <https://github.com/bennytsai1234/Night-Reader/issues?q=is%3Aissue> 用檔名與關鍵字搜過。
- 和 ADR 或 `DESIGN.md`「否決過的方向」衝突的建議。若認為某份 ADR 本身判斷錯，最多開一個，標 `question`，寫清楚理由。
- 全新的功能線、命名與風格偏好、lint 與格式（CI 已跑 `flutter analyze`）、對比度工具的意見。
- 要使用者拿手機或模擬器去試才能確認的。
- 說「可能有效能問題」卻指不出哪一段在主執行緒做了多少事的。
- 只說「缺測試」。
- `*.g.dart`、`build/`，以及 `third_party/` 裡上游原本的程式（各套件 `PATCHES.md` 記的修補可以看）。

只走到一半、沒把握的，不開 issue，寫在最後的回覆裡。

## 開 issue

每次最多開：「改動」3 個、其他區塊 2 個。一個都沒找到就不開，這是正常結果。

- 標題：繁體中文，`<區塊>：<一句話說讀者會碰到什麼>`。
- 標籤：`auto-audit`、`needs-triage`，再加 `bug`、`enhancement`、`documentation`、`question` 其中一個。
- 用詞照 `GLOSSARY.md`（例如「書源」「骨架」「掉幀」「幀」），不寫沒解釋的代號。
- 內文：

```markdown
## 會發生什麼
讀者在什麼情況下會碰到什麼，一兩句。

## 為什麼
從觸發點走到出錯的那一行，每一步附釘在 SHA 的連結：
https://github.com/bennytsai1234/Night-Reader/blob/<SHA>/<路徑>#L<起>-L<迄>
關鍵幾行直接貼出來。

## 怎麼確認
可以寫成的測試：放在 `test/` 哪裡、準備什麼資料、斷言什麼。

## 修法方向
修在最初出錯的地方；同一個原因造成的其他地方一起列出。

## 相關
ADR、DESIGN.md 段落、相關 issue。

---
自動巡檢・<區塊>／<子區塊>・讀的是 <SHA>・讀程式推理，沒有執行
```

沒有能建立 issue 的工具時，每個問題給一條預填好的連結讓使用者點開送出：`https://github.com/bennytsai1234/Night-Reader/issues/new?title=<網址編碼>&labels=auto-audit,needs-triage,bug&body=<網址編碼>`。

## 最後的回覆

繁體中文，三段：開了哪些 issue（連結＋一句話）、沒把握所以沒開的、這次讀了哪些檔。
