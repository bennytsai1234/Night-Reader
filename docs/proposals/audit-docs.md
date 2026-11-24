# 全面檢查：文件

這份是全面檢查「文件」那一段的清單：給讀者看的說明（`README.md`、`website/index.html`、`PRIVACY.md`）、`docs/design/` 的規格、ADR 索引、給 agent 看的文件，以及 `.github/workflows/`、`.githooks/`、`tool/` 的腳本，和程式實際做的不一樣的地方。只讀、只列，不修。

- 讀的是 `origin/beta` 的 `fff55f9c`。
- 標準照 `docs/agents/auto-audit.md` 的「算問題的」「不報的」；每一筆都對過程式，兩邊附 `檔案:行號`，並用 `gh issue list --state all --search` 查過沒報過。

## 進度

| 類 | 讀了哪些 | 找到幾筆 |
|---|---|---|
| README 與網站 | `README.md`、`website/index.html` | 1 |

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
