# 全面檢查：文件

這份是全面檢查「文件」那一段的清單：給讀者看的說明（`README.md`、`website/index.html`、`PRIVACY.md`）、`docs/design/` 的規格、ADR 索引、給 agent 看的文件，以及 `.github/workflows/`、`.githooks/`、`tool/` 的腳本，和程式實際做的不一樣的地方。只讀、只列，不修。

- 讀的是 `origin/beta` 的 `fff55f9c`。
- 標準照 `docs/agents/auto-audit.md` 的「算問題的」「不報的」；每一筆都對過程式，兩邊附 `檔案:行號`，並用 `gh issue list --state all --search` 查過沒報過。GPT 這一波開的 #525（文件）沒有拿來比對，照交辦不處理。
- **還沒讀完**：做到一半交接，進度表標「還沒讀」的類別要接著讀，見分支 `docs/audit-docs` 的 `HANDOFF.md`。

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
| ADR 索引 | 還沒讀 | — |
| 給 agent 看的文件 | 還沒讀（`docs/design/` 的日期與經過也還沒評） | — |
| CI 與腳本 | 還沒讀 | — |
| 沒排進分段的程式 | 還沒列 | — |

## 問題

### README 與網站

#### 1. README 說「用檔案開書」只有 iOS 沒有，其實 Android 也沒有

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

#### 2. README 說漫畫的圖片資料夾在「加入本地書籍」匯入，其實要用「加入本地漫畫」

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

#### 5. 規格與用語表寫「關於夜讀 → 系統工具」，畫面上沒有「系統工具」這幾個字

- **文件寫的**：「開 App 時照同樣方式檢查一次（「關於夜讀 → 系統工具 → 啟動時檢查書架更新」可關）」（`docs/design/screens.md:10`）；`GLOSSARY.md:24`「更新紀錄」也寫「「關於夜讀 → 系統工具」裡列出各版更新說明的頁面」。寫成路徑，讀的人會去找一個叫「系統工具」的分段。
- **程式做的**：「關於夜讀」的幾組卡片都沒有段落標題（`lib/features/about/about_page.dart:304`、`:333` 的 `GroupedSection(children: [...])` 都沒給 `header`），照 ADR 0076 卡片外不放小字，只有隱私說明、權限這種說明文件有段落標題（`docs/design/components.md:67`）。「系統工具」只是 `screens.md:143` 描述分組時用的名字。
- **該改哪一邊**：改文件，`screens.md:10` 與 `GLOSSARY.md:24` 改成「關於夜讀」裡的「啟動時檢查書架更新」「更新紀錄」，不寫成有「系統工具」這一層。

#### 6. 畫面規格的「背景工作」只列四種，漏了 AI 建立書源與自動換源

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

#### 7. 規格裡的幾句畫面字，程式改字或拿掉後沒跟著改

同一個原因：#382（畫面說明文字更精簡）、#369、#487（分組標題拿掉）改了畫面字，規格沒跟上。

- **標註的備忘框**：`docs/design/reader.md:52` 寫備忘輸入框「提示「寫下自己的話」」；程式的框沒有提示字（`lib/features/reader/features/highlight/reader_highlight_sheet.dart:130-135`：`GroupedTextFieldRow(controller: _note, minLines: 2, maxLines: 6, …)`，沒給 `hintText`），#382 拿掉的。
- **複製給 AI 的貼上框**：`docs/design/screens.md:83` 寫提示「貼上 AI 回的書源 JSON」；程式是「書源 JSON」（`lib/features/source_manager/ai_repair/ai_repair_page.dart:426`：`hintText: '書源 JSON'`）。
- **AI 服務的測試連線**：`docs/design/screens.md:84` 寫成功時提示「連得上：模型名」；程式是「連線與工具呼叫正常：模型名」（`lib/features/source_manager/ai_repair/ai_repair_settings_page.dart:320`），#369 改的。
- **閱讀統計**：`docs/design/screens.md:147` 寫「沒聽過時一組「累積閱讀時間」」；程式沒聽過有聲書時那一組沒有名稱（`lib/features/bookmarks/reading_stats_view.dart:245-248`：`if (listened.isEmpty) GroupedSection(children: [for (final record in read) _row(context, record)])`），#487 拿掉分組標題。
- **該改哪一邊**：改文件，照程式現在的字寫。

## 沒排進分段的程式

還沒列。

## 拿不準

- **第 1 筆**的「用檔案開書」是照「從檔案管理員選用夜讀開啟」讀的；作者原意若是 App 裡選檔，這筆不成立。
- **隱私說明**只核對了同步、備份、送給 AI 的長度上限與遮掉的資料、日誌遮罩；「AI 改書源之前的那一份不進備份、不同步」（`ai_repair_backups.dart` 存在哪）、WebDAV 帳密存在哪、AI 找書只送作品名稱到維基百科、讀章節的正文不存不算閱讀時間，都還沒對程式。
- **`docs/design/` 的日期與經過**：這幾份到處寫「使用者 2026-11-xx 在候選圖上選」與類別名稱，照 `auto-audit.md` 算給 agent 看的文件的沉積；但 `AGENTS.md` 要 agent 把使用者選的寫進 `docs/design/`，兩條要不要一起改由使用者定，還沒評、也還沒算筆數。
