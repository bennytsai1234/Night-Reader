# Hybrid Reader 穩定性修復

日期：2026-07-10｜層級：T2（stateful、效能熱路徑、Reader V2 回歸重點）

## Before

- hybrid capture 以 `LineMetrics` 行頂保存視覺位移，restore 卻以 `TextBox.top` 還原；回歸測試重現關閉／重開後 `6.75 logical px` 誤差。
- 每次 hybrid 進度發布都讓 `ReaderV2Page` 整頁 `setState`，拖動期間反覆重建閱讀主面。
- late block 若落入 visible+cache 範圍會被 admission 永久拒絕，精確內容即使已就緒仍可能撞到目前的人工 extent。

## After

- capture/restore 共用 `ui.TextBox.top` 幾何；同一裝置、相同內容與排版設定的 round-trip 測試誤差不超過 `0.01 logical px`。
- `HybridProgressSnapshot` 依章序與 0.1% 顯示值去重，資訊列以局部 `ValueListenableBuilder` 更新；移除 `ReaderV2Page` 的頁級 progress listener。
- normal admission 仍在 visible+cache 外；late exact edge 可在實際 visible 外恢復，並以 debug assert 保證所有既有 block 的 `topOf` 完全不變。
- 保留現行方案 B 模組邊界；未實作 Hybrid V2.1 的全書 runway、虛擬 extent 或速度預測排程。

## 變更檔案

- `hybrid_reader_screen.dart`：統一 capture/restore text-box 幾何。
- `hybrid_contracts.dart`、`reader_v2_page.dart`、`reader_v2_page_shell.dart`：進度顯示去重與局部重建。
- `admission_controller.dart`：late exact edge 安全恢復與座標不變斷言。
- `test/features/reader_v2/hybrid/*`、`reader_v2_page_shell_test.dart`：位置、雙向 admission、visible 保護、進度去重及局部重建回歸測試。
- `docs/night_reader/reader.md`：同步修正 admission 與錨點幾何紀律。

## 驗證

- `dart format`：完成。
- `flutter analyze`：No issues found。
- `flutter test test/features/reader_v2/hybrid test/features/reader_v2/reader_v2_page_shell_test.dart`：35 passed。
- `flutter test`：683 passed。
- 120Hz 真機 p99 不在本機 widget 測試可驗證範圍，仍需 profile APK／device 驗收。

## 交付

- no commit；由使用者審查後自行提交。
