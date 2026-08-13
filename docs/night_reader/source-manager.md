# source-manager

## Responsibility

本模組掌管書源的完整生命週期：列表檢視（篩選／排序／域名分組／拖拽排序）、多選批次操作（啟停用、分組、置頂置底、匯出、分享、校驗）、匯入（URL／檔案／剪貼簿，含隔離執行緒解析與匯入預覽）、批量校驗（isolate 池＋健康分類持久化）、規則除錯（逐步管線終端機）、六標籤頁規則編輯器、分組 CRUD 與分組分享、以及清理（建議刪除來源／非小說源）。

未來工作應從這裡開始的時機：任何新增「書源欄位／規則」、新增「校驗階段或健康分類」、新增「匯入來源格式」、調整「書源列表互動」的任務。訂閱式更新（legado 式書源訂閱）仍不存在（全庫無 `訂閱/订阅/subscribe` 相關實現），若要做此功能，列表頁的「更多」選單與 `SourceManagerProvider` 是切入點。

注意：核心執行引擎（WebBook、JS 規則、NetworkService、WebView 登入）不在本模組，屬於 engine／services 其他模組；本模組是它們的調度與管理層。

## Scope

代表性檔案與入口：

- `lib/features/source_manager/`（約 4,863 行）：
  - `source_manager_page.dart` — 書源列表頁（AppBar 三選單、搜尋列、底部 `SelectActionBar`、狀態列）；`SourceManagerPage` 由 settings / search / explore 三個頁面 push 進來。
  - `source_manager_provider.dart`（1,138 行）— 列表狀態（篩選/排序/選取/批次互斥）+ `SourceImportService` 內聯（同檔案頂層類別）。
  - `source_editor_page.dart` + `views/`（6 個 tab 表單）— 規則編輯器，`_initControllers` ↔ `_syncSource` 為欄位同步核心。
  - `source_debug_page.dart` / `source_debug_provider.dart` — 除錯終端機 UI 與串流收集。
  - `source_group_manage_page.dart` — 分組 CRUD＋分享；共用主頁 provider 實例（`ChangeNotifierProvider.value`）。
  - `widgets/` — `source_item_tile.dart`、`source_batch_toolbar.dart`（`SelectActionBar`）、`source_check_status_bar.dart`、`source_manager_menus.dart`（static 建構三個 AppBar 選單）、`source_manager_dialogs.dart`（static：校驗設定/日誌/批量分組/清理確認/除錯輸入）、`import_preview_dialog.dart`（含 `ImportPreviewResult`）、`rule_text_field.dart`（規則小幫手）。
- 服務層在 feature 之外（必須同步修改的地方，見 Change Entry Points）：
  - `core/services/check_source_service.dart`（1,079 行）— 批量校驗調度（pool／semaphore／JS-heavy 分類／健康持久化）。
  - `core/services/source_check_isolate.dart`（1,444 行）— 單書源在背景 isolate 內的完整校驗邏輯與健康分類判定。
  - `core/services/source_debug_service.dart` — 除錯管線（單例）。
  - `core/services/source_validation_context.dart` — 批次校驗「非互動 zone」旗標（擋掉人工驗證/驗證碼流程）。
- 模型與持久化：`core/models/source/book_source_logic.dart`（健康標籤常數＋`runtimeHealth` 判定）、`core/database/dao/book_source_dao.dart`（CRUD／`insertOrUpdateAll`／`updateCustomOrder`／`renameGroup`／`removeGroupLabel`／`watchDiscoveryPart`）。
- 測試：`test/features/source_manager/`（9 檔，`source_manager_provider_test.dart` 1,159 行為主要行為規格）＋ `test/core/services/check_source_service_test.dart`（僅 2 測）。
- 開發期真實書源回歸：`tool/source_validation_support.dart`（共用基礎）、`source_single_debug_test.dart`／`source_batch_validation_test.dart`／`live_source_validation_test.dart`／`explore_batch_validation_test.dart` ＋ shell `run_source_validation.sh`／`flutter_test_with_quickjs.sh`。書源規則變更回歸優先走這些腳本（DEVELOPMENT.md:136-141、219）。

