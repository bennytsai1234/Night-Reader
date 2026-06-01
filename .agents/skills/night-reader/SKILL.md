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
   - 使用者想**知道**某件事 → 遵循 `../../../docs/night_reader_investigate_workflow.md`。
   - 使用者想**修改**某件事 → 遵循 `../../../docs/night_reader_change_workflow.md`。
   - 混合或不明確 → 從理解開始，再決定是否需要修改。
5. 組合時將前一工作流程的結論帶入下一個，不要重新讀取索引。
6. 對任何編輯檔案的操作，提供之前 / 之後並等待使用者明確確認。
7. 交付策略：no commit（只寫檔案，使用者自行 commit）
8. 任務完成後詢問是否還有其他需要處理的事。

## 禁止事項

- 不要略過讀取 atlas 索引。
- 不要在使用者確認之前 / 之後之前編輯檔案。
- 不要重新執行 Codebase Atlas 初始化（除非使用者明確要求）。
