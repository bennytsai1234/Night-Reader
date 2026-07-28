# 模組：source-manager — 書源管理

## 1. 職責

提供書源的完整生命週期管理：匯入（URL／檔案／剪貼簿）、批量校驗（isolate 池）、規則除錯、編輯器（六標籤頁表單）、分組與篩選、排序與拖拽、匯出／分享、訂閱式更新預留（TODO），以及清理非小說源/建議刪除來源。

## 2. 範疇

```
lib/features/source_manager/
├── source_manager_page.dart           # 書源列表 + AppBar 選單 + 底部操作列 + 匯入/匯出/校驗入口
├── source_manager_provider.dart        # 列表狀態（913 行） + SourceImportService 內聯（含 isolate 解析）
├── source_group_manage_page.dart       # 分組 CRUD + 分組分享
├── source_editor_page.dart             # 6 標籤頁編輯器 + 一鍵存檔/調試
├── source_debug_page.dart              # 調試結果終端機 UI（黑底 mono 串流日誌）
├── source_debug_provider.dart          # 委派 SourceDebugService 並收集 DebugLog
├── views/
│   ├── source_edit_basic.dart          # 基礎資訊（名稱/URL/圖示/分組/備註/Header）
│   ├── source_edit_search.dart         # 搜尋 URL + SearchRule 各欄位
│   ├── source_edit_explore.dart        # 發現 URL + ExploreRule 各欄位
│   ├── source_edit_book_info.dart      # BookInfoRule 各欄位
│   ├── source_edit_toc.dart            # TocRule 各欄位
│   └── source_edit_content.dart        # ContentRule 各欄位（含替代規則 JSON）
└── widgets/
    ├── source_item_tile.dart           # 列表項：拖拽把手/勾選/名稱分組/域名/狀態標籤/開關/編輯/更多
    ├── source_batch_toolbar.dart       # SelectActionBar：全選/反選/刪除/溢出選單
    ├── source_check_status_bar.dart    # 校驗中進度條 or 上次報告摘要
    ├── source_manager_menus.dart       # AppBar 三個 PopupMenu（分組篩選/排序/更多操作）
    ├── source_manager_dialogs.dart     # 校驗設定/日誌/批量分組/清理確認/輸入調試關鍵字
    ├── import_preview_dialog.dart      # 匯入預覽（新增/更新/無變化/不支援）
    └── rule_text_field.dart            # 規則輸入框 + 規則小幫手（CSS/XPath/JSONPath/JS 樣板）
```

## 3. 相依與衝擊

| 方向 | 相依模組 | 用途 |
|------|----------|------|
| 依賴 | `core/services/check_source_service.dart` | 批量校驗核心（isolate 池、JS heavy 分類、quarantine） |
| 依賴 | `core/services/source_debug_service.dart` | 逐步調試管線（search→info→toc→content） |
| 依賴 | `core/services/book_source_service.dart` | 編輯器存檔、調試階段調用（委派 WebBook 引擎） |
| 依賴 | `core/services/network_service.dart` | URL 匯入 HTTP 請求 |
| 依賴 | `core/database/dao/book_source_dao.dart` | 書源 CRUD、批量更新、group rename |
| 依賴 | `core/models/book_source.dart` | 完整書源模型 |
| 依賴 | `core/models/book_source_part.dart` | 列表輕量視圖 |
| 依賴 | `core/di/injection.dart` | getIt 服務定位 |
| 被依賴 | `features/settings/` | `SettingsPage` push `SourceManagerPage` |
| 被依賴 | `features/explore/` | `ExplorePage` 長按書源→編輯→push `SourceEditorPage` |
| 被依賴 | `features/book_detail/` | 換源底部表內「詳情/調試」→push `SourceEditorPage`/`SourceDebugPage` |
| 被依賴 | `features/association/` | `AssociationDialogHelper` 讀取 `SourceManagerProvider` |

## 4. 關鍵流程

### 4.1 匯入管線