公開 API 重點：`SourceImportService`（`parseSourcesDetailedAsync`/`previewImport`/`importSources`/`importFromJson`/`importFromUrl`/`fetchImportTextFromUrl`）、`CheckSourceService`（`check`/`cancel`/`config`/`lastReport`/`sourceProgress`）、`spawnSourceCheck`＋`SourceCheckIsolateHandle`、`SourceDebugService.startDebug`＋`logStream`。

## Dependencies & Impact

上游輸入（本模組依賴）：
- `BookSourceDao`：列表（`getAllPart`）、批量寫（`upsertAll`/`insertOrUpdateAll`/`deleteByUrls`/`updateCustomOrder`）、單項開關（`updateEnabledByUrl`/`updateEnabledExploreByUrl`）、分組（`renameGroup`/`removeGroupLabel`）。provider 直接操作 DAO（非經 service facade）。
- `BookSourceService`（engine 委派）：編輯器存檔 `saveSource`、除錯各階段與 isolate 校驗共用 `searchBooks`/`getBookInfo`/`getChapterList`/`getContent`/`exploreBooks`。
- `NetworkService`：URL 匯入的 HTTP 抓取（`fetchImportTextFromUrl`）。
- `BookSource`/`BookSourcePart` 模型與 `book_source_logic.dart` 擴充（`runtimeHealth`/`isNovelTextSource`/`getCheckKeyword`）。
- `getIt` 服務定位；`AppStoragePaths.shareExportFile`（分享/匯出檔案）；`AppFileSelectionService.pickBookSourceImportPath`（允許 `.json/.txt/.legado`，`app_file_selection_service.dart:30-31`；背後是 third_party 受控 fork file_picker）。
- `shared_preferences`（`PreferKey.checkSource*` 校驗設定）；`flutter/services` Clipboard（匯出、剪貼簿匯入）；`share_plus`。

下游受影響（本模組變更會打到的區域）：
- 入口 push 本頁：`settings_page.dart:57`、`search_page.dart:233`、`explore_page.dart:165`。
- 長按/換源進編輯器與除錯：`explore_page.dart:525`（長按→`SourceEditorPage`）、`book_detail_page.dart:674/690`（換源表內「編輯/調試」）。
- `association_dialog_helper.dart:49-96` 直接呼叫 `SourceImportService().importFromJson/importFromUrl/fetchImportTextFromUrl`（不經 provider）——改 `SourceImportService` 行為會影響深連結/關聯匯入。
- 健康狀態消費：`search_provider.dart:343` 以 `isSearchEnabledByRuntime` 過濾搜尋池；`book_detail_provider.dart` 多處（159/167/272/308/418/700）讀 `runtimeHealth`/`isReadingEnabledByRuntime`。改健康標籤或判定順序＝直接改搜尋與閱讀可用性。
- `explore_provider.dart:60/80` 透過 `watchDiscoveryPart`/`getDiscoveryPart` 串流訂閱 DAO——本頁 `enabledExplore` 開關、分組標籤變更會即時反映到發現頁。
- `CheckSourceService` 完成時 fire `AppEventBus.checkSourceDone`（`core/services/event_bus.dart`），目前模組外無任何 listener；另有平行的 `core/engine/app_event_bus.dart`（bookshelf/book_detail/reader_v2 使用），兩者不相通。

## Key Flows

