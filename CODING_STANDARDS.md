# 寫碼規範

合併前的審查（`codex-review`）依這些規範判斷。格式、lint 與測試由 CI（`.github/workflows/ci.yml`）把關，不在這裡重複。

## 測試

- 不為了讓測試看到內部狀態，在 production 程式碼加 `debug*`、測試專用 getter 或 UI 狀態快照；測試照公開的行為驗證。
- 元件測試（`testWidgets`）等的平台呼叫都換成假的實作：App 資料夾已由 `test/flutter_test_config.dart` 換好，其他平台呼叫照它換。真的平台呼叫在元件測試裡永遠等不到回覆，測試卡住、`--timeout` 也停不了（2026-11-09 書源管理的測試因此卡了 18 分鐘）。
- 會變的狀態不放在全 App 共用的靜態變數裡：測試之間會互相影響（2026-11-05 前一項測試量好的標點表留給下一項，骨架比對依測試先後而不同）。放在擁有它的物件上（資料層、依賴注入的服務），測試換一個新的就乾淨。開 App 讀一次、整個 App 共用、非放靜態不可的快取，給一個清除的入口，測試外殼在每項測試前後呼叫。

## 資料與狀態

- Drift 表結構變更要在 `AppDatabase` 提高 `schemaVersion`，並在 `MigrationStrategy` 寫 migration。只更新 `.g.dart`，既有使用者的資料不會跟著升級。
- SQLite、SharedPreferences 與 App 私有檔案是三個不同的狀態來源；備份、還原、清理或遷移要逐一確認影響範圍。
- 新增會被 Model 或 Reader 直接讀取的偏好時，`SettingsProvider`、`AppConfig` 與 `PreferKey` 三者要一起檢查。

## 動畫

- 玻璃（`GlassSurface`、`BackdropFilter`）不包在 `Opacity`、`FadeTransition` 或 `AnimatedOpacity` 裡：從畫面邊緣進出用 `GlassSlide`，原地出現要淡入時用 `GlassReveal`（ADR 0022）。玻璃進出場的測試在動畫途中呼叫 `expectNoGlassUnderFade`（`test/support/glass_motion.dart`），只量透明度數值看不出模糊在哪一幀生效。
- 宣稱某段工作已離開主執行緒、拿掉一段等待，或改了骨架換場、開 App 進場、跳章的流程時，用 `bash tool/frame_budget_compare.sh <改前的提交> <test/frame_budget/ 的測試檔>` 比對改動前後每一幀的成本，它印出的表寫進 commit message（ADR 0018；看尖峰幀是誰造成的，用 `test/support/frame_budget.dart` 檔頭的歸因模式）。
- 只修使用者在手機上覺得頓的動畫，量測量到超過、使用者感覺不到的不主動修（ADR 0036）。修一段動畫前先照 ADR 0037 說它屬於哪種場景、用哪個流暢策略：點一下進頁、開面板、閱讀器原地重排的重工作放在畫面靜止時做完再開始動畫，不切碎攤進動畫；只有手指在動的時候與照時間切的工作才每幀限量。做到的標準是沒有掉幀：畫面在變的每一幀，扣掉測試的資料庫時間、閱讀器排版切片照實算後都低於 4.2ms（手機 8.3ms，ADR 0029、0036）；最重一幀降了但還超過不算修好。
- 新增或修改轉場、骨架換場與換場之後才開始的背景工作時，照 ADR 0029 的六點做：先骨架後內容、後面是實色時給 `SkeletonSwitcher.backdrop` 只遮一層、會在動畫前後變動的小狀態用獨立的 `ValueListenable` 不通知整頁、換場後的工作依序隔一格啟動（不用 `Priority.idle`）、推入的頁面第一格只畫骨架（分組清單頁用 `GroupedListView` 就有）、量測涵蓋到骨架換完再多一秒。

## 給讀者看的說明

- 拿掉、改名或搬動使用者看得到的功能與設定時，對照 `website/index.html`（功能介紹、上手步驟、常見問答）與 `README.md`，不符的在同一個 PR 改。網站隨正式版部署，#92 拿掉朗讀音量後網站寫錯到下一個正式版前才發現。

## Reader V2

- 排版樣式會進入 layout signature 與 metrics cache key；改動字級、行高、字距、縮排、字型或內容轉換時，要確認快取會失效、閱讀位置能正確恢復。

## 網路與書源

- 書源的 HTTP 一律經 `NetworkService` 與其攔截器。書源程式要使用者操作（開網頁、驗證碼）只在登入頁按下的動作裡可以（`SourceInteraction.runInteractive`），其他地方立即拒絕，背景工作不等人（ADR 0038）；不需要互動的網頁渲染（網址選項 `webView`、`java.webView`）照常在背景載入。

## 背景執行

- `lib/main.dart` 與 Workmanager 的 `callbackDispatcher()` 都會呼叫 `configureDependencies()`；背景 isolate 不共用主 isolate 的 GetIt 單例。
- 交給 `SourceIsolate.run` 的工作，以及傳給 `BookSourceService.searchBooks` 的 `filter`、`shouldBreak`，連同捕捉的變數會複製到另一個 isolate：在只捕捉書源、書籍、字串這類資料的頂層函式裡建立。方法或測試本體裡的 lambda 會把同一層其他閉包捕捉的變數（例如 `this`、頁面、資料庫連線）一起帶過去，送不出去或複製出用不到的東西。
- 在書源 isolate 執行的程式只用 `getIt` 裡的資料庫與 DAO（`registerDatabase`）；WebView、`rootBundle`、`SharedPreferences`、頁面這些只有主 isolate 有的東西，要先在 `SourceIsolate` 加上交給主 isolate 的代理（ADR 0028）。
- 規則 JS 呼叫 Dart 一律同步傳回結果；要等網路、資料庫或平台的，經 `JsExtensionsBase.onBlocking` 與 `BlockingCall.run` 交給網路 isolate，工作在 `js_blocking_tasks.dart` 這類只捕捉資料的頂層函式裡建立，裡面不跑規則 JS（ADR 0034）。不要從 JS 的 handler 傳回 `Future`：JS 拿到的是還沒完成的結果。
- 說明或註解宣稱某段工作「在背景」「不佔主執行緒」時，沿呼叫路徑看到底：只有送進 `SourceIsolate.run`、worker 或 `Isolate.run` 的那一段在背景，呼叫端在主 isolate 讀整本目錄、逐章或逐筆的迴圈、每筆都 `notifyListeners`，都還在主執行緒（ADR 0018、0028）。
