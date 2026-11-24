# 全面檢查：文件

這份是全面檢查「文件」那一段的清單：給讀者看的說明（`README.md`、`website/index.html`、`PRIVACY.md`）、`docs/design/` 的規格、ADR 索引、給 agent 看的文件，以及 `.github/workflows/`、`.githooks/`、`tool/` 的腳本，和程式實際做的不一樣的地方。只讀、只列，不修。

- 讀的是 `origin/beta`：README 到 `docs/design/` 是 `fff55f9c`，ADR 索引以後的四類是 `de5f8e51`。
- 標準照 `docs/agents/auto-audit.md` 的「算問題的」「不報的」；每一筆都對過程式，兩邊附 `檔案:行號`，並用 `gh issue list --state all --search` 查過沒報過。GPT 這一波開的 #525（文件）沒有拿來比對，照交辦不處理。

## 進度

| 類 | 讀了哪些 | 找到幾筆 |
|---|---|---|
| README 與網站 | `README.md`、`website/index.html` | 2 |
| 隱私說明 | `PRIVACY.md`、`lib/features/about/privacy_pages.dart`（App 的「隱私說明」與「權限」） | 2 |
| `docs/design/appearance.md` | 全文；抽查配色、層次、遮罩、陰影、間距、平板的數字 | 0 |
| `docs/design/audiobook.md` | 全文；抽查選單、列高、播放模式、通知按鈕、圓鈕時長 | 0 |
| `docs/design/comics.md` | 全文；抽查紙色、縮放、換章分隔、預載、選單 | 0 |
| `docs/design/components.md` | 全文；抽查玻璃強度、分頁列、提示框、開關、快速捲軸、空書架 | 0 |
| `docs/design/loading.md` | 全文；抽查骨架深淺、呼吸、換場、記下的筆數 | 0 |
| `docs/design/motion.md` | 全文；抽查時長、曲線、拖曳返回 | 0 |
| `docs/design/reader.md` | 全文；抽查預設值、選單順序、高亮、定時；畫面字全部比對 | 1 |
| `docs/design/screens.md` | 全文；書架、關於夜讀、背景工作逐條對；其他段只比對畫面字 | 3 |
| `docs/design/website.md` | 全文；功能數 | 0 |
| ADR 索引 | `docs/adr/README.md` 與 `docs/adr/` 每個檔逐一比對；所有文件、程式、腳本裡寫到的 ADR 號碼都對過有這一份；被取代的幾份開頭有沒有標 | 1 |
| 給 agent 看的文件 | `AGENTS.md`、`DESIGN.md`、`CODING_STANDARDS.md`、`docs/agents/` 十七份全文，寫到的路徑、檔案、指令、函式與類別逐一對過還在，數值與行為只抽查（候選圖的預設風格與玻璃、崩潰日誌最多 50 份、「我的」九個入口、推送前檢查、PR 標題長度）；ADR 本文、`GLOSSARY.md`、`docs/state-machines.md` 只機械比對（寫到的路徑與類別、函式名稱在不在程式裡），沒逐條對行為；`docs/design/` 的日期與經過照 `DESIGN.md` 自己的規則評 | 6 |
| CI 與腳本 | 全文：`.github/workflows/` 四份、`.githooks/` 三支、`tool/changelog.sh`、`flutter_test.sh`、`skill_refs.sh`；`frame_budget_compare.sh` 只讀檔頭與參數；`tool/` 其餘只對過每一支都有文件或程式指到、文件寫的用法與參數；四份 workflow 的 Flutter 版本一致（3.47.2）；跑過 `changelog_test.sh`、`frame_budget_compare_test.sh`、`skill_refs.sh`，都通過 | 0（兩處檢查的缺口併在第 8、13 筆） |
| 沒排進分段的程式 | `lib/features/` 17 個、`lib/core/` 31 個資料夾，`lib/core/source/` 9、`storage/` 15、`utils/` 12 個檔，逐一對 `docs/agents/auto-audit.md` 的分段表；表上寫的檔名反過來也都對過還在 | 交辦範圍內 0；範圍外 3 處 |
| 補讀：`lib/shared/shelf_look.dart` | 全文；所有呼叫的地方（開 App 讀回、書架寫入與重讀、同步套用、換源搬位置、預設封面取位置） | 0 |
| 補讀：iOS 的 Swift 程式 | `ios/Runner/AppDelegate.swift`、`SceneDelegate.swift` 全文；每個平台通道對 Dart 呼叫的方法名稱，iOS 沒實作的通道與方法 Dart 端有沒有擋（App 內更新、背景工作、選漫畫資料夾、啟動畫面、系統結束紀錄、音量鍵、亮度、挖孔、狀態列）；`Info.plist` 的 Face ID 說明 | 0 |
| 補讀：`flutter_tts`、`file_picker`、`xpath_selector` 的修補 | 三份 `PATCHES.md` 全文；從 pub.dev 下載三個上游封存檔（雜湊和 `PATCHES.md` 寫的一樣），整份比對改過哪些檔、都有記；`xpath_selector` 的存在條件、相對路徑、聯集切分三處讀程式；`flutter_tts` 的 Android 外掛讀了連線、念、重連與回覆的部分 | 1 |

