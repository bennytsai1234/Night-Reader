# 自動巡檢

給 ChatGPT 排程任務讀的規則：每天讀這個 repo 的一部分，找出真的會出錯的地方，寫成一份報告開成一個 GitHub issue。有兩個排程，排程本身只寫「改動」或「舊程式」，其餘都照這份。

- Repo：<https://github.com/bennytsai1234/Night-Reader>，公開，預設分支 `beta`。
- 讀檔：有 GitHub 連接器就用它；沒有就讀 `https://raw.githubusercontent.com/bennytsai1234/Night-Reader/beta/<路徑>`，目錄看 `https://github.com/bennytsai1234/Night-Reader/tree/beta/<路徑>`。
- 這是讀網路小說用的 Android App（Flutter／Dart）。要找的是讀者會碰到的錯，不是讓程式更漂亮。

## 開工前先讀

1. `AGENTS.md` 的「維護範圍」，`CODING_STANDARDS.md` 全文。
2. `DESIGN.md` 的「設計原則」「否決過的方向」，`docs/adr/README.md` 的索引；跟這次要看的程式有關的 ADR 打開讀。
3. 記下 `beta` 目前最新提交的 SHA（<https://github.com/bennytsai1234/Night-Reader/commits/beta> 第一筆），證據連結都釘在這個 SHA。

## 改動

`beta` 過去 24 小時的提交，逐個看 diff（只改 `.md` 與 `docs/` 的只照下面「文件」那一項看）。各方面都看：漏改的呼叫端、改了一處而同一原因的其他處沒改、註解或文件與新行為不符、PR 標題（去掉前綴就是測試版說明）讀者看不懂、改 Drift 表卻沒提高 `schemaVersion`，以及改到的程式屬於哪個方面，就照下面「各方面看什麼」看。沒有提交就不開 issue，回覆「過去 24 小時沒有改動」。

## 舊程式

程式分成 20 段，用今天是一年的第幾天除以 20 取餘數，挑那一段（從 0 數），20 天輪完一圈；照「各方面看什麼」看。段的順序：書源 0–4、閱讀器 0–4、資料 0–4、介面 0–3、文件。表裡的「服務」指 `lib/core/services/` 裡的那幾個檔。

