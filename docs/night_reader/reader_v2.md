# 閱讀器 V2

## 現有責任

閱讀頁面的全部功能：自製排版引擎（分頁計算、字型度量、行距段距）、Canvas 渲染、viewport（捲動 / 左右滑動）、runtime（閱讀狀態機、位置追蹤、預載排程）、TTS 朗讀（highlight、音訊控制）、設定面板、書籤、章節替換規則、自動翻頁、選單（上下選單列）。是專案中最複雜的模組，也是 release 的重點回歸區域。

## 範圍

- **Application 層**：`lib/features/reader_v2/application/`（controller host、coordinators、session facade、dependencies）
- **排版引擎**：`lib/features/reader_v2/layout/`（layout engine、spec、style、typography、constants）
- **渲染層**：`lib/features/reader_v2/render/`（render page、tile layer/painter、line box、TTS highlight overlay、page cache）
- **Viewport**：`lib/features/reader_v2/viewport/`（scroll / slide viewport、screen、position tracker、infinite segment strip、pointer tap layer、visible page calculator、chapter page cache manager）
- **Runtime**：`lib/features/reader_v2/runtime/`（runtime、state、location、resolver、open target、page window、preload scheduler、progress controller、performance metrics）
- **Content**：`lib/features/reader_v2/content/`（chapter repository、content、content transformer、processed chapter）
- **功能面板**：`lib/features/reader_v2/features/`（auto_page、bookmark、menu、replace_rule、settings、tts）
- **Shell**：`lib/features/reader_v2/shell/`（reader page、page shell、chapters drawer）
- **Settings 持久化**：`lib/features/reader_v2/features/settings/reader_v2_prefs_repository.dart`
- **測試**：`test/features/reader_v2/`

## 依賴與下游影響

- 上游：**應用基礎設施**（DAO：chapter、bookmark、read_record）、**下載與快取**（chapter content pipeline，提供已快取章節內容）、**規則引擎**（網路書源章節正文抓取）
- 下游：`audio_service` / `flutter_tts`（TTS 播放）、`shared_preferences`（閱讀設定持久化）
- 排版引擎改動（layout constants、typography）需在多種字型與螢幕尺寸下確認不破版
- viewport 改動可能影響捲動與滑動兩種模式的觸控行為

## 關鍵流程

1. 開書：`ReaderV2Page` 接收 `ReaderV2OpenTarget` → `ReaderV2SessionFacade` 初始化 runtime → 載入首章內容 → layout engine 分頁 → tile layer 渲染
2. 翻頁（滑動）：`SlideReaderV2Viewport` 手勢 → `ReaderV2ViewportController` → `ReaderV2Runtime` 更新位置 → 觸發預載
3. TTS 朗讀：`ReaderV2TtsController` 驅動 `TtsService` → 逐句朗讀 → `ReaderV2TtsHighlight` 更新 highlight overlay
4. 設定變更：`ReaderV2SettingsController` 更新 prefs → 觸發 layout 重算 → 重新渲染

## 變更入口

- 排版/字型問題：`lib/features/reader_v2/layout/reader_v2_layout_engine.dart`、`reader_v2_typography.dart`
- 翻頁/手勢問題：`lib/features/reader_v2/viewport/`
- TTS 問題：`lib/features/reader_v2/features/tts/`
- 章節切換/預載問題：`lib/features/reader_v2/runtime/`、`content/`
- UI 選單/設定面板：`lib/features/reader_v2/features/menu/`、`features/settings/`

## 變更路由

- 修改排版規格：`reader_v2_layout_spec.dart` → `reader_v2_layout_engine.dart` → `test/features/reader_v2/reader_v2_layout_engine_test.dart`
- 修改 viewport/滑動行為：對應 viewport 檔案 → `test/features/reader_v2/reader_v2_viewport_test.dart`、`reader_v2_viewport_stress_test.dart`
- 修改 runtime 狀態機：`reader_v2_runtime.dart` → `test/features/reader_v2/reader_v2_runtime_test.dart`
- 修改 content 轉換：`reader_v2_content_transformer.dart` → `test/features/reader_v2/reader_v2_content_transformer_test.dart`

## 已知風險

- Canvas tile 渲染依賴字型度量，不同 Android 裝置的字型可能有細微差異，難以在測試中全面覆蓋
- 捲動與滑動兩種 viewport 維護的狀態有差異，切換模式時需要小心位置同步
- TTS highlight 與渲染 overlay 的同步依賴 stream 與 post-frame callback，有輕微的 async 時序風險
- `ReaderV2InfiniteSegmentStrip` 的無限滾動段落管理在極長書籍時的記憶體上限未完整測試

## 參考備註

無（Standalone 模式）

## 禁止事項

- 不要在 reader_v2 內直接呼叫書源服務；章節內容應透過 content repository 取得
- 不要在排版引擎層做 I/O；layout 是純計算層
- 不要將 TTS 狀態洩漏到 runtime state；TTS 有獨立的 controller