## 問題

### README 與網站

#### 1. README 說「用檔案開書」只有 iOS 沒有，其實 Android 也沒有（已修）

- **文件寫的**：「iOS 版沒有 App 內更新、分享進 App 與用檔案開書，也沒在 iPhone 上試過。」（`README.md:31`）讀起來 Android 有這三項。
- **程式做的**：Android 只接 `legado://`、`yuedu://` 連結的「開啟」，與 JSON、文字、EPUB 的「分享」；沒有接檔案的「開啟」（從檔案管理員點書檔、選「用夜讀開啟」不會出現夜讀）。`android/app/src/main/AndroidManifest.xml:51-66`：

  ```xml
  <action android:name="android.intent.action.VIEW"/>
  ...
  <data android:scheme="legado"/>
  <data android:scheme="yuedu"/>
  ...
  <action android:name="android.intent.action.SEND"/>
  <action android:name="android.intent.action.SEND_MULTIPLE"/>
  ```

  分享進來的檔案由 `lib/features/association/handlers/file_association_handler.dart:18-47` 處理，只有分享這條路。
- **該改哪一邊**：改文件，拿掉「與用檔案開書」，或寫成 Android 也只能分享進 App。

#### 2. README 說漫畫的圖片資料夾在「加入本地書籍」匯入，其實要用「加入本地漫畫」（已修）

- **文件寫的**：「手邊的 TXT、EPUB 與漫畫（CBZ、ZIP、圖片資料夾）不用書源，在書架選「加入本地書籍」。」（`README.md:39`）
- **程式做的**：書架「加入」選單有兩項，「加入本地書籍」選單一個檔，只收 TXT、EPUB、CBZ、ZIP（`lib/core/platform/app_file_selection_service.dart:22-24`：`allowedExtensions: ['txt', 'epub', 'cbz', 'zip']`）；圖片資料夾、一個作品好幾話的資料夾要按「加入本地漫畫」選資料夾（`lib/features/bookshelf/bookshelf_page.dart:417-424` 兩個選單項；`:1220-1222`「加入本地漫畫（ADR 0052）：選一個作品資料夾」）。照 README 去「加入本地書籍」找不到選資料夾的地方。
- **該改哪一邊**：改文件，寫成「TXT、EPUB 與單一個 CBZ 在「加入本地書籍」，漫畫資料夾在「加入本地漫畫」」。

### 隱私說明

#### 3. 隱私說明的「同步」列了會同步哪些資料，漏了 AI 找書「不想看的」清單與書架、搜尋的設定

- **文件寫的**：「書架上的書（…）、閱讀進度、書籤（…）、標註（…）、書源、替換規則、閱讀與外觀設定、閱讀統計、書源的登入資料、過去的找書，以及 AI 服務設定（…）會存到你自己的同步空間」（`PRIVACY.md:43`；App 內同一段在 `lib/features/about/privacy_pages.dart:53`）。這一段是逐項列，讀者會以為沒列的不會離開手機。
- **程式做的**：同步的設定還有 AI 找書每次都送給 AI 的「不想看的」清單，與書架、搜尋的設定（含搜尋屏蔽的字）。`lib/core/sync/settings_sync.dart:39-48`、`:97-100`：

  ```dart
  // 書架與搜尋
  'bookshelf_is_grid',
  ...
  'precision_search',
  'search_blocked_words',
  ...
  // AI 找書「不想看的」清單：使用者的口味，兩台該一樣
  AiFindAvoid.key,
  ```

