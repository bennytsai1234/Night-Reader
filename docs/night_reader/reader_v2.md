# 閱讀器 V2

## 職責

擁有自製的小說閱讀器渲染引擎，包含版面佈局計算、文字渲染、視埠管理、頁面快取、執行時期狀態、以及使用者介面殼層。這是 App 的核心體驗模組。

## 範圍

- `lib/features/reader_v2/shell/` — 閱讀器頁面殼層
  - `reader_v2_page.dart` — 閱讀器主頁面（約 17KB）
  - `reader_v2_page_shell.dart` — 頁面外殼與互動（約 12KB）
  - `reader_v2_chapters_drawer.dart` — 章節抽屜
- `lib/features/reader_v2/layout/` — 版面佈局
  - `reader_v2_layout_engine.dart` — 佈局引擎（約 19KB，核心排版邏輯）
  - `reader_v2_layout.dart` — 佈局資料結構
  - `reader_v2_layout_constants.dart` — 佈局常數
  - `reader_v2_layout_spec.dart` — 佈局規格
  - `reader_v2_style.dart` — 文字樣式
  - `reader_v2_typography.dart` — 排版設定
- `lib/features/reader_v2/render/` — 渲染層
  - `reader_v2_render_page.dart` — 渲染頁面（約 17KB）
  - `reader_v2_tile_painter.dart` — Tile 繪製器
  - `reader_v2_tile_layer.dart` — Tile 圖層
  - `reader_v2_tile_key.dart` — Tile 鍵值
  - `reader_v2_page_cache.dart` — 頁面快取
  - `reader_v2_text_adapter.dart` — 文字適配器
  - `reader_v2_line_box.dart` — 行框
  - `reader_v2_tts_highlight_overlay_layer.dart` — TTS 朗讀標示層
- `lib/features/reader_v2/viewport/` — 視埠管理
- `lib/features/reader_v2/runtime/` — 執行時期狀態
- `lib/features/reader_v2/content/` — 內容處理
- `lib/features/reader_v2/application/` — 應用層
- `lib/features/reader_v2/features/` — 閱讀器子功能
- `lib/core/engine/reader/chinese_text_converter.dart` — 簡繁轉換

## 依賴與影響

- **上游**：基礎設施、資料庫與模型（書籍、章節、進度）、核心服務（章節內容儲存、TTS 服務）
- **下游**：無（最上層的功能模組，直接面向使用者）
- **外部依賴**：flutter_tts（朗讀標示）

## 關鍵流程

- **開啟書籍**：ReaderV2Page 接收書籍 ID → 載入章節列表 → 載入當前章節內容 → LayoutEngine 計算佈局 → RenderPage 繪製 → 顯示
- **翻頁**：手勢事件 → Viewport 更新 offset → 判斷前後頁 → 預載入鄰近頁 → RenderPage 重繪
- **TTS 朗讀**：TTSService 逐句朗讀 → TTSHighlightOverlayLayer 在渲染層標示當前句子
- **章節切換**：章節抽屜選擇 → 載入新章節內容 → ContentPreparationPipeline 處理 → LayoutEngine 重新佈局

## 變更入口與路線

- **修改排版邏輯**：編輯 `layout/reader_v2_layout_engine.dart`（核心，約 19KB）
- **修改渲染行為**：編輯 `render/reader_v2_render_page.dart` 或 `reader_v2_tile_painter.dart`
- **修改閱讀器 UI**：編輯 `shell/reader_v2_page.dart` 或 `reader_v2_page_shell.dart`
- **新增閱讀器設定**：在 `features/settings/reading_settings_page.dart` 加入 UI，確保對應的樣式參數傳遞到 `reader_v2_style.dart`
- **修改頁面快取策略**：編輯 `render/reader_v2_page_cache.dart`

## 已知風險

- `reader_v2_layout_engine.dart` 是核心排版邏輯，極其複雜，修改需充分測試各種文字內容（中文、英文、標點、換行）
- Tile 快取策略直接影響翻頁流暢度和記憶體使用
- 閱讀器內部的狀態管理（閱讀進度、章節位置）需與書架模組保持同步
- 這是 release 的重點回歸區域，任何修改都應在實機上測試翻頁、章節切換、TTS 朗讀

## 禁止事項

- 不要在閱讀器中直接操作資料庫——透過核心服務取得內容
- 不要在閱讀器中直接發起網路請求——透過核心服務
- 不要修改閱讀器狀態而不更新閱讀進度（會導致書架顯示不同步）
