PLAN.md 第二階段：有書源的目錄只抓到 50 章

- [x] 讀 AGENTS.md、PLAN.md、roadmap 第 1、4 項、environment.md、ai-find-runs.md，載入 bug-fix
- [x] 找材料：這台沒有 11-22 的實跑紀錄與書源匯出檔；改從源倉庫下載 601 個書源的合集（id 1340）
- [x] 讀程式：AI 找書讀目錄走 `BookSourceService.getChapterList`（不帶上限），引擎沒有 50 的上限；翻頁邏輯對照 Legado `BookChapterList.kt` 大致一致
- [ ] 跑 `test/live/tmp_toc50_live_test.dart`，找出章數卡在一頁量的書源與書
- [ ] 同一本書對著 Legado 走一遍，找第一個分岔
- [ ] 照三種結論之一處理（修引擎／記第四階段）
- [ ] 刪掉臨時測試，收尾