- **該改哪一邊**：改文件，兩處（`PRIVACY.md` 與 App 的「隱私說明」）一起補上「AI 找書不想看的清單、書架與搜尋設定」。

#### 4. App 的「權限」說哪些工作會用通知，漏了 AI 建立書源與自動換源

- **文件寫的**：「朗讀的播放控制，與修書源、校驗書源、AI 找書、放到背景的搜尋的進度會使用通知權限；…在 Android 上，它們跑的時候會開前景服務」（`lib/features/about/privacy_pages.dart:130`）。
- **程式做的**：AI 建立書源與自動換源也是背景工作，跑的時候一樣在通知欄顯示進度、開前景服務。AI 建立書源按下「開始建立」就建一件背景工作（`lib/features/source_manager/ai_repair/ai_create_source_page.dart:162-163`：`final run = SingleRepairRun(session); if (!_runs.adopt(run)) …`，`SingleRepairRun` 是 `RepairRun`，`RepairRun implements BackgroundJob`，`lib/features/source_manager/ai_repair/repair_runs.dart:103`）；自動換源是 `class AutoSourceSwitch implements BackgroundJob`，「跑的時候佔背景工作的位置、只有『結束』」（`lib/core/source_switch/auto_source_switch.dart:24-28`）。
- **該改哪一邊**：改文件，補上 AI 建立書源與自動換源。

### `docs/design/`

#### 5. 規格與用語表寫「關於夜讀 → 系統工具」，畫面上沒有「系統工具」這幾個字（已修）

- **文件寫的**：「開 App 時照同樣方式檢查一次（「關於夜讀 → 系統工具 → 啟動時檢查書架更新」可關）」（`docs/design/screens.md:10`）；`GLOSSARY.md:24`「更新紀錄」也寫「「關於夜讀 → 系統工具」裡列出各版更新說明的頁面」。寫成路徑，讀的人會去找一個叫「系統工具」的分段。
- **程式做的**：「關於夜讀」的幾組卡片都沒有段落標題（`lib/features/about/about_page.dart:304`、`:333` 的 `GroupedSection(children: [...])` 都沒給 `header`），照 ADR 0076 卡片外不放小字，只有隱私說明、權限這種說明文件有段落標題（`docs/design/components.md:67`）。「系統工具」只是 `screens.md:143` 描述分組時用的名字。
- **該改哪一邊**：改文件，`screens.md:10` 與 `GLOSSARY.md:24` 改成「關於夜讀」裡的「啟動時檢查書架更新」「更新紀錄」，不寫成有「系統工具」這一層。

#### 6. 畫面規格的「背景工作」只列四種，漏了 AI 建立書源與自動換源（已修）

- **文件寫的**：「修書源（單一、一批）、從書源管理按的校驗（…）、AI 找書與按了「放到背景」的搜尋（ADR 0070）離開頁面、離開夜讀、關螢幕都照跑。」（`docs/design/screens.md:129`）；「一次一件」列哪些入口會灰掉（`:131`）、「通知」逐一寫每一種的標題與內文（`:133-137`），最後「右邊兩顆「暫停」「結束」」（`:138`）。
- **程式做的**：
  - AI 建立書源也是背景工作，通知標題是「AI 建立書源 · 名稱」：`lib/features/source_manager/ai_repair/repair_runs.dart:663-669`

    ```dart
    title:
        '${creating ? 'AI 建立書源' : 'AI 修復'} · '
        '${_session.job.original.bookSourceName}',
    text: _session.job.steps.lastOrNull?.line ?? '準備中…',
    pausable: true,
    ```

  - 自動換源也是背景工作，通知標題「自動換源」、內文「正在替《書名》找書源」、有進度條、只有「結束」沒有「暫停」：`lib/core/source_switch/auto_source_switch.dart:24-28`（「跑的時候佔背景工作的位置、只有『結束』」）、`:48`（`static const String title = '自動換源';`）、`:264-268`（`BackgroundWorkStatus(title: title, text: … '正在替《${book.name}》找書源', progress: …)`，沒給 `pausable`，預設 `false`，`lib/core/background_work/background_work.dart:27`）。