### 1. 匯入管線（URL／檔案／剪貼簿）
```
source_manager_page.dart: _showImportDialog / _importFromFile / _importFromClipboard
  → _importWithPreview
    → provider.parseSourcesDetailedAsync(json)
        → compute(_parseSourcesPayloadForIsolate)   # 背景 isolate 解析
        # 非小說源: enabled=false、enabledExplore=false、加 nonNovelSourceGroupTag、丟進 unsupported
    → provider.previewImport()                      # 以 bookSourceUrl + lastUpdateTime 對比 DAO
        → new / updated / unchanged 三分類
    → showImportPreviewDialog()                     # 新/更新可勾選，無變化自動跳過
  → provider.importSources(confirmed)
    → SourceImportService._prepareImportSources     # 既有 customOrder 保留、新增者接續
    → dao.insertOrUpdateAll
```
- BOM 字元由 `_normalizeImportJson` 統一裁剪（含 URL 抓取後的 `_importPayloadToText`：String / Uint8List / List<int> / JSON 物件四種型別處理）。
- `importFromUrl` 用 `NetworkService().dio.getUri`（plain responseType），非 2xx 拋 `StateError`。
- `SourceManagerPage._importWithPreview` 全程以 `_isImporting` 狀態列鎖定 UI（`_runImportFlow`）。

### 2. 批量校驗（isolate 池）
```
checkAllSources / checkSelectedSources (config 可選)
  → CheckSourceService.check(urls)                  # isChecking 防重入，直接回 lastReport
  → SourceValidationContext.runNonInteractive       # zone 旗標：批次內禁止互動驗證/驗證碼
  → _primeSourceExecutionTraits                     # compute 預分類 JS-heavy（背景 isolate）
  → _SourceCheckExecutionPool(workers=8)
      # 同域名 _AsyncSemaphore(8) + JS-heavy 專用 semaphore(8)
      → 每源: spawnSourceCheck(source, config, sourceTimeoutDuration)
          # sourceTimeoutDuration = 階段數加權 × 單步超時，上限 90s
          # RootIsolateToken → BackgroundIsolateBinaryMessenger（platform channel）
          # NetworkService().init(ephemeral: true)（isolate 內無 getIt）
      → isolate 內 _IsolateSourceChecker: search → (未終結) discovery → book flow
          detail → toc(限 8 章) → content(探測 5 章，跳過疑似鎖章)
      → 回傳 SourceCheckIsolateResult(updatedSourceJson + logs)
  → 主 isolate 套用健康群組 + // Error: 註解（_persistStatus，批次 16 筆 flush）
  → _lastReport + fire AppEventBus.checkSourceDone
```
- 失敗分類（isolate 內 `_issueFromException` + 主 isolate `_recordSourceTimeout`/`_recordUnexpectedSourceFailure`）：`nonNovel`/`downloadOnly`/`loginRequired`/`searchBroken`/`discovery(Broken|DetailBroken|TocBroken|ContentBroken)`/`detailBroken`/`tocBroken`/`contentBroken`/`upstreamUnstable`，對應群組標籤寫回 DAO（`detailBroken/tocBroken/contentBroken/upstreamUnstable` 額外加 `quarantineSourceGroupTag`）。
- 每次批次開始與結束都 `JsEngine.clearCaches()`＋`JsExtensionsBase.clearCaches()`（大量 jsLib/TTF 記憶體），結束於 `finally`（取消也清）。
- `cancel()` 只停 `_isChecking`＋abort 活動 isolate；worker 迴圈靠 `shouldContinue()` 收尾。
- isolate 異常訊息以 List 形式回主線程寫入 `CrashHandler.recordError`；`§DIAG§` 前綴 log 只挑「解析/原始錯誤/[js]」寫崩潰日誌。
- UI：`_checkNotifyTimer` 500ms 節流通知；每源進度在 `SourceItemTile` 內顯示；完成後狀態列點擊 → 校驗日誌對話框或跳「異常」篩選（`source_manager_page.dart:112-114`）。

