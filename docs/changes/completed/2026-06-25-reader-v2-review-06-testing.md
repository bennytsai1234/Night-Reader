# 06 — 測試

> 範圍：Reader V2 模組的測試覆蓋問題。共 4 條。

## T1【中】Layout engine 測試覆蓋不足 — ★Top 5 配套

- **位置**：`test/features/reader_v2/reader_v2_layout_engine_test.dart` 只 108 行
- **Tier**：T1（核心排版需高覆蓋）
- **問題**：核心排版引擎只 108 行，對中文、英文、混合、標點禁則、超長行、空章節、單字元章節、純標點等邊界無專門 case。配合子報告 03 C7（英文單字切斷）優先處理。
- **改善方向**：每邊界類別至少 3 case；加 property-based test（隨機文字 → layout → page 應包含所有 lines 且不重疊、行不溢出）。
- **驗證**：新測試覆蓋上述邊界；隨機文字 property test 紅燈時能精準定位 regression。

## T2【中】無 TTS 跨章推進、進度還原整合測試

- **位置**：目前無
- **Tier**：T1（release 重點：TTS / 進度）
- **問題**：無 TTS 跨章推進測試、無「閱讀→離開→回開」進度還原測試。配合子報告 03 C2/C3 處理 TTS 跨章節，但無測試守護。
- **改善方向**：
  - 整合測試 1：`TTS speak → onComplete → 跨章 → highlight 對齊`，驗 visualOffset 與 line.top 一致。
  - 整合測試 2：`scroll → saveProgress → cold restart → restoreFromLocation`，驗還原位置誤差 ≤ 1 行。
- **驗證**：兩條整合測試紅燈時能反映 TTS／進度 regression。

## T3【低】多個子模組缺獨立測試

- **位置**：無以下獨立測試
  - `runtime/reader_v2_preload_scheduler.dart`
  - `runtime/reader_v2_resolver.dart`（inflight / stale generation / retain）
  - `viewport/reader_v2_chapter_page_cache_manager.dart`（evict / soft retain / revision）
  - `runtime/reader_v2_progress_controller.dart`（debounce、flush chain）
  - `features/tts/reader_v2_tts_controller.dart`（segment 切分、跨章推進、generation cancel）
  - `features/auto_page/reader_v2_auto_page_controller.dart`
  - `render/reader_v2_tile_painter.dart`（golden）
  - `content/reader_v2_chapter_repository.dart`（MockDAO）
- **Tier**：T1
- **問題**：以上子模組皆無獨立測試，問題/重構風險高。
- **改善方向**：補上述子模組獨立測試；`tile_painter` 加 golden test。
- **驗證**：每個子模組有核心 case；golden test 守住視覺 regression。

## T4【低】reader_v2_page_tap_test 過淺

- **位置**：`test/features/reader_v2/reader_v2_page_tap_test.dart` 只 156 行
- **Tier**：T0
- **問題**：未覆蓋 `_handleControllerChanged`、`_drainRuntimeNotice`、換源流程、exit coordinator。
- **改善方向**：擴充 page 整合測試涵蓋 exit flow、change source、notice drain。
- **驗證**：換源／離開／notice 流程有測試守護。