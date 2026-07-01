# 2026-07-01 完成變更摘要

- [reader-open-scroll-layout-yield.md](reader-open-scroll-layout-yield.md) — 排版引擎 `ReaderV2LayoutEngine.layout()` 改為分批讓出主執行緒，緩解開書首屏與滑動撞未預載章節時的同步排版卡頓；不改排版演算法/結果。