### 3. 除錯管線
```
SourceDebugPage(source, debugKey)
  → SourceDebugProvider.startDebug()
    → SourceDebugService.startDebug (單例, cancel 支援)
        key 啟發式: startsWith('http')→詳情; contains('::')→發現(split 末段);
                    startsWith('++')→目錄; startsWith('--')→正文; 其餘→搜尋
        → 依序 search/explore → info → toc → content，Log 以 state 標記
          10=搜尋/發現, 20=詳情, 30=目錄, 40=正文, 1000=成功, -1=錯誤
  → logStream(broadcast) → 黑色 mono 終端機即時串流
```
- 編輯器 AppBar 的除錯按鈕固定用 `debugKey: '我的世界'`（`source_editor_page.dart:276`）；列表「調試書源」先彈 `showDebugInput`。
- 除錯頁提供「複製完整日誌」與「重新除錯」；頁面銷毀即 `cancel()`。

### 4. 編輯器存檔
```
SourceEditorPage._save()
  → _syncSource()   # controllers map → 重建 SearchRule/ExploreRule/BookInfoRule/TocRule/ContentRule
  → _validateRequiredFields()  # 僅書源名稱 + 網址非空（其餘無驗證）
  → BookSourceService().saveSource → dao.upsert
  → Navigator.pop(context, true)   # true = 列表頁收到後 loadSources
```
- 空字串自動轉 `null`（`extension _emptyToNull`）；`SourceEditorPage` 亦可注入 `onSave`（book_detail 換源表入口用）。
- 除錯按鈕先 `_syncSource`＋驗證再進 `SourceDebugPage`。

### 5. 匯出／分享
- 匯出：`exportSelected()` 以 UTF-8 bytes > 512KB（Android Binder IPC ~1MB 下限）判斷走剪貼簿還是改走檔案分享（`_shareSourceObjects`）；回傳值決定 SnackBar 文案。
- 分享：`shareSourcesByUrls` 逐一 `getByUrl` 組 JSON；檔名經 `sanitizeExportBaseName`（去 `.legado`/`.json`、剔除路徑與控制字元）；分組分享檔名 `'$groupName.legado'`。

### 6. 選取與批次操作
- 選取集合 `_selectedUrls` 以 URL 為 key；`selectAll`/`revertSelection` 只作用於「目前可見列表」；`checkSelectedInterval`（連續選取）以可見次序補滿首尾區間。
- 批次互斥：`isMutationBusy`（`_beginBatchOperation`/`_endBatchOperation`）＋逐 URL `_pendingSourceMutations`，重複觸發直接忽略（有專測）。
- 返回鍵：`PopScope` 在選取非空時攔截返回改為清空選取（`source_manager_page.dart:60-65`）。
- 拖拽排序僅在 `canReorder`（手動排序＋無篩選＋無搜尋＋無忙碌）成立時以 `ReorderableListView` 啟用；`reorderSource` 走 `updateCustomOrder`。

## Change Entry Points & Routes

常見任務的第一站與必須同步的多檔路徑：

- **新增列表篩選桶**（如新的狀態分類）：`source_manager_provider.dart:_computeVisibleSources`（`filterGroup` 分支）＋ `source_manager_menus.dart:buildGroupMenu`（選單項）。若新桶來自健康標籤，同時檢查 `book_source_logic.dart` 標籤常數。
- **新增批次操作**：provider 方法（套 `_beginBatchOperation` 慣例）＋ `source_batch_toolbar.dart:SelectActionBar` 的 callback 與選單 ＋ `source_manager_page.dart:bottomNavigationBar` 接線，三處同步。`SelectActionBar` 是受控元件，callback 全由頁面提供。
- **新增書源規則欄位**（最易漏）：
  1. `core/models/source/book_source_rules.dart`（SearchRule/ExploreRule/BookInfoRule/TocRule/ContentRule 模型）
  2. `source_editor_page.dart:_initControllers`（controller key）＋ `_syncSource`（寫回 model）
  3. 對應 `views/source_edit_*.dart`（`RuleTextField`）
  4. 如需校驗用到：`source_check_isolate.dart:_sourceLooksJsHeavy`（`check_source_service.dart:906` 的欄位清單）與 `_payloadMapContainsRuleJs` 的遞迴掃描（新欄位若含 `<js>`/`@js:` 即被視為 JS-heavy——payload 遞迴掃描自動涵蓋，但 `_sourceLooksJsHeavy` 白名單需手動加）。
