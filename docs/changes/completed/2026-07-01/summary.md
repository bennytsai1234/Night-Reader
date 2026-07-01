# 2026-07-01 完成變更摘要

- [reader-open-scroll-layout-yield.md](reader-open-scroll-layout-yield.md) — 排版引擎 `ReaderV2LayoutEngine.layout()` 改為分批讓出主執行緒，緩解開書首屏與滑動撞未預載章節時的同步排版卡頓；不改排版演算法/結果。
- [quickjs-windows-test-detection.md](quickjs-windows-test-detection.md) — 修正 `test/test_helper.dart` 對非 Linux 平台「假設 QuickJS 可用」的錯誤判斷，補上 Windows `.dll` 偵測，讓 `analyze_rule_test.dart` 的 JS 規則測試能在本機實際跑過。
- [scroll-shift-threshold-velocity.md](scroll-shift-threshold-velocity.md) — 滑動視窗提前擴張門檻不再依速度縮放（拖曳中恆為 0、減速尾聲會收斂），一律用最大提前量，緩解慢滑/減速時卡頓。
- [scroll-window-eviction-decouple.md](scroll-window-eviction-decouple.md) — 滑動視窗重新置中時不再把 Resolver 的 50 章排版快取強制砍到只剩窗口大小，修正「捲幾章再捲回去又要重排一次」。