| 段 | 讀哪些 |
|---|---|
| 書源 0 | `lib/core/engine/js/`、`third_party/flutter_js/` |
| 書源 1 | `lib/core/engine/parsers/`、`analyze_rule/` 與 `analyze_rule.dart`、`rule_analyzer/` 與 `rule_analyzer.dart`、`analyze_url.dart`、`explore_url_parser.dart`、`rule_data_fields.dart` |
| 書源 2 | `lib/core/engine/web_book/`、`source_isolate/`、`lib/core/network/`；`lib/core/utils/` 的 `network_utils`、`idna`、`public_suffix`（不看資料表 `idna_mapping_table`、`public_suffix_rules`）；服務 `http_client`、`network_service`、`rate_limiter`、`encoding_detect` |
| 書源 3 | `lib/features/source_manager/`（`ai_repair/` 在書源 4）、`search/`、`explore/`、`lib/core/engine/book/`、`app_event_bus.dart`；服務 `book_source_service`、`check_source_service`、`source_check_isolate`、`source_check_diagnostics`、`source_check_js_worker_probe`、`source_debug_service`、`source_switch_service`、`source_switch_handoff`、`rule_big_data_service` |
| 書源 4 | 登入、網頁驗證與 AI 修書源：`lib/features/source_login/`、`lib/core/ai_repair/`、`lib/features/source_manager/ai_repair/`；服務 `source_login_session`、`source_interaction`、`cookie_store`、`login_data_backup`、`backstage_webview`、`webview_cloudflare_solver`、`webview_data_service` |
| 閱讀器 0 | `lib/features/reader_v2/hybrid/` |
| 閱讀器 1 | `reader_v2/features/`、`lib/features/bookmarks/`、`lib/core/engine/reader/`、`lib/core/services/system_playback/`；服務 `tts_speech_coordinator`、`sleep_timer`、`chinese_display`、`chinese_utils` |
| 閱讀器 2 | `reader_v2/screen/`、`viewport/` |
| 閱讀器 3 | `reader_v2/chapter/`、`session/`、`layout/`、`use_cases/`；`lib/core/utils/` 的 `illustration_markers`、`html_formatter`、`string_utils`；服務 `chapter_content_preparation_pipeline`、`chapter_content_kind`、`book_toc_replacer` |
| 閱讀器 4 | 漫畫與有聲書：`lib/features/comic_reader/`、`audiobook/`、`lib/core/comic/`；服務 `local_comic_service`、`comic_folder_picker`、`audio_chapter_download` |
| 資料 0 | `lib/core/database/`（不看 `*.g.dart`）、`storage/`、`models/` |
| 資料 1 | `lib/core/services/download/`、`lib/features/cache_manager/`；服務 `download_service`、`cache_manager`、`book_storage_service`、`book_chapter_files`、`reader_chapter_content_store`、`reader_chapter_content_storage`、`book_illustration_storage`、`book_cover_storage_service`、`book_update_service`、`bookshelf_state_tracker`、`books_in_use` |
| 資料 2 | 備份、還原、匯出、本地書、更新：`lib/core/local_book/`；服務 `backup_service`、`restore_service`、`bookshelf_exchange_service`、`export_book_service`、`highlight_export`、`local_book_service`、`update_service`、`update_preferences`、`app_update_installer`、`app_version`、`tts_service` |
| 資料 3 | `lib/main.dart`、`lib/app_providers.dart`、`lib/core/startup/`、`di/`、`config/`、`constant/`、`exception/`、`fonts/`、`lib/core/services/background_work/`；Android 那一半：`android/app/src/main/` 的 Kotlin 與 `AndroidManifest.xml`；`lib/core/utils/` 的 `encoder_utils`、`lru_map`；服務 `crash_handler`、`crash_trail`、`process_exits`、`app_log_service`、`app_permission_service`、`app_file_selection_service`、`event_bus`、`default_data`、`resource_service` |
| 資料 4 | 同步：`lib/core/sync/` |
| 介面 0 | `lib/shared/widgets/` 裡的 `skeleton*`、`snapshot_sweep`、`launch_entrance` |
| 介面 1 | `lib/shared/widgets/` 其餘、`lib/shared/navigation/`、`theme/`、`layout/` |
| 介面 2 | `lib/features/bookshelf/`、`book_detail/`、`welcome/` |
| 介面 3 | `lib/features/settings/`、`about/`、`association/`、`replace_rule/` |
| 文件 | 全部文件；另外列出 `lib/features/`、`lib/core/` 底下的資料夾與 `lib/core/services/` 的檔，表上沒有的寫進報告「沒排進分段的程式」一節 |

## 各方面看什麼

| 方面 | 看什麼 |
|---|---|
| 書源 | 書源規則（Legado 3.0 格式）解析錯、例外沒接住讓整批失敗、isolate 間傳了送不過去的東西、規則 JS 拿到還沒完成的 `Future`；對照 ADR 0013、0028、0033、0034 與 `CODING_STANDARDS.md`「網路與書源」「背景執行」 |
| 閱讀器 | 分頁與排版算錯、閱讀進度存錯或還原到錯的位置、排版樣式改了快取沒失效（layout signature）、章節邊界與空章節；對照 ADR 0006、0007、0016、0019、0026 |
| 資料 | 資料遺失或寫壞、migration 漏寫、SQLite／SharedPreferences／私有檔案三處不同步、下載排程卡住或重複、背景 isolate 用了主 isolate 才有的東西；對照 ADR 0008、0032 |
| 介面 | `dispose` 漏了（控制器、監聽、計時器）、非同步回來時頁面已關還在 `setState`、動畫最後一幀和靜止畫面不同、玻璃包在淡入淡出裡、畫面和 `DESIGN.md` 規格不符；對照 ADR 0018、0020、0022、0029、0036、0037 與 `CODING_STANDARDS.md`「動畫」 |
| 文件 | `README.md`、`website/index.html` 和程式實際行為不符；`docs/design/` 寫的規格程式裡已經不是那樣；ADR 索引漏列；給 agent 看的文件（`AGENTS.md`、`DESIGN.md`、`docs/design/`、ADR、`docs/agents/`）寫了日期、來回的經過、程式裡查得到的類別名稱或數值，或同一件事寫在好幾處（照 `writing-for-agents` 的「重複」「沉積」）；`.github/workflows/`、`.githooks/`、`tool/` 的腳本錯誤或彼此不一致（例如兩個 workflow 的 Flutter 版本） |

