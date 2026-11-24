PLAN.md：背景工作在頁面轉場的空檔被別件搶先時照樣跑

- [x] 查清每個登記背景工作的入口（表在下面）
- [ ] 計畫交 Codex 挑毛病（plan 技能，高風險）
- [ ] 先寫會紅的測試：每個入口「按下去後、開始前另一件登記了」只有一件在跑、通知控制在跑的那件
- [ ] 共用那層加「佔位置」：`BackgroundWork` 佔著不送通知；`RepairRuns.adopt` 新工作當場佔；`start()` 才送通知、要權限、開始重的工作
- [ ] `RepairRun._launch` 看 `begin` 的結果；頁面在推入動畫播完前關掉時，頁面拆掉後開始
- [ ] 校驗書源：按下去先佔位置，佔不到不結束暫停中的那次；途中出錯放掉位置
- [ ] 量 `source_manager`、`search` 的幀預算前後
- [ ] 改 `docs/state-machines.md`「背景工作的生命週期」：階段表「未開始」那列與入口表
- [ ] 收尾：Codex 審查、PR、CI、合併、刪 PLAN.md 那一條與本檔

## 入口表（改前，`beta` `5085dc92`）

| 入口 | 什麼時候看位置 | 什麼時候登記 | 登記失敗時 |
|---|---|---|---|
| 單一書源 AI 修復 `ai_repair_page.dart` `openAiRepair` | 按下去、讀完 AI 設定再看一次 | 推頁，推入動畫播完 `RepairRun.start()` | 沒處理：`_launch` 不看 `begin` 的回傳，照跑，兩件同時 |
| 修復異常書源 `source_repair_page.dart` `openSourceRepair` | 同上 | 同上 | 同上 |
| AI 建立書源 `ai_create_source_page.dart` `_start` | 讀設定、問同網站之後 | `pushReplacement` 後推入動畫播完 | 同上 |
| AI 找書 `ai_find_page.dart` `_start` | 讀設定後；之後還有存偏好的 await 才 adopt | 下一幀 start | 同上 |
| 放到背景的搜尋 `search_provider.dart` `moveToBackground` | 按下去當下 | 同一段同步程式 | 不會失敗 |
| 校驗書源（全部、選中）`source_manager_provider.dart` | 只有選單灰不灰 | 存設定、`pausedCheck.end()` 之後才 `SourceCheckJob.run()` 第一行 | 不開始、不說；暫停中的那次已被結束 |
| 繼續暫停的校驗 | 按下去當下 | 同步 | 不會失敗 |
| 繼續暫停的修復、找書、搜尋（含開 App 讀回的）`RepairRun.resume` | 讀回存檔後再看 | 看完同步 `_launch` | 不會失敗 |
| 自動換源 `auto_source_switch.dart` | — | `beginAfterCurrent` | 排在後面（ADR 0069） |
