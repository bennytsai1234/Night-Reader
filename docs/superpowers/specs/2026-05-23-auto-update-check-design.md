# Auto Update Check 設計

- 日期：2026-05-23
- 範圍：墨頁 Inkpage（Android）App 內自動檢查更新並下載安裝。
- 模組路由：[Settings Backup And Release](../../inkpage_reader_legado/settings_backup_and_release.md)。

## 1. 背景

`lib/core/services/update_service.dart` 已有 `AppUpdateService.checkUpdate()`，會打 GitHub Releases API、回傳 `UpdateInfo`，但目前：

- **沒有任何呼叫端** — UI 沒接，啟動流程沒接，等同於死碼。
- 版本比對用 `String.compareTo`，會在 `0.2.9` vs `0.2.72` 比錯（lexical 比較）。
- 沒處理 tag 前綴 `v`（本專案 release tag 是 `vX.Y.Z`）。
- 沒測試。

本 spec 處理「接上 UI + 修補版本比對 + 自動觸發」三件事，並在第二階段加入 App 內下載安裝。

## 2. 行為規格

### 2.1 觸發

- App 啟動後跑一次背景檢查（非阻塞，不影響首屏）。
- About 頁新增「檢查更新」ListTile，使用者可手動觸發。
- 兩條路徑共用 `AppUpdateService.checkLatest()`。

### 2.2 頻率與重複保護

- **不做時間節流** — 每次啟動都查。
- **靠忽略邏輯避免重複彈窗**：使用者按「忽略此版」會把 `vX.Y.Z` 寫進 SharedPreferences；之後同一版本的**自動檢查**不再彈 Dialog。手動按鈕仍會顯示。

### 2.3 新版提示

`UpdateDialog`：
- 標題：「發現新版 vX.Y.Z」
- 內容：release notes（GitHub Release body，原樣顯示，需可滾動）
- 按鈕：
  - **去下載**：切到 in-dialog 進度條（階段二）。階段一改為 `url_launcher` 開 GitHub Release 頁。
  - **稍後提醒**：關閉 Dialog，不寫任何狀態，下次啟動再彈。
  - **忽略此版**：寫入 `update.ignored_version = vX.Y.Z`，關閉 Dialog。

### 2.4 下載與安裝（階段二）

- 用 Dio 串流下載到 `getExternalCacheDir()/updates/inkpage-vX.Y.Z.apk`。
- Dialog 內顯示 0~100% 進度。
- 下載完用 `permission_handler` 取 `Permission.requestInstallPackages`，再呼叫 `open_filex` 跳系統安裝器。
- **同版本重複下載**：先檢查 cache dir 是否已有 APK 且檔案大小與 GitHub asset `size` 欄位相符；相符直接跳安裝。

### 2.5 平台限制

- iOS 與其他平台：啟動 hook 與 About 入口都直接 `if (!Platform.isAndroid) return;`。iOS 沒有合法的 APK 安裝路徑。

## 3. 架構分解

### 3.1 `AppUpdateService`（既有，修補）

純 HTTP + 版本比對。不碰 SharedPreferences、UI、檔案系統。

```dart
class AppUpdateService {
  Future<UpdateInfo?> checkLatest(); // null = 沒新版 / 失敗
}
```

修補內容：
- 版本比對改成 semver：拆 `int.parse(major.minor.patch)` 後逐段比；tag 前綴 `v` 去掉；無法解析時視為非新版並 log。
- 若 assets 找不到 `.apk`，視為沒新版（避免顯示無法下載的版本）。
- 移除 `isBeta` 不在這次 UI 接的暗門 — 參數保留但內部直接 `assert(!isBeta)` 或在 UI 入口固定傳 `false`。

### 3.2 `UpdateIgnoreStore`（新）

SharedPreferences 薄封裝，純粹為了好測。

```dart
class UpdateIgnoreStore {
  Future<bool> isIgnored(String version);
  Future<void> ignore(String version);
  Future<void> clear();
}
```

Key：`update.ignored_version`，String 型別。

### 3.3 `UpdateInstaller`（新，階段二）

下載與安裝流程。

```dart
class UpdateInstaller {
  Stream<DownloadState> download(UpdateInfo info);
  Future<bool> install(String filePath);
}

sealed class DownloadState {
  factory DownloadState.progress(double ratio);
  factory DownloadState.done(String filePath);
  factory DownloadState.error(Object e);
}
```

