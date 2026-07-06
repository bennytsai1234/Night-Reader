# 2026-07-06 工作摘要

- [splash-art-handoff](splash-art-handoff.md) — 原生 splash 去圖標（Android 12+ 純深棕），全螢幕夜空藝術圖改由 Flutter 首幀轉場層顯示，撐到書架載完淡出交棒。
- [reader-v2-jump-partial-center-overlap](reader-v2-jump-partial-center-overlap.md) — 修章節跳轉後文字重疊：部分就緒的中心章維持前向邊界、不掛下一章，重錨不再誤判往上長；附回歸測試。
- [release-v0.2.124](release-v0.2.124.md) — 發布版本 v0.2.124 (版本號 0.2.124+138)，將 splash 改動與文字重疊修復發布。
- [splash-seamless-reveal](splash-seamless-reveal.md) — 啟動轉場重設計：底色統一為藝術圖天空的深紫 `#261940`，藝術圖改淡入＋微縮放浮現，消除棕色→夜空圖的硬切割裂感。
- [reader-v2-strip-hardening](reader-v2-strip-hardening.md) — strip 收尾三件組：placeWindowInStrip 改用即時 extent（修過期快照重疊）、加部分就緒章節不變量 assert、刪 placeCenterIfAbsent 死碼；附回歸測試。
- [reader-v2-backward-lock](reader-v2-backward-lock.md) — 往上鎖定：上一章沒排完不掛假尾巴（消除往上滑看到假章尾、內容位移），排完自動通知補掛且零位移；反向排版方案評估後否決，記入 reader 模組 Known Risks。
