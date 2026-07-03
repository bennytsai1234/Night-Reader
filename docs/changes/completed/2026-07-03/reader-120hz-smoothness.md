# Reader 120Hz 滾動絲滑度修復

## 症狀

使用者回報：App 在 120Hz 裝置上滾動不夠絲滑。

## 診斷（已確認的事實）

1. **App 從未要求高刷新率**：`MainActivity.kt` 只是空殼（`AudioServiceActivity`），Dart 層與原生層都沒有設定 `preferredDisplayModeId`，repo 內完全沒有 displaymode / refreshRate 相關程式碼。多數 Android OEM（小米、OPPO、vivo、一加等）預設把未宣告的 app 鎖在 60Hz，所以 App 很可能根本沒跑在 120Hz。
2. **排版 yield 預算為固定 8ms**（`reader_v2_layout_engine.dart` `_layoutYieldBudget`）：排版在 UI isolate 上分片執行，每片最多佔用 8ms 才讓出。60Hz 幀預算 16.6ms 下可以與一幀共存；120Hz 幀預算只有 8.3ms，滾動中跨章觸發的 layout step 每一片都會吃掉整幀 → 必然掉幀。
3. **未啟用 pointer resampling**：輸入事件率與顯示刷新率不同步時（高刷裝置常見），拖曳位移逐幀不均勻。Flutter 提供 `GestureBinding.resamplingEnabled` 將輸入對齊 vsync。

次要觀察（本次不動）：動作中每 200ms 的 runtime notify 造成 page shell 整體 rebuild；`animationShiftThrottleEveryTicks = 2` 在 120Hz 下 capture 頻率翻倍。影響相對小，若真機驗證仍不足再處理。

## 變更

1. `android/app/src/main/kotlin/com/inkpage/reader/MainActivity.kt`：`onCreate` 中選擇與目前解析度相同、刷新率最高的 display mode 設為 `preferredDisplayModeId`（minSdk 24 ≥ API 23，API 恆可用；以 try/catch 包護）。
2. `lib/features/reader_v2/layout/reader_v2_layout_engine.dart`：`_layoutYieldBudget` 由常數改為依 `PlatformDispatcher` 回報的顯示刷新率動態計算，取半個幀預算（120Hz→約 4.2ms；60Hz→約 8.3ms，與現行 8ms 行為幾乎一致）。yield 機制本身（`Future.delayed(Duration.zero)`）不動，避免與測試的 frame pump 互動出問題。
3. `lib/main.dart`：`ensureInitialized` 後啟用 `GestureBinding.instance.resamplingEnabled = true`。

## 驗證

- `flutter analyze`、`flutter test`。
- Kotlin 變更本機無 Android SDK 無法編譯，由 CI（Android Release workflow）把關；程式碼為標準 API 用法並以 try/catch 包護。
- 真機絲滑度需使用者以 120Hz 裝置實測（可用開發者選項的「顯示刷新率」浮層確認 App 是否真的跑 120Hz）。

## 風險

- 排版切片變短 → 單章排完所需的讓出次數變多，背景排版總時長略增；換得滾動中不佔滿幀。
- resampling 引入約 5.5ms 取樣位移，屬 Flutter 官方建議做法，感知延遲可忽略。
