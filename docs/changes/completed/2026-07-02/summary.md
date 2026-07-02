# 2026-07-02 完成變更摘要

- [reader-incremental-layout.md](reader-incremental-layout.md) — Reader V2 排版最小單位從「整章」改成「可續跑區塊」：`ReaderV2LayoutEngine` 新增 `layoutStep`/游標可從中途繼續排；`ReaderV2Resolver` 快取改為可部分就緒（`ensureLayoutAtLeast`），並修正 `nextPageSync`/`prevPageSync` 誤把「本章未排完」當「章節結尾」的問題；`ReaderV2PreloadScheduler` 背景排版改為多章節輪流推進而非依序整章排完；`ReaderV2ChapterPageCacheManager` 視窗建置改用「至少要這麼多」且遇未完成章節即停止擴張，並訂閱排版進度通知讓背景推進即時反映到畫面。等待時間上界從「正比於章節總長度」變成「正比於視窗實際需求」。新增 4 個測試檔涵蓋此區之前完全沒有單元測試的 Resolver/PreloadScheduler/ChapterPageCacheManager。全專案 `flutter analyze`（0 issue）與 `flutter test`（636 passed）皆過。
