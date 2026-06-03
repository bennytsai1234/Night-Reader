# 閱讀器 V2

## 目前職責

閱讀頁面的全部功能：排版引擎（Typography）、Canvas 渲染（Tile-based rendering）、viewport（捲動/滑動）、runtime 狀態機（位置、進度、預讀排程、效能追蹤）、TTS 朗讀、設定面板、書籤、章節替換規則。最複雜的模組，release 重點回歸區域。

## 範圍

主路徑：`lib/features/reader_v2/`（50+ 檔案，8 層架構）

| 層 | 路徑 | 職責 |
|---|---|---|
| **content** | `lib/features/reader_v2/content/` | 章節資料載入與轉換；呼叫 ChapterContentPreparationPipeline |
| **runtime** | `lib/features/reader_v2/runtime/` | 狀態追蹤（位置、進度、預讀排程、效能指標） |
| **layout** | `lib/features/reader_v2/layout/` | 排版引擎（字體、行距、段落、styles、specs 計算） |
| **render** | `lib/features/reader_v2/render/` | 低層渲染（tile painter、page cache、line boxes、text adapters） |
| **viewport** | `lib/features/reader_v2/viewport/` | viewport 管理與捲動/滑動控制 |
| **shell** | `lib/features/reader_v2/shell/` | 頂層 Widget 容器（ReaderV2Page） |
| **application** | `lib/features/reader_v2/application/` | Coordinator 模式（feature 協調）、Session facade（狀態隔離）、依賴裝配 |
| **features** | `lib/features/reader_v2/features/` | Reader 功能 UI：menu（頂/底欄）、settings（設定面板）、tts（TTS 控制）、bookmark（書籤）、auto_page（自動翻頁）、replace_rule（替換規則） |

測試：`test/features/reader_v2/`（8 個測試檔案，涵蓋 content_transformer、layout_engine、page_shell、runtime、viewport、settings_controller）

## 依賴與影響

- **上游**：下載與快取（ChapterContentPreparationPipeline、ReaderChapterContentStorage 提供章節內容）、書架（書籍資料與閱讀進度）、設定（SettingsProvider 提供字體/主題/TTS 設定）
- **下游**：書架（更新閱讀進度、書籤）、設定與備份（讀取 TTS 設定）
- **事件**：監聽 `ttsProgress`、`aloudState`、`updateReadActionBar`、`upConfig`；發出 `upBookshelf`（進度更新）（見 [event_bus](event_bus.md)）
- **服務**：TTSService（GetIt singleton）、AppEventBus、SettingsProvider、ReplaceRule

## 關鍵流程

**章節載入流程**：
```
ReaderV2Page（shell）→ Application Coordinator
  → content/ → ChapterContentPreparationPipeline（跨模組）
    → ReaderChapterContentStorage（磁碟快取）
    → 或 WebBookService（從書源抓取）
  → 轉換後交給 layout/（排版計算）
  → render/（渲染到 Canvas tile）
```

**使用者翻頁流程**：
```
使用者手勢（viewport/）
  → runtime/（更新位置狀態）
  → render/（觸發重繪或 tile swap）
  → 預讀排程（runtime/）→ content/ 預取下一章
```

**TTS 流程**：
```
features/tts/ UI
  → TTSService（core/services/tts_service.dart）
  → flutter_tts / audio_service / just_audio
  → 發 ttsProgress 事件 → runtime/ 高亮對應文字
```

**閱讀器換源流程**（書架的書，2026-06）：
```
底部選單「換源」（reader_v2_bottom_menu.dart，僅網路書 !book.isLocal）
  → ReaderV2Page._showChangeSource → showModalBottomSheet
    → ChangeSourceSheet（複用詳情頁清單 UI；參數化 onSelectSource 回呼）
      → BookDetailChangeSourceProvider 並行 preciseSearch 其他源
  → 使用者選源 → SourceSwitchService.resolveSwitch（對齊目前章節 + clamp + 驗證目標可讀）
    → persistSwitch（遷移到新 bookUrl 時刪舊 row/章節，upsert 新 book + 章節）
    → flushProgress → AppEventBus.upBookshelf
    → Navigator.pushReplacement(BookOpenRoute(migratedBook, chapters, resume))
       以新源在「對齊後章節」完整重建 runtime
失敗（任何 StateError/例外）→ 提示「換源失敗」，不 pop、不動 runtime，完整停留原源。
```
- ReaderV2 的 `book`/runtime 為深度不可變（final），換源採 pushReplacement 整頁重開，而非 live-swap runtime（最低風險）。
- 詳情頁換源行為不變：`ChangeSourceSheet` 不傳 `onSelectSource` 時沿用 `BookDetailProvider.changeSource`。

## 常見修改入口

- 排版問題（行距、字體、頁邊距）→ `lib/features/reader_v2/layout/`
- 渲染效能問題 → `lib/features/reader_v2/render/`
- 翻頁/捲動行為 → `lib/features/reader_v2/viewport/`
- 閱讀器設定 UI → `lib/features/reader_v2/features/settings/`
- TTS 控制 → `lib/features/reader_v2/features/tts/` + `lib/core/services/tts_service.dart`
- 章節內容轉換（清洗、替換規則）→ `lib/features/reader_v2/content/`
- 換源入口（底部選單「換源」）→ `lib/features/reader_v2/features/menu/reader_v2_bottom_menu.dart`（選單項） + `lib/features/reader_v2/shell/reader_v2_page.dart`（`_showChangeSource` 流程）

## 修改路線

- 修改 layout 計算：render/ 依賴 layout 輸出（PageSpec、LineBox）；修改後必須執行 `test/features/reader_v2/reader_v2_layout_engine_test.dart` 和 `reader_v2_viewport_test.dart`
- 修改 runtime 狀態機：Coordinator 和 Session facade 依賴 runtime；進度更新會同步到書架（ReadRecord）
- 修改 content 載入：涉及 ChapterContentPreparationPipeline（下載與快取模組）和 ReaderChapterContentStorage；修改後測試 `reader_v2_content_transformer_test.dart`
- 修改 TTS：TTSService 在 GetIt 中是 singleton，同時供 audio_service 使用；修改需同步 `tts_service.dart` 和 `audio_handler.dart`

## Known Risks

- Tile-based rendering 的 page cache 有記憶體壓力；大字體或超長章節可能觸發 OOM
- 捲動/滑動的手勢識別與 Flutter 手勢系統有衝突點，邊界情況（快速連點、多指）容易出現問題
- TTS 的 `audio_service` 需要系統音訊焦點；背景音樂衝突只有在真機上才能可靠重現
- `runtime/` 的預讀排程與網路請求非同步；章節內容快取失效 + 網路慢時容易出現空白頁閃爍
- ReaderV2 的 Session facade 隔離了閱讀狀態，但關閉閱讀器時的狀態持久化（ReadRecord 寫入）有延遲，可能丟失最後幾頁的進度

## Reference Notes

None（standalone 模式）

## Do Not Do

- 不要在 layout/ 或 render/ 中直接呼叫網路 API（只能透過 content/ 層）
- 不要把 Legado 的漫畫翻頁器（翻頁動畫 > 2 種）移植進來
- 不要跳過 Session facade 直接操作 runtime 狀態（破壞狀態隔離）
- 不要在 tile painter 中做同步 I/O