- **同一個原因**：`GLOSSARY.md`「背景工作」也只列「修書源、校驗書源、AI 找書、按了「放到背景」的搜尋」，並寫「使用者按了才開始」；自動換源是刪書源時夜讀自己開始的。
- **該改哪一邊**：改文件，`screens.md`「背景工作」與 `GLOSSARY.md`「背景工作」補上這兩種：一次一件的入口、通知的標題與內文，以及自動換源只有「結束」。AI 建立書源一節（`:90`）已寫了灰掉的規則，這裡只差總表。

#### 7. 規格裡的幾句畫面字，程式改字或拿掉後沒跟著改（已修）

同一個原因：#382（畫面說明文字更精簡）、#369、#487（分組標題拿掉）改了畫面字，規格沒跟上。

- **標註的備忘框**：`docs/design/reader.md:52` 寫備忘輸入框「提示「寫下自己的話」」；程式的框沒有提示字（`lib/features/reader/features/highlight/reader_highlight_sheet.dart:130-135`：`GroupedTextFieldRow(controller: _note, minLines: 2, maxLines: 6, …)`，沒給 `hintText`），#382 拿掉的。
- **複製給 AI 的貼上框**：`docs/design/screens.md:83` 寫提示「貼上 AI 回的書源 JSON」；程式是「書源 JSON」（`lib/features/source_manager/ai_repair/ai_repair_page.dart:426`：`hintText: '書源 JSON'`）。
- **AI 服務的測試連線**：`docs/design/screens.md:84` 寫成功時提示「連得上：模型名」；程式是「連線與工具呼叫正常：模型名」（`lib/features/source_manager/ai_repair/ai_repair_settings_page.dart:320`），#369 改的。
- **閱讀統計**：`docs/design/screens.md:147` 寫「沒聽過時一組「累積閱讀時間」」；程式沒聽過有聲書時那一組沒有名稱（`lib/features/bookmarks/reading_stats_view.dart:245-248`：`if (listened.isEmpty) GroupedSection(children: [for (final record in read) _row(context, record)])`），#487 拿掉分組標題。
- **該改哪一邊**：改文件，照程式現在的字寫。

### ADR 索引

#### 8. ADR 0079（書架「列表併成一面」做成一般選項）沒有列進索引

- **文件寫的**：索引開頭要求「新增後把它加進下面的索引」（`docs/adr/README.md:3`）；前後的 0074、0077、0078 都列在「正文排版」那張表（`docs/adr/README.md:51`、`:55`、`:58`），就是沒有 0079。
- **程式做的**：`docs/adr/0079-shelf-merged-list-is-an-option.md` 存在，#512 加的；書架的「列表併成一面」照它做（`lib/shared/shelf_look.dart:1`「「整理」選單的「列表併成一面」（ADR 0079）」），`docs/design/screens.md:8` 也引用它。照 `auto-audit.md` 開工前只讀索引的 agent 看不到這一份。
- **同一個原因**：CI 的「Check ADR numbers are unique」只查檔名格式與編號重複（`.github/workflows/ci.yml:215-230`），不查每一份都在索引裡，所以漏了也不會擋。
- **該改哪一邊**：改文件，索引補一行 0079（放「介面與動畫」）。要不要讓 CI 一起查索引由使用者定。

### 給 agent 看的文件

#### 9. 寫碼規範說網站「隨正式版部署」，其實推上 `beta` 就部署（已修）

- **文件寫的**：「網站隨正式版部署，#92 拿掉朗讀音量後網站寫錯到下一個正式版前才發現。」（`CODING_STANDARDS.md:44`）
- **程式做的**：`website-deploy.yml` 在 `website/` 推上 `beta` 時就部署（`.github/workflows/website-deploy.yml:3-6`：`push: branches: ["beta"]`、`paths: ["website/**", …]`），#309 改的；網站規格也寫「`website/` 推上 `beta` 就部署」（`docs/design/website.md:9`）。照寫碼規範讀，agent 會以為網站改了要等發正式版才上線。
- **該改哪一邊**：改文件，`CODING_STANDARDS.md:44` 拿掉「網站隨正式版部署」與 #92 的經過，只留「不符的在同一個 PR 改」。

#### 10. 發測試版的步驟指向一段已經不在的全域指示，而現在的全域指示說的正好相反（已修）