- **新增校驗階段或健康分類**（多檔同步路徑，極易漂移）：
  1. `book_source_logic.dart`：`SourceHealthCategory` enum、群組標籤常數、`sourceRuntimeStatusTags`、`runtimeHealth` getter 的判定優先序
  2. `source_check_isolate.dart`：`_applyHealthGroup`、`_issueFromException`、`_issuePriority`
  3. `check_source_service.dart`：`_applyHealthGroup`（與 isolate 版**重複**，兩處都要改）
  4. `source_item_tile.dart:_buildStatusTag`（顏色語義：cleanupCandidate=error / quarantined=warning）
  5. 測試：`test/features/source_manager/source_manager_provider_test.dart`（行為規格）、`test/core/services/check_source_service_test.dart`（目前僅 config 測試）
  6. 真實書源回歸：`tool/` 腳本。
- **改匯入解析**：`source_manager_provider.dart` 的 `_parseSourcesPayloadForIsolate`（isolate entry，必須 top-level）＋ `SourceImportService`。
- **改除錯流程**：`core/services/source_debug_service.dart`（單例）；UI 在 `source_debug_page.dart`（state 值 1000/-1/10-40 決定顏色）。
- **改校驗的調度**（併發/超時/取消）：`check_source_service.dart`（`_SourceCheckExecutionPool`/`SourceCheckConfig.sourceTimeoutDuration`/`cancel`）。

## Known Risks

- **`SourceManagerProvider`（1,138 行）**：列表 ViewModel＋匯入調度＋大量批次操作單一類別過重；`SourceImportService` 雖已是獨立類別但仍內聯在同一檔案。舊文件記載的 913 行問題仍在（還變胖了）。
- **健康分類三處重複**：`_applyHealthGroup` 在 `check_source_service.dart:786` 與 `source_check_isolate.dart:1039` 幾乎逐行複製；`runtimeHealth` 判定又在 `book_source_logic.dart:217` 是第三份語義。任一份漂移（例如新分類只加一邊）會造成「校驗結果與列表顯示/搜尋排除不一致」。目前健康標籤文字也在三處散落。
- **isolate 邊界限制**：isolate 內 getIt 為空，DAO 依賴退化為記憶體模式（`source_check_isolate.dart:191` 註解）；`NetworkService` 需在 isolate 內自行 `init(ephemeral: true)`（獨立 cookie jar，避免多 isolate 檔案競爭）。flutter_js 為 FFI，理論上不可跨 isolate，`source_check_js_worker_probe.dart` 專測此場景，但該檔案目前**無任何生產呼叫者**（疑似死碼）。
- **非互動 zone**：批次校驗在 `SourceValidationContext` zone 內執行；需要人工驗證/驗證碼的來源會被判定 `upstreamUnstable` 並標 `已隔離`（quarantine）。這是設計而非 bug，但「被隔離來源不視為永久失效」的語意要跟 `source_item_tile` 的警告色、搜尋排除行為一起理解。
- **匯入 isolate 非 typed**：`compute` payload 是 `Map<String, List<Map<String, dynamic>>>`，型別安全靠執行期斷言（`BookSource.fromJson(Map<String, dynamic>.from(...))`）。
- **編輯器無驗證抽象**：除名稱/網址外全無欄位驗證；規則錯誤要等到除錯或校驗才暴露。`source_editor_page.dart` 的 controller map 用字串 key，新增欄位時 `_initControllers`/`_syncSource`/view 三方任何一處漏改不會有編譯錯誤。
- **`PreferKey.checkSource`（config summary）只寫不讀**：`check_source_service.dart:505` 寫入後無任何消費端。
- **事件匯流排分裂**：`checkSourceDone` fire 在 `core/services/event_bus.dart`，但 bookshelf/book_detail/reader_v2 用的是 `core/engine/app_event_bus.dart`——校驗完成目前無法通知其他模組，若未來要「校驗後自動清快取/刷新書架」需先選邊。
- **測試覆蓋缺口**：`check_source_service_test.dart` 只有 config 載入與超時預算 2 測；`_SourceCheckExecutionPool`/`_AsyncSemaphore`/報告聚合/取消路徑無單測。UI 測試用 `_FakeSourceDao extends Fake` 註冊進 GetIt（`source_manager_page_smoke_test.dart`），沒覆蓋真實 DAO 行為。tool/ 腳本依賴真實網站與 QuickJS 環境（`flutter_test_with_quickjs.sh`），CI 不會跑。
- **舊文件失準處**（本文件已修正）：舊版聲稱 association 讀取 `SourceManagerProvider`，實際 `association_dialog_helper.dart:49-96` 已改用 `SourceImportService` 直呼；舊版「訂閱式更新預留」仍屬 TODO；舊版「provider 913 行」現為 1,138 行。

