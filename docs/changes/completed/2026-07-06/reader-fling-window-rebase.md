# Reader V2 fling window rebase

## Before

滾動減速時仍可能跳動。已知 strip 座標補償會同步調整 `readingY`，但
`_ensureWindowAround()` 在 active fling 期間換完章節 window 後，仍會把
`readingY` 套到 `_motion.scrollAnimationValue`。如果 window 載入/換錨等待期間
動畫模擬值已跑到目前畫面前方，減速末段會用累積值硬拉一次，形成可見跳動。

## After

換完 window 後不再追套累積動畫值；改為把 active fling 重新以目前 `readingY`
為起點續跑，只保留當下速度。這讓減速手感延續，但不補吃等待期間累積的位移。

## Verification

- 新增 `test/features/reader_v2/scroll_reader_v2_motion_controller_test.dart`
  覆蓋 active fling rebase 不得瞬間追套等待期間累積的舊動畫值。
- `flutter test test/features/reader_v2/scroll_reader_v2_motion_controller_test.dart`
  — passed。
- `flutter test test/features/reader_v2/reader_v2_viewport_repaint_test.dart --plain-name "甩動減速期間 runtime notify 受節流約束，settle 後進度落地"`
  — passed。
- `flutter analyze` — No issues found。
- `flutter test` — 665 passed / 4 skipped。

註：Flutter test 在此 Windows/公司代理環境需對單次命令設定
`NO_PROXY/no_proxy=localhost,127.0.0.1,::1`，否則測試 listener 連線
`127.0.0.1` 會被代理攔截為 WebSocket 502；未修改任何全域設定。
