# 2026-06-30 變更摘要

- [無縫品牌開啟方案](splash-seamless-open.md) — 開啟流程（點圖示→動畫→書架）圖示接力一致化、中央展開動線、時序壓短至 ~1.25s、退場改單段純淡入；v31 splash 圖示底色對齊深棕。本機無 Flutter SDK，analyze/test 未執行（已人工複查）。
- [ReaderV2 重構：移除 Slide、拆分 Runtime](2026-06-30-reader-v2-remove-slide-split.md) — **P1 ✅ P2 ✅ P3 ✅**：移除 slide viewport 固定 scroll（`0b85122`）；拆分 Runtime 為 NavigationController + ViewportBridge（`9cdd60a`）；P3 已由 [Split ScrollReaderV2Viewport](split-scroll-reader-v2-viewport.md) 完成。
- [Split ScrollReaderV2Viewport](split-scroll-reader-v2-viewport.md) — 拆分 viewport model、motion controller、command queue、canvas widgets 與 visible line helper；保留既有 public API。release 前一併清理 bookshelf reorder analyzer deprecated info 與 Windows importScript 測試 path 轉義；`flutter analyze`、`flutter test` 通過。