- **文件寫的**：「還在跑就在同一輪裡前景等（`gh run watch <run> --exit-status`，逾時設 10 分鐘），不放背景，原因見全域指示「指令與測試」。」（`docs/agents/release.md:9`）
- **現在的樣子**：全域指示沒有「指令與測試」這一段了；現在的「長指令」寫「等 CI……一律放背景」（`~/.claude/CLAUDE.md:27`）。前景等的規則和原因搬到 `plan` 技能的收尾合併清單：「還要等、十分鐘內跑得完的（例如等主線 CI 再發版），在同一輪前景等……T3 在背景工作結束、PR 已合併時可能自動收尾」（`~/.claude/skills/plan/references/rubric.md:87`）。照指向去找的 agent 找到的是相反的規則。
- **該改哪一邊**：改文件，`release.md:9` 的「原因見全域指示「指令與測試」」改成指向 `plan` 技能「收尾合併清單」第 6 條。

#### 11. ADR 0001 與索引說自行維護「三個 fork」，`third_party/` 其實有四個（已修）

- **文件寫的**：「自行維護 flutter_tts、flutter_js、file_picker 三個 fork」（`docs/adr/0001-maintain-third-party-plugin-forks.md:1`、`docs/adr/README.md:105`），本文的理由是上游用了 AGP 9 拿掉的 Kotlin 設定（`0001…md:3`）。
- **程式做的**：`xpath_selector` 也放在 `third_party/`、自己維護（`pubspec.yaml:53-56`：「自行維護（源自 3.0.2），見 third_party/xpath_selector/PATCHES.md」，`:131-133` 連 `xpath_selector_html_parser` 也換成這一份），#214、#217 為了 XPath 照 Legado 改的，理由和 ADR 0001 的不同；`docs/` 裡沒有任何一份寫到它。`a21f85a4`（「third_party 的 fork 是四個，不是三個」）只把 `AGENTS.md` 那句改成「各 fork」，ADR 與索引沒跟著改。
- **同一個原因**：巡檢的分段表只排了 `third_party/flutter_js/`（`docs/agents/auto-audit.md:25`），另外三個的修補沒有段會看，見「沒排進分段的程式」。
- **該改哪一邊**：改文件，ADR 0001 與索引補上 `xpath_selector` 與它的理由；要併進 0001 還是另寫一份由使用者定。

#### 12. ADR 0028 寫網址選項 `webView` 經 `HeadlessWebViewService.delegate` 交給主 isolate，這個類別已經拿掉（已修）

- **文件寫的**：「網址選項 `webView` 與 `java.webView` 由書源 isolate 請主 isolate 渲染（`HeadlessWebViewService.delegate`、`BackstageWebView.delegate`）。」（`docs/adr/0028-source-work-in-a-source-isolate.md:13`）
- **程式做的**：`headless_webview_service.dart` 在 #175 刪掉了，網址選項 `webView` 改走 `BackstageWebView`（`lib/core/engine/analyze_url.dart:692`），書源 isolate 只設 `BackstageWebView.delegate`（`lib/core/engine/source_isolate/source_isolate.dart:952`、`lib/core/network/backstage_webview.dart:30`）。照 ADR 找程式的 agent 找不到前一個。
- **該改哪一邊**：改文件，拿掉 `HeadlessWebViewService.delegate`。

#### 13. 幾份 agent 文件寫給沒有安裝的技能用

- **文件寫的**：`docs/agents/domain.md:10`「`/domain-modeling` 技能（經由 `/grill-with-docs` 與 `/improve-codebase-architecture` 觸發）」；`docs/agents/issue-tracker.md:21`「`/triage` 會讀這個旗標」、`:39-48` 一整段「Wayfinding 操作」「給 `/wayfinder` 用」；`docs/agents/triage-labels.md:3`「技能用五個標準的 triage 角色溝通」；`AGENTS.md:60-72`「Agent skills」三小節指向這三份。
- **現在的樣子**：`grill-with-docs`、`improve-codebase-architecture`、`triage`、`wayfinder` 都不在 `~/.claude/skills/`、專案的 `.claude/skills/`，也不在技能正本 `~/skills/`，只在 `~/skills/vendor/mattpocock-skills/` 當參考。`domain-modeling` 在。五個 triage 標籤本身還在 GitHub 上、巡檢報告也用 `needs-triage`。
- **同一個原因**：推送前的 `tool/skill_refs.sh` 只認「`` `名稱` 技能 ``」這種寫法（`tool/skill_refs.sh:13`），`/名稱` 的寫法查不到，所以沒擋下來。
- **該改哪一邊**：改文件，拿掉指向沒裝的技能的句子與「Wayfinding 操作」一段；`triage-labels.md` 與 `AGENTS.md`「Agent skills」要留多少由使用者定。

