# 寫碼規範

`code-review` 審查時依這些規範判斷。格式、lint 與測試由 CI（`.github/workflows/ci.yml`）把關，不在這裡重複。

## 測試

- 不為了讓測試可觀測，在 production 程式碼加 `debug*`、`*ForTesting`、測試專用 getter、靜態 hook 或 UI 狀態快照。

## 資料與狀態

- Drift 表結構變更要在 `AppDatabase` 提高 `schemaVersion`，並在 `MigrationStrategy` 寫 migration。只更新 `.g.dart`，既有使用者的資料不會跟著升級。
- SQLite、SharedPreferences 與 App 私有檔案是三個不同的狀態來源；備份、還原、清理或遷移要逐一確認影響範圍。
- 新增會被 Model 或 Reader 直接讀取的偏好時，`SettingsProvider`、`AppConfig` 與 `PreferKey` 三者要一起檢查。

## 動畫

- 玻璃（`GlassSurface`、`BackdropFilter`）不包在 `Opacity`、`FadeTransition` 或 `AnimatedOpacity` 裡：從畫面邊緣進出用 `GlassSlide`，原地出現要淡入時用 `GlassReveal`（ADR 0022）。玻璃進出場的測試在動畫途中呼叫 `expectNoGlassUnderFade`（`test/support/glass_motion.dart`），只量透明度數值看不出模糊在哪一幀生效。
- 宣稱某段工作已離開主執行緒、拿掉一段等待，或改了骨架換場、開 App 進場、跳章的流程時，用 `bash tool/frame_budget_compare.sh <改前的提交> <test/frame_budget/ 的測試檔>` 比對改動前後每一幀的成本，它印出的表寫進 commit message（ADR 0018；看尖峰幀是誰造成的，用 `test/support/frame_budget.dart` 檔頭的歸因模式）。
- 新增或修改轉場、骨架換場與換場之後才開始的背景工作時，照 ADR 0029 的六點做：先骨架後內容、後面是實色時給 `SkeletonSwitcher.backdrop` 只遮一層、會在動畫前後變動的小狀態用獨立的 `ValueListenable` 不通知整頁、換場後的工作依序隔一格啟動（不用 `Priority.idle`）、推入的頁面第一格只畫骨架（分組清單頁用 `GroupedListView` 就有）、量測涵蓋到骨架換完再多一秒。

## Reader V2

- 排版樣式會進入 layout signature 與 metrics cache key；改動字級、行高、字距、縮排、字型或內容轉換時，要確認快取會失效、閱讀位置能正確恢復。

## 網路與書源

- 書源的 HTTP 一律經 `NetworkService` 與其攔截器。書源不支援登入與需要使用者互動的驗證，遇到就立即拒絕（ADR 0013）；不需要互動的網頁渲染（網址選項 `webView`、`java.webView`）照常在背景載入。

## 背景執行

- `lib/main.dart` 與 Workmanager 的 `callbackDispatcher()` 都會呼叫 `configureDependencies()`；背景 isolate 不共用主 isolate 的 GetIt 單例。
- 交給 `SourceIsolate.run` 的工作，以及傳給 `BookSourceService.searchBooks` 的 `filter`、`shouldBreak`，連同捕捉的變數會複製到另一個 isolate：在只捕捉書源、書籍、字串這類資料的頂層函式裡建立。方法或測試本體裡的 lambda 會把同一層其他閉包捕捉的變數（例如 `this`、頁面、資料庫連線）一起帶過去，送不出去或複製出用不到的東西。
- 在書源 isolate 執行的程式只用 `getIt` 裡的資料庫與 DAO（`registerDatabase`）；WebView、`rootBundle`、`SharedPreferences`、頁面這些只有主 isolate 有的東西，要先在 `SourceIsolate` 加上交給主 isolate 的代理（ADR 0028）。
- 說明或註解宣稱某段工作「在背景」「不佔主執行緒」時，沿呼叫路徑看到底：只有送進 `SourceIsolate.run`、worker 或 `Isolate.run` 的那一段在背景，呼叫端在主 isolate 讀整本目錄、逐章或逐筆的迴圈、每筆都 `notifyListeners`，都還在主執行緒（ADR 0018、0028）。
