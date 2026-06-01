---
name: night-reader-atlas
description: "Codebase Atlas entrypoint for 夜讀 Night Reader — reads the atlas index and routes before acting."
---

# 夜讀 Night Reader Codebase Atlas

這是這個專案日常操作的入口技能。

## 使用方式

1. 保留使用者的原始請求。
2. 開啟 `../../../docs/night_reader_index.md` 並在任何操作之前先讀取索引。
3. 用一句平易近人的話確認這個專案做什麼。
4. 根據意圖路由：
   - 使用者想**知道**某件事 — 解釋、定位、可行性評估、所有權、行為確認、審查、重現、效能分析、CI 失敗、風險評估 → 遵循 `../../../docs/night_reader_investigate_workflow.md`。
   - 使用者想**修改**某件事 — 任何程式碼修改 → 遵循 `../../../docs/night_reader_change_workflow.md`。
   - 混合或不明確 → 從理解開始，再決定是否需要修改。
5. 組合工作流程時，將前一個的結論帶入下一個；除非下一步需要尚未收集的脈絡，否則不要重新讀取索引或模組文件。
6. 對任何編輯檔案的操作，提供之前 / 之後並等待使用者明確確認後再編輯。
7. 依此交付策略完成：no commit（只寫檔案，使用者自行 commit）
8. 任務完成後，用平易近人的語言詢問是否還有其他需要處理的事。如果使用者繼續，路由下一個請求時不需重新讀取索引。

## 報告

- 之前 / 之後是唯一的人工確認介面。
- 報告詳細度：technical（技術詳情）
  - 技術詳情：在使用者面向的報告中包含模組名稱、檔案路徑和相關程式脈絡。

## 禁止事項

- 除非使用者明確要求完整重建，否則不要重新執行 Codebase Atlas 初始化。
- 不要略過讀取 atlas 索引。
- 不要在使用者確認之前 / 之後之前編輯檔案。