#### 14. `docs/design/` 寫了選定的日期與來回的經過，違反 `DESIGN.md` 自己「規格裡不寫經過」（已修）

- **文件寫的規則**：「理由寫在 ADR，規格裡不寫經過。」（`DESIGN.md:5`）
- **實際寫的**：只算日期就有 `docs/design/screens.md` 26 處、`components.md` 13、`appearance.md` 4、`website.md` 3、`reader.md` 2、`audiobook.md` 2；多半跟著「使用者在候選圖上選了甲，否決了……」的經過。例：
  - `docs/design/components.md:22`「2026-11-13 使用者在候選圖上選了「前幾行照常、最後一行可拖」，沒選「整段排成一行拖」……」
  - `docs/design/components.md:28`「使用者 2026-11-10 在動畫儀表板上選；否決過：選中換實心、一律實心。」
  - `DESIGN.md:42`「改分組卡片的圓角與進度線」一條裡「2026-11-19 使用者重開書架……書卡的圓角試過 0、4、26……分頁列置中 2026-11-20 改成外觀設定的一種」。
- **同一類**：`DESIGN.md` 本身 5 處（上面 `:42` 那條，與 `:16`、`:58`、`:59`）、`docs/agents/` 18 處（`phone.md` 5、`environment.md` 4、`ai-repair-runs.md` 3 等）、`CODING_STANDARDS.md` 2 處，多是「某天踩過」的理由；這幾份不在 `DESIGN.md:5` 管的範圍，照 `auto-audit.md` 的「文件」那一項算沉積。`AGENTS.md` 要把使用者選的「寫進 `docs/design/`」，寫的是選了什麼，不衝突。
- **該改哪一邊**：改文件，`docs/design/` 只留選了什麼；否決過的寫進 `DESIGN.md`「否決過的方向」或 ADR，不帶日期。這筆量大，要不要現在整理由使用者定。

## 沒排進分段的程式

交辦要列的三類（`lib/features/`、`lib/core/` 底下的資料夾，`lib/core/source/`、`storage/`、`utils/` 裡的檔）都在 `docs/agents/auto-audit.md` 的分段表上，沒有漏的。

交辦範圍外、順手看到也沒有段會讀的：

- `lib/shared/shelf_look.dart`：書架「列表併成一面」與書架順序的設定（#512 加的）。介面 1 只排了 `lib/shared/` 底下的 `widgets/`、`navigation/`、`theme/`、`layout/` 四個資料夾（`auto-audit.md:41`），這個檔在 `lib/shared/` 最上層。
- `ios/Runner/AppDelegate.swift`（280 行，斷詞、網頁、電量、閱讀器裝置、系統列的平台通道）與 `SceneDelegate.swift`：資料 3 只排了 Android 那一半（`auto-audit.md:38`）。
- `third_party/flutter_tts/`、`file_picker/`、`xpath_selector/` 的修補：只有 `flutter_js` 排進書源 0（`auto-audit.md:25`）；「不報的」說 `PATCHES.md` 記的修補可以看，但沒有段會看到（見第 11 筆）。

## 補讀：沒排進分段的三處

照 `docs/agents/auto-audit.md` 的標準讀，讀的是 `origin/beta` 的 `2b98b434`。書架列表的設定檔與 iOS 程式沒有找到問題；Dart 端呼叫 iOS 沒實作的方法時都有接住或先擋掉平台。

#### 15. `flutter_tts` 與 `file_picker` 的修補紀錄，開頭寫的版本與「沒改」的說法過時了（已修）