失敗 fallback：開瀏覽器到 Release 頁。

### 3.4 UI

- **啟動 hook**：在 `app_providers.dart` 或 `main.dart` 適當時機（不阻塞首屏）跑一次背景檢查。Provider 化或單純 `unawaited(_runCheck())`，看 `app_providers.dart` 現有風格而定。
- **`UpdateDialog`**：新 widget。三按鈕；階段二時內含進度條。
- **`AboutPage`**：在「系統工具」分類下新增「檢查更新」ListTile，subtitle 顯示「目前版本 vX.Y.Z」。手動觸發呼叫 service 並繞過 ignore 檢查。

## 4. 錯誤處理

| 情境 | 處理 |
|---|---|
| 網路失敗 / API 4xx / JSON 解析失敗 | `checkLatest()` 回 `null` + log。啟動時靜默；手動觸發顯示 SnackBar「檢查更新失敗，請稍後再試」 |
| Asset 找不到 APK | 視為沒新版 |
| 下載中斷 / 下載完大小與 asset size 不符 | Dialog 顯示重試按鈕，刪除殘檔 |
| 安裝權限被拒 | 提示 + 「開啟系統設定」（沿用 `app_permission_service.openSystemSettings()`） |
| 非 Android | 整個流程短路 |
| 同版本重複下載 | 比對 asset size，相符直接跳安裝 |

## 5. 新增相依與 Android 設定

- 新套件：`open_filex`（階段二）。
- 已有相依：`permission_handler`、`dio`、`shared_preferences`、`path_provider`、`url_launcher`、`package_info_plus`。
- `AndroidManifest.xml`（階段二）：
  - 宣告 `<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>`
  - 宣告 FileProvider authority
- `android/app/src/main/res/xml/file_paths.xml`（階段二）：宣告 `external-cache-path` 讓 FileProvider 導出 APK URI。

## 6. 測試策略

| 單位 | 測試 |
|---|---|
| `AppUpdateService` | mock Dio，餵 fake GitHub JSON。覆蓋：有新版、無新版、API 失敗、版本比對 case（`v0.2.72` vs `0.2.9`、相同版本、tag 前綴 `v`/無 `v`） |
| `UpdateIgnoreStore` | `SharedPreferences.setMockInitialValues({})` 走 in-memory，覆蓋 isIgnored / ignore / clear |
| `UpdateInstaller` | 不寫 unit test（涉及 OS 安裝器，難 mock）。手動測試清單寫在 PR |
| `UpdateDialog` | widget test 驗三按鈕 callback 觸發 |
| `AboutPage` | smoke test 加「檢查更新」按鈕的 tap 不 crash |

不寫真實網路整合測試。

## 7. 交付分階段

**Commit 1（最小可用）**：
- `AppUpdateService` 修補（semver 比對、tag 前綴）
- `UpdateIgnoreStore` + 單元測試
- `UpdateDialog`（無進度條版本）
- `AboutPage` 新增「檢查更新」入口
- App 啟動 hook
- 「去下載」用 `url_launcher` 開 Release 頁

**Commit 2（in-app 下載安裝）**：
- 加 `open_filex`
- `AndroidManifest.xml` + `file_paths.xml`
- `UpdateInstaller`
- `UpdateDialog` 加進度條與安裝流程
- 把「去下載」從開瀏覽器改成 in-app 下載

## 8. 已知風險

- `REQUEST_INSTALL_PACKAGES` 在某些 Android 版本與廠商 ROM 上行為不一致；fallback 開瀏覽器是必要的。
- GitHub API rate limit：未登入 60/h per IP。每次啟動都查在多開的測試裝置上可能踩到，但實務不大可能。若未來踩到，再加 24h 節流即可（spec 預留位置）。
- 同版本重複下載靠 `size` 比對，沒做 checksum；GitHub 不提供 asset checksum，要做需要額外發布 `.sha256` asset，目前不做。

## 9. 不在範圍

- Beta 通道 UI（service 參數保留，UI 不接）。
- iOS 安裝（無解）。
- 自動下載（必須由使用者按「去下載」才下）。
- App 內 release notes 的 Markdown 渲染（直接顯示文字即可）。