```
SourceManagerPage._importWithPreview()
  → SourceManagerProvider.parseSourcesDetailedAsync()
    → compute(_parseSourcesPayloadForIsolate)  # 背景 isolate 解析 JSON
  → SourceManagerProvider.previewImport()
    → compare with existing (by URL + lastUpdateTime) → 分類 new/updated/unchanged
  → showImportPreviewDialog() → user confirms
  → SourceManagerProvider.importSources()
    → assign customOrder (preserve existing, append new)
    → BookSourceDao.upsertAll()
```

- 非小說來源自動停用 + 標記 `nonNovelSourceGroupTag`
- BOM 字元自動裁剪 (`_stripBom`)

### 4.2 批量校驗

```
SourceManagerProvider.checkAllSources() / checkSelectedSources()
  → CheckSourceService.check(urls)
    → prime JS heavy classification (isolate)
    → _SourceCheckExecutionPool(workers=8)
      → per-source: spawn Isolate → run stages (search/discovery/info/toc/content)
      → apply health group + error comment → persist
    → AppEventBus.fire(checkSourceDone)
```

- 同域名併發限制、JS heavy 書源專用 semaphore
- 失敗分類：loginRequired / searchBroken / detailBroken / contentBroken / upstreamUnstable …等，各自對應 `quarantineSourceGroupTag`
- 每次校驗完畢清除 JS 引擎快取避免記憶體暴增

### 4.3 調試

```
SourceDebugPage
  → SourceDebugProvider.startDebug()
    → SourceDebugService.startDebug(source, key)
      → (key heuristic): URL→info, "::"→explore, "++"→toc, "--"→content, else→search
      → sequential: search/explore → info → toc → content
      → stream DebugLog → UI 黑色終端機即時顯示
```

- 單例 `SourceDebugService`，支援 cancel

### 4.4 編輯器存檔

```
SourceEditorPage._save()
  → _syncSource()  # 6 個 tab 的 TextEditingController → 重建 rule objects
  → BookSourceService.saveSource()
    → BookSourceDao.upsert()
```

- 空字串自動轉 `null`（extension `_emptyToNull`）

## 5. 變更入口

| 檔案 | 影響 |
|------|------|
| `source_manager_provider.dart` | 列表狀態與匯入邏輯耦合（913 行），新增匯入格式/校驗項目時擴充此處 |
| `source_manager_page.dart` | AppBar/底部欄選單項目；新增操作入口時對應擴充 |
| `source_editor_page.dart` | 編輯器標籤頁；新增規則欄位時需同步 `_initControllers` + `_syncSource` + view |
| `source_debug_service.dart` | 調試管線；新增 stage 或判斷邏輯時修改 |

## 6. 已知風險

- **`SourceManagerProvider`（913 行）** 同時擔任列表 ViewModel 與匯入調度，單一類別過重。
- **`SourceImportService`** 直接內聯在 provider 檔案內，而非抽成獨立 service。
- **匯入 isolate** (`compute`) 非 typed：payload 以 `Map<String, List<Map<String, dynamic>>>` 傳輸，型別安全靠執行期斷言。
- **`CheckSourceService`（1079 行）** 內部類別繁多（`_SourceCheckExecutionPool`/`_SourceCheckTaskQueue`/`_AsyncSemaphore`），狀態機易出錯。
- **編輯器無驗證層**：所有欄位直接操作 `TextEditingController`，無欄位級與跨欄位驗證抽象。
- **無 UI 測試**：所有對話框為 static method，難以單元測試。

## 7. 不實施

- 不在 feature 層直接操作 `BookSourceDao`（應透過 service facade）。
- 不在 `SourceManagerPage` 內嵌複雜表單邏輯（已抽至 `source_editor_page.dart` 與其 views/）。
- 不透過 `GlobalKey` 或 inherited widget 跨頁面共享 provider 實例（選取狀態由 `SourceManagerProvider` 單一實例管理，透過 `ChangeNotifierProvider.value` 傳遞）。