- **文件寫的**：`third_party/file_picker/PATCHES.md:9`「Local version: `11.0.3+nightreader.1`」；`third_party/flutter_tts/PATCHES.md:23`「Dart and native runtime sources are unchanged from the published archive.」
- **程式做的**：`file_picker` 已經是 `11.0.3+nightreader.3`（`third_party/file_picker/pubspec.yaml:3`，同一份 `PATCHES.md` 後面也記了 `nightreader.2`、`.3`）。`flutter_tts` 的 `nightreader.3` 改了 `getEngines` 的回傳（`third_party/flutter_tts/PATCHES.md:47`；`lib/flutter_tts.dart:496-503`），`nightreader.5` 重寫了 Android 外掛的執行緒與回覆（`PATCHES.md:59`；`android/src/main/kotlin/com/eyedeadevelopment/fluttertts/FlutterTtsPlugin.kt` 和上游 4.2.5 整份不同）。照開頭那句，升級或對照上游的人會以為執行的程式和上游一樣。
- **該改哪一邊**：改文件，`file_picker` 那行改成 `nightreader.3`；`flutter_tts` 那句改成只說建置設定那一段沒動到執行的程式，或直接拿掉。

## 拿不準

- **第 1 筆**的「用檔案開書」是照「從檔案管理員選用夜讀開啟」讀的；作者原意若是 App 裡選檔，這筆不成立。
- **隱私說明**只核對了同步、備份、送給 AI 的長度上限與遮掉的資料、日誌遮罩；「AI 改書源之前的那一份不進備份、不同步」（`ai_repair_backups.dart` 存在哪）、WebDAV 帳密存在哪、AI 找書只送作品名稱到維基百科、讀章節的正文不存不算閱讀時間，都還沒對程式。
- **ADR 本文與 `docs/state-machines.md` 的日期與經過**：76 份 ADR 共 342 處日期、`state-machines.md` 18 處，照 `auto-audit.md` 也算沉積；但 ADR 照它的索引就是記「考慮過什麼、否決了什麼」（`docs/adr/README.md:3`），`state-machines.md` 是每做完一個狀態機加一節的紀錄（`docs/state-machines.md:3`），沒算進第 14 筆。類別名稱也沒算：`docs/design/` 寫了不少（例如 `components.md:22` 的 `DragOverflowText`），是不是沉積和日期一樣由使用者定。
- **只改 `.gitignore` 這類檔也會發測試版**：`tool/changelog.sh` 的 `is_app_path` 把文件、網站、測試、hook、工具與三份 workflow 以外的路徑都算 App 內容（`tool/changelog.sh:32-40`），`.gitignore`、`.gitattributes`、`LICENSE`、`.metadata` 也算；上一個發布之後只改了這些時，`android-release.yml` 仍會發一版（`.github/workflows/android-release.yml:79-88`、`:202`）。實際有沒有碰過、要不要排除沒查。
- **第 13 筆**：`a21f85a4` 整理「指向不存在的技能」時改了 `git-flow`、`codex-review` 這幾個，留著 `/triage`、`/wayfinder`、`/grill-with-docs`；這三份是 mattpocock 技能的設定範本產生的，可能是刻意留著等之後裝，若是就不算問題。
- **沒有任何能用的朗讀引擎時，按朗讀可能一直等、外掛一直重連**：照程式推，`speak` 碰到連線不能用時重建引擎、把這句排回去（`third_party/flutter_tts/android/src/main/kotlin/com/eyedeadevelopment/fluttertts/FlutterTtsPlugin.kt:785-789`、`:414-417`）；引擎初始化失敗時 `ttsStatus` 照樣設成失敗碼，接著重跑排著的呼叫（`:320-356`），`speak` 又看到連線不能用、再重建，沒有上限，Dart 的 `speak` 一直收不到回覆（`lib/core/playback/tts_service.dart:297` 沒有逾時）。上游 4.2.5 也是同一個重連條件。沒把握的一步是 Android 的 `TextToSpeech` 連不上任何引擎時 `mServiceConnection` 是不是一直是 null（照 AOSP 原始碼推的，沒在手機上看過）；`PATCHES.md` 的 `nightreader.5` 說「失敗會回覆、不會卡住」，這條路不在裡面。
- **這台 Linux 電腦**：`docs/agents/environment.md`、`emulator.md`、`phone.md` 只寫了家裡與公司兩台 Windows（Legado 在 `C:\…`、模擬器在 `C:/Android/Sdk`、Git Bash、「家裡這台沒有 `jq`」）；這台有 `jq`、沒有模擬器、Legado 在 `~/.cache/audit-legado/legado`。是不是會長期用的電腦不知道，沒列成問題。`issue-tracker.md:8` 要用 `jq` 過濾留言，和 `environment.md:24`「家裡這台沒有 `jq`」也對不上。
