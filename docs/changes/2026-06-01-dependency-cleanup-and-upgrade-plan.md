# 依賴版本總清算與逐批升級計畫

> 本文件為**工程計畫草稿**，只規劃、不執行；建立時不修改任何程式碼、不 commit。
> 每個批次實際動手前，請再走一次 before/after 確認。

## 任務類型

Dependency + Cleanup（綜合，T2）。批次 1 含資料庫底層依賴調整，批次 4 跨多檔改外部套件 API，整體升級到 T2 紀律。

## 證據基準（盤點時間：2026-06-01）

- 環境：Flutter 3.41.6、Dart `^3.7.0`、目前版本 `0.2.97+111`
- 資料來源：`flutter pub outdated`、`flutter pub deps --json` 反向依賴查詢、`pubspec.lock`、pub.dev / GitHub 維護狀態

### 健康度三個好消息

1. **無 git fork / 本地 path 依賴**：`pubspec.lock` 中 git/path 來源數為 0，只有 4 個正常的 Flutter/Dart SDK 內建套件。沒有被硬鎖在 fork 的技術債。
2. **無 `dependency_overrides`**：沒有用強制覆寫壓版本。
3. **所有「卡住」都是約束或上游問題**，非自鎖，多數可控。

### `flutter pub outdated` 全表

直接依賴：

| 套件 | 現在 | 可升(免改約束) | 可解(改約束) | 最新 | 分類 |
|---|---|---|---|---|---|
| app_links | 6.4.1 | 6.4.1 | 7.1.1 | 7.1.1 | B |
| archive | 3.6.1 | 3.6.1 | 4.0.9 | 4.0.9 | B（改碼） |
| drift | 2.31.0 | 2.31.0 | 2.33.0 | 2.33.0 | 批次1 |
| drift_flutter | 0.2.8 | 0.2.8 | 0.3.0 | 0.3.0 | 批次1 |
| file_picker | 10.3.10 | 10.3.10 | 12.0.0-beta.5 | 11.0.2 | B（避 beta） |
| flutter_native_splash | 2.2.16 | 2.4.4 | 2.4.8 | 2.4.8 | A（需驗證） |
| flutter_widget_from_html | 0.16.1 | 0.16.1 | 0.17.2 | 0.17.2 | B |
| network_info_plus | 7.0.0 | 7.0.0 | 8.1.0 | 8.1.0 | B |
| package_info_plus | 9.0.1 | 9.0.1 | 10.1.0 | 10.1.0 | B |
| permission_handler | 12.0.1 | 12.0.3 | 12.0.3 | 12.0.3 | A |
| pointycastle | 3.9.1 | 3.9.1 | 3.9.1 | 4.0.0 | C（卡住） |
| share_plus | 12.0.2 | 12.0.2 | 13.1.0 | 13.1.0 | B |
| sqlite3_flutter_libs | 0.5.42 | 0.5.42 | 0.6.0+eol | 0.6.0+eol | D（移除） |
| workmanager | 0.7.0 | 0.7.0 | 0.9.0+3 | 0.9.0+3 | B（需測） |
| xml | 6.6.1 | 6.6.1 | 7.0.1 | 7.0.1 | B（改碼） |

dev 依賴：

| 套件 | 現在 | 可解 | 分類 |
|---|---|---|---|
| drift_dev | 2.31.0 | 2.33.0 | 批次1 |
| flutter_lints | 5.0.0 | 6.0.0 | B |

關鍵 transitive：

| 套件 | 現在 | 狀態 | 來源 |
|---|---|---|---|
| image | 3.3.0 | 可升 4.3.0 | 僅 `flutter_native_splash 2.2.16` |
| js | 0.6.7 | **discontinued** | `flutter_native_splash` / `pointycastle` / `audio_service` |
| sqlcipher_flutter_libs | (未安裝) | +eol | 無依賴者，無影響 |

## 四條依賴鏈干擾地圖

升級的核心策略：**依賴鏈分組，一鏈一批，各自驗證，絕不一次 `--major-versions` 全升**。四條鏈彼此不交叉，可獨立進行。

