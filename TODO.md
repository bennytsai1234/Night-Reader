PLAN.md 第二階段：有書源的目錄只抓到 50 章

- [x] 讀 AGENTS.md、PLAN.md、roadmap 第 1、4 項、environment.md、ai-find-runs.md，載入 bug-fix
- [x] 找材料：這台沒有 11-22 的實跑紀錄與書源匯出檔；改從源倉庫下載 601 個書源的合集（id 1340）
- [x] 讀程式：AI 找書讀目錄走 `BookSourceService.getChapterList`（不帶上限），引擎沒有 50 的上限；翻頁邏輯對照 Legado `BookChapterList.kt` 大致一致
- [x] 跑 `test/live/tmp_toc50_live_test.dart`，找出章數卡在一頁量的書源與書
- [x] 同一本書對著 Legado 走一遍，找第一個分岔：沒寫目錄網址規則時夜讀照「目录」連結另找目錄頁，Legado 用詳情頁
- [x] 寫重現測試（紅）
- [x] 修引擎：刪掉猜目錄連結，照 Legado 用詳情頁；跑受影響的測試
- [x] 修好後再實跑一次成對比較（幻影 140、讀趣 135、飛盧 816）
- [ ] 刪掉臨時測試，收尾（Codex 審查、併入最新 beta、PR、CI、合併）
- [ ] 合併後在 `docs/proposals/audit-source-engine.md` 第 10 筆、`legado-sources.md` R10 標題加「（已修，#PR）」，推上 beta