## 算問題的

能從觸發點沿呼叫路徑走到出錯的那一行，說得出讀者會看到什麼（閃退、資料不見、進度跳錯、畫面錯、功能沒反應、文件說的和 App 做的不一樣）。

## 不報的

- 已經在 issue（開著或關掉的都算，含標了 `wontfix` 的、以前的巡檢報告）、`DESIGN.md`「否決過的方向」或 ADR 提過的。開之前到 <https://github.com/bennytsai1234/Night-Reader/issues?q=is%3Aissue> 用檔名與關鍵字搜過。
- 和 ADR 或 `DESIGN.md`「否決過的方向」衝突的建議。若認為某份 ADR 本身判斷錯，最多開一個，標 `question`，寫清楚理由。
- 全新的功能線、命名與風格偏好、lint 與格式（CI 已跑 `flutter analyze`）、對比度工具的意見。
- 要使用者拿手機或模擬器去試才能確認的。
- 說「可能有效能問題」卻指不出哪一段在主執行緒做了多少事的。
- 只說「缺測試」。
- `*.g.dart`、`build/`，以及 `third_party/` 裡上游原本的程式（各套件 `PATCHES.md` 記的修補可以看）。

只走到一半、沒把握的，不開 issue，寫在最後的回覆裡。

## 開 issue

每次一份報告、開一個 issue：「改動」最多 5 個問題，「舊程式」最多 3 個。一個都沒找到就不開，這是正常結果。

- 標題：`自動巡檢・<改動或舊程式的段>・YYYY-MM-DD`。
- 標籤：`auto-audit`、`needs-triage`。
- 用詞照 `GLOSSARY.md`（例如「書源」「骨架」「掉幀」「幀」），繁體中文，不寫沒解釋的代號。
- 內文每個問題一節：

```markdown
## 1. <一句話說讀者會碰到什麼>（bug／enhancement／documentation／question）

**會發生什麼**：讀者在什麼情況下會碰到什麼，一兩句。

**為什麼**：從觸發點走到出錯的那一行，每一步附釘在 SHA 的連結：
https://github.com/bennytsai1234/Night-Reader/blob/<SHA>/<路徑>#L<起>-L<迄>
關鍵幾行直接貼出來。

**怎麼確認**：可以寫成的測試：放在 `test/` 哪裡、準備什麼資料、斷言什麼。

**修法方向**：修在最初出錯的地方；同一個原因造成的其他地方一起列出。

**相關**：ADR、DESIGN.md 段落、相關 issue。
```

最後一行：`自動巡檢・<改動或舊程式的段>・讀的是 <SHA>・讀程式推理，沒有執行`。

沒有能建立 issue 的工具時，給一條預填好的連結讓使用者點開送出：`https://github.com/bennytsai1234/Night-Reader/issues/new?title=<網址編碼>&labels=auto-audit,needs-triage&body=<網址編碼>`。

## 最後的回覆

繁體中文，三段：報告 issue 的連結與找到幾個問題、沒把握所以沒寫進報告的、這次讀了哪些檔。