| 鏈 | 成員 | 干擾關係與現況 |
|---|---|---|
| ① Splash 鏈 | `flutter_native_splash` → `image` → `js` | 升 splash 連帶升 image 4.x、甩掉部分 js。**曾**與 epubx 透過 image 3↔4 衝突；epubx 已於 commit 4dea0d18 換成自製 `archive`+`xml` 解析器，**衝突源已消除**。其 Android build tools 前置（Gradle 8.14 / AGP 8.11.1 / Kotlin 2.2.20 / NDK 28.2）已於 commit 5a147020 升妥。 |
| ② 資料庫鏈 | `drift` / `drift_flutter` → `sqlite3_flutter_libs`(EOL) | 升 drift 至 2.32+、drift_flutter 至 0.3.0 後，sqlite3_flutter_libs 不再被需要，可移除。 |
| ③ 加密鏈 | `encrypt 5.0.3` → `pointycastle ^3` | encrypt 把 pointycastle 鎖在 `^3`，且 encrypt 已是最新版。pointycastle 4.0 **現在動不了**，非自身可控。 |
| ④ 壓縮/XML 鏈 | `archive` + `xml` → epub_service / 備份還原 | 升 archive 4 / xml 7 需改 7 個核心檔，**獨立於上面三鏈**，風險最高，排最後。 |

### ⚠️ Splash 歷史警示

`flutter_native_splash` 升級**試過又退回**：
- commit b02eedf7 整合 splash 消除冷啟動閃白
- 舊計畫 `docs/changes/2026-06-01-upgrade-android-build-tools.md` 打算升至 `^2.4.8`
- 但 `epubx` 需要 `image ^4`、舊 splash 卡 `image ^3` → 衝突 → commit 08e3a698 **移除** splash
- commit 4dea0d18 以自製解析器替換 epubx 後，**恢復** splash 為 `^2.2.16`（即現況）

因此 pubspec.yaml 目前是 `^2.2.16`，但衝突的根因（epubx）已不存在。升級 splash 現在理論上安全，但**務必實機驗證冷啟動 splash 不再閃白**再定案。

---

## 不再維護清理（方法 1：能移除嗎？要砍功能嗎？）

**結論：這次清理一個 App 功能都不用砍。**

| 套件 | 能否移除 | 要砍功能嗎 | 前置條件 |
|---|---|---|---|
| `sqlite3_flutter_libs` (EOL) | ✅ 能 | **不用** | 先完成批次 1（升 drift / drift_flutter）。`lib/` 完全無 `import`，純打包 native SQLite 用；drift 2.32+ 改由 `sqlite3` 3.x 自動 bundle，移除後資料庫照常運作 |
| `js` (discontinued) | ⚠️ 不可手動移除（transitive） | 不涉及功能 | 靠批次 2 升 splash / 等上游升 pointycastle、audio_service 自然甩掉 |
| `sqlcipher_flutter_libs` (EOL) | — | — | 未安裝，無需處理 |

