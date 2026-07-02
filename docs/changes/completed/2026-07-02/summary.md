# 2026-07-02

- Reader V2 架構目錄改為 screen / session / use_cases / chapter / layout / render / viewport / features，並同步更新 import 與 atlas 文件。
- Reader V2 新增 state machine 與 operation token，集中 open/jump/restore/presentation/contentReload 的 phase 與過期操作檢查。
- Reader V2 state machine 完成剩餘 session mutation 收斂，涵蓋 restore-in-progress、visible/committed location、page window 與 notice-only 通知。
- [reader-v2-session-core-refactor](reader-v2-session-core-refactor.md) — Reader V2 底層重構：修復 11 個 session/viewport BUG（預載 waiter 洩漏、背景排版不重繪、部分就緒章節頁面重疊、fallback 翻頁不保存進度等），移除可繞過 state machine 的 runtime API，新增 5 個壓力測試檔；`flutter analyze` 無警告、`flutter test` 655 測試全綠。