## Boundaries

- **健康判定是確定性規則**，別加啟發式隨機：`runtimeHealth` 的判定順序即優先序（`book_source_logic.dart:217-366`：nonNovel → downloadOnly → loginRequired → searchBroken → discovery* → detail/toc/contentBroken → upstreamUnstable → healthy）；isolate 內 `_issuePriority`（`source_check_isolate.dart:1371`）是另一套用於「多 issue 選主因」的權重，兩者不要互相參照。
- **非小說判定有封閉 marker 清單**（`book_source_logic.dart:40-68`，含「有聲/漫畫/podcast/m3u8…」），且以名稱/分組/註解/URL/探索/搜尋欄位的字串包含為準；新增 marker 只能加字串常數，不要改成機器學習或黑名單檔案。
- **批次校驗永不執行互動流程**（`SourceValidationContext` 非互動 zone，`SourceInteractionBlockedException`）。凡新增網路/驗證行為必須確認在該 zone 下會拋此例外而非卡死。
- **校驗常數**：workers=8、同域名併發=8、JS-heavy semaphore=8、狀態寫入批次=16、log 上限 400 條（`check_source_service.dart:424-432,1011`）；isolate 內章節上限 8、正文探測 5 章、正文可讀門檻 20 runes（`source_check_isolate.dart:249-251,1288-1294`）。改動需連同 `sourceTimeoutDuration` 的 90s 上限一起評估。
- **匯出契約**：>512KB 自動由剪貼簿改走系統分享（Android Binder 限制，`source_manager_provider.dart:775-777`）；檔名經 `sanitizeExportBaseName` 白名單過濾（去 `.legado/.json`、禁控制字元與 `/:*?"<>|`）。檔案匯入 picker 允許 `.json/.txt/.legado` 三種副檔名（內容仍須是 JSON，`app_file_selection_service.dart:30-31`）。
- **provider 生命周期歸屬**：`SourceManagerProvider` 每頁建例（`ChangeNotifierProvider(create:)`），並在 `dispose` 中 `checkService.dispose()`；`SourceGroupManagePage` 透過 `ChangeNotifierProvider.value` 共享同一實例。不要在 feature 層另開 `CheckSourceService` 長生命週期實例。
- **DAO 直接使用是既定現實**：provider 對列表/開關/排序/分組操作直接呼叫 `BookSourceDao`（舊文件「不在 feature 層直接操作 DAO」的邊界已不符現狀）；只有匯入與存檔走 service（`SourceImportService`/`BookSourceService`）。新批次操作照同樣慣例。
- **改 Drift table/DAO 必須跑 `build_runner` 並處理 schema migration**（DEVELOPMENT.md:221）；書源相關變更需以 `tool/` 腳本在真實網站上驗證（DEVELOPMENT.md:219），本機不做 build。