依據：[sqlite3_flutter_libs 0.6.0+eol](https://pub.dev/packages/sqlite3_flutter_libs/versions/0.6.0+eol)（0.6.0 起此套件不再做任何事，drift 2.32+ 改用 sqlite3 3.x 自動 bundle）、[drift issue #3702](https://github.com/simolus3/drift/issues/3702)、[js discontinued 公告](https://dart.dev/go/package-discontinue)。

---

## 逐批升級計畫（方法 2：能升儘量升，分鏈防干擾）

> 每批獨立一個 commit / 分支，依序執行；任一批驗證失敗就回退該批，不影響其他批。
> 通用驗證命令：`flutter analyze`、`flutter test`。

### 批次 1：資料庫鏈 + 移除 EOL（風險低，純賺，建議先做）

**改動**
- `pubspec.yaml`：`drift: ^2.33.0`、`drift_dev: ^2.33.0`、`drift_flutter: ^0.3.0`
- `pubspec.yaml`：**刪除** `sqlite3_flutter_libs: ^0.5.0` 一行

**指令**
```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # drift 重新生成 .g.dart
flutter analyze
flutter test
```

**驗證**（資料庫是核心，需實機讀寫各一條路徑）
- `flutter pub get` 成功且 `sqlite3_flutter_libs` 不再出現在 `pubspec.lock`
- App 啟動 → 開啟書架（讀路徑）正常
- 新增一本書 / 寫入閱讀進度（寫路徑）正常
- 既有資料庫升級無 migration 錯誤（用既有資料的裝置測一次）

**回退**：`git checkout pubspec.yaml pubspec.lock` + 還原生成檔，`flutter pub get`。

---

### 批次 2：清 lock 落後 + Splash 鏈（無痛，但 splash 需實機驗證）

**改動**
- 先跑 `flutter pub upgrade`（在現有約束內升 9 個 locked 套件，含 permission_handler 12.0.3、image 4.x、video_player_android 等）
- 若要 splash 升至 2.4.x：確認 `pubspec.yaml` 的 `flutter_native_splash` 約束（現為 `^2.2.16`，已允許 2.4.x；如需 2.4.8 用 `flutter pub upgrade flutter_native_splash`）

**指令**
```bash
flutter pub upgrade
dart run flutter_native_splash:create   # splash 版本變動後重新生成原生資源
flutter analyze
flutter test
```

**驗證**
- **冷啟動實機測試**：splash 顯示正常、無閃白（這是 splash 歷史踩過的雷）
- Android 打包通過（build tools 前置已備妥）

**回退**：還原 `pubspec.lock`（與 `pubspec.yaml` 若有改），`flutter pub get`，重跑 `flutter_native_splash:create`。

---

### 批次 3：plus 系列大版本（低風險，逐個升逐個測）

**改動**（`pubspec.yaml` 改約束，建議**一次一個**升、各自驗證，不要一起）

| 套件 | 改為 | 注意 |
|---|---|---|
| app_links | `^7.1.1` | 深連結，測一次外部連結喚起 |
| network_info_plus | `^8.1.0` | 區域網路 IP（內建 web server 用） |
| package_info_plus | `^10.1.0` | 版本顯示（關於頁） |
| share_plus | `^13.1.0` | 分享功能 |
| file_picker | `^11.0.2` | **避開 12.0.0-beta**；本地書籍匯入需測 |
| flutter_widget_from_html | `^0.17.2` | HTML 渲染，測書籍詳情頁 |
| workmanager | `^0.9.0` | **背景任務**，需測下載 / 訂閱更新 |
| flutter_lints (dev) | `^6.0.0` | 純 lint，升後可能多一批警告需清 |

**指令**（每個套件重複）
```bash
flutter pub get && flutter analyze && flutter test
```

**回退**：逐個套件單獨 commit，出問題只 revert 該套件那個 commit。

---

### 批次 4：archive 4.x / xml 7.x（要改程式碼，風險最高，最後做，單獨分支）

**改動**：`pubspec.yaml` `archive: ^4.0.9`、`xml: ^7.0.1`，並修正 7 個受影響檔案的 API。

**archive 4.0 破壞性變更對照**（[changelog](https://pub.dev/packages/archive/changelog)）
- `decodeBuffer(...)` → `decodeStream(...)`
- `InputStream` → `InputMemoryStream`
- `OutputStream` → `OutputMemoryStream`
- `ZipEncoder.encode` 的 `autoClose` 預設改為 `false`

**受影響檔案（7 個）**
- `lib/core/services/epub_service.dart`（剛寫的自製 EPUB 解析器，重點回歸）
- `lib/core/services/backup_service.dart`
- `lib/core/services/restore_service.dart`
- `lib/core/utils/archive_utils.dart`
- `lib/core/engine/js/encode/encode_utils_hash.dart`
- `lib/core/engine/js/extensions/js_network_extensions.dart`
- `lib/core/engine/js/extensions/js_file_extensions.dart`

**xml 7.0**：確認 epub_service 的 XML 解析 API 是否受影響（先讀 changelog 再動）。

**驗證**（核心功能回歸，建議補測試）
- EPUB 匯入解析正常（多本不同結構的 EPUB）
- 備份匯出 → 還原匯入往返一致
- JS 引擎的 zip/壓縮相關擴充正常
- `flutter analyze` + `flutter test` 全綠

**回退**：整個分支 revert；archive/xml 固定回 `^3.6.1` / `^6.6.1`。

---

## 暫不處理項與追蹤 TODO

| 項目 | 原因 | 追蹤動作 |
|---|---|---|
| `pointycastle` 3.9.1 → 4.0.0 | 被 `encrypt 5.0.3` 鎖在 `^3`，encrypt 無新版 | 觀察 encrypt 是否釋出支援 pointycastle 4.x 的版本；或評估替換加密套件（影響規則引擎加密，T2，需獨立評估） |
| `js` 0.6.7 (discontinued) 殘留 | transitive，批次 2 後仍可能由 pointycastle / audio_service 帶入 | 隨上游升級自然消除，無需主動處理 |
| `file_picker` 12.x | 目前僅 beta | 待正式版釋出再評估 |
| win32 等桌面 transitive | 本專案為 Android/iOS，桌面平台依賴不影響 | 忽略 |

---

## 維護建議（避免下次再大清算）

1. **把 `flutter pub outdated` 變例行**：每次 release 前或每 1–2 個月跑一次，小步快升。
2. **lock 檔進版控**（已在做）：確保團隊與 CI 用同一組解析結果。
3. **升級分鏈分批**：永遠不要一次 `flutter pub upgrade --major-versions` 全升。
4. **選型偏好**：新增依賴時優先選活躍維護、功能不重疊的套件，減少未來相互干擾。

---

## 整體回退路徑

每批獨立 commit；任一批出問題只需 `git revert` 該批 commit 並 `flutter pub get`。批次 4 走獨立分支，未驗證通過不合併。所有改動皆可逆，無不可逆的資料遷移（drift schema 不變，僅底層 SQLite bundle 方式改變）。
