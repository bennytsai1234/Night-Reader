# AI 修復實跑

用真的書源與使用者的 AI 服務跑 AI 修復，照結果改 AI 修復的工具、提示詞或迴圈（`agent-harness` 技能的「評估、迭代」）。

## 案件集

`test/live/ai_repair_cases.json` 列每件書源的預期答案（`fixed` 修得好、`unfixable` 書源本身修不了、`unknown` 還沒定）與證據。預期答案要有 AI 修復以外的證據（curl 打網站、網站本身的行為），不拿 AI 修復自己的判定當答案；寫好請使用者確認，`confirmed` 改成 true。書源 JSON 是使用者的資料，不進 repo：整份匯出檔放在主資料夾的 `.local/ai-repair/export_589_sources.json`，跑的時候照名稱與網址挑。

## 一輪怎麼跑

1. 跑整個案件集：`NR_SOURCES` 給匯出檔、`NR_CASES` 給案件集（測試檔頭有寫），跑完印出每件預期與實際、對或錯。只查一件時，把那件單獨存成 JSON 陣列給 `NR_SOURCES`、不給 `NR_CASES`。匯出檔要更新時從手機拿（`docs/agents/phone.md`「書源原文」）。
2. 金鑰固定放在主資料夾的 `.local/ai-repair.key`（`C:\Users\benny\Desktop\Folder\projects\Night-Reader\.local\ai-repair.key`，git 忽略、不上傳，worktree 也讀這一份）。已經有就直接用；沒有或服務回金鑰不對時，用 `request_secret`（`delivery: "file"`）跟使用者要，存到這裡，不刪。
3. 跑 `test/live/source_repair_batch_live_test.dart`，跑法與環境變數寫在它的檔頭；要跑幾分鐘，所以放背景。使用者 2026-11-12 定的服務：`NR_AI_URL=https://opencode.ai/inference/go/openai/v1`、`NR_AI_MODEL=deepseek-v4.1-flash`、`NR_AI_EFFORT=low`。
4. 讀結果檔（`NR_OUT`）與最後印出的完整修復紀錄。紀錄裡找每一輪的「讀不懂」、重複的指令、失控與校驗沒過，打開那幾輪 AI 實際回的話。

## 怎麼回報

只講這一件從起點到終點，不逐輪列：

- **結論**：修好了沒有，幾輪、多少 token、多久。
- **修好了**：列出拖慢的地方（讀不懂的輪、繞遠路、重抓同一頁），每項附輪數，再提出讓下次少走這幾輪的改法。
- **沒修好**：先分清是哪一種，附紀錄裡的證據：
  - **書源本身修不了**：網站不在、要登入或付費、網站功能本身壞了（例如搜尋只回首頁）。這種就換下一個書源。
  - **修得好卻失敗**：網站正常、答案找得到，是模型失控、工具缺了或回錯、提示詞誤導。查出卡在哪一步，提出工具、提示詞或迴圈怎麼改，模型才走得到終點。
- 校驗判「修好了」也要核對：改過的規則有沒有弄壞別段（例如發現頁沒有自己的書單規則時借用搜尋規則）。

改法列給使用者挑，挑了才改；改完提交，再跑下一個書源。
