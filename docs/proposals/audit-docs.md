# 全面檢查：文件

這份是全面檢查「文件」那一段的清單：給讀者看的說明（`README.md`、`website/index.html`、`PRIVACY.md`）、`docs/design/` 的規格、ADR 索引、給 agent 看的文件，以及 `.github/workflows/`、`.githooks/`、`tool/` 的腳本，和程式實際做的不一樣的地方。只讀、只列，不修。

- 讀的是 `origin/beta` 的 `fff55f9c`。
- 標準照 `docs/agents/auto-audit.md` 的「算問題的」「不報的」；每一筆都對過程式，兩邊附 `檔案:行號`，並用 `gh issue list --state all --search` 查過沒報過。

## 進度

| 類 | 讀了哪些 | 找到幾筆 |
|---|---|---|
| README 與網站 | `README.md`、`website/index.html` | 1 |
| 隱私說明 | `PRIVACY.md`、`lib/features/about/privacy_pages.dart`（App 的「隱私說明」與「權限」） | 2 |

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

### 隱私說明

#### 2. 隱私說明的「同步」列了會同步哪些資料，漏了 AI 找書「不想看的」清單與書架、搜尋的設定

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

#### 3. App 的「權限」說哪些工作會用通知，漏了 AI 建立書源與自動換源

- **文件寫的**：「朗讀的播放控制，與修書源、校驗書源、AI 找書、放到背景的搜尋的進度會使用通知權限；…在 Android 上，它們跑的時候會開前景服務」（`lib/features/about/privacy_pages.dart:130`）。
- **程式做的**：AI 建立書源與自動換源也是背景工作，跑的時候一樣在通知欄顯示進度、開前景服務。AI 建立書源按下「開始建立」就建一件背景工作（`lib/features/source_manager/ai_repair/ai_create_source_page.dart:162-163`：`final run = SingleRepairRun(session); if (!_runs.adopt(run)) …`，`SingleRepairRun` 是 `RepairRun`，`RepairRun implements BackgroundJob`，`lib/features/source_manager/ai_repair/repair_runs.dart:103`）；自動換源是 `class AutoSourceSwitch implements BackgroundJob`，「跑的時候佔背景工作的位置、只有『結束』」（`lib/core/source_switch/auto_source_switch.dart:24-28`）。
- **該改哪一邊**：改文件，補上 AI 建立書源與自動換源。
