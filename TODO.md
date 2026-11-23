PLAN.md：AI 服務相容各家的工具呼叫與思考送回（提案 `docs/proposals/ai-provider-compat.md`）

- [x] 不送 tool_choice，系統提示寫明每輪呼叫工具、只用交出或放棄結束；改 ADR 0054
- [x] 工具呼叫的額外欄位、OpenRouter 的完整思考資料原樣存、原樣送回（含存檔與續跑）
- [x] 串流工具呼叫照 OpenAI 官方套件的方式拼
- [x] 測試連線第二步帶工具清單
- [x] OpenAI 官方改走 Responses 介面
- [x] 對話帶過思考時每則 AI 回覆都送思考欄位
- [x] 看書架不送參數格式、改書源的內容列出欄位
- [x] 模擬各家服務的測試；OpenCode Go 實跑
- [ ] 收尾
