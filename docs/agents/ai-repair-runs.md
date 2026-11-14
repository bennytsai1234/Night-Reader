# AI 修復實跑

用真的書源與使用者的 AI 服務整批跑 AI 修復，照 `agent-harness` 技能第 5 步一輪一輪迭代：抽樣、評過程、歸因、要使用者認定的、終點都照技能；評估表的欄位與回報格式照技能的 `references/evaluation.md`。這裡只寫夜讀的材料、跑法與對應。

## 材料

- **案件集**：`test/live/ai_repair_cases.json`，一件只有 `name` 與 `url`，取自 2026-11-13 手機上整批修復時交給 AI 的 67 件。不附預期答案，評的是過程。
- **書源 JSON**：使用者的資料，不進 repo。整份匯出檔在主資料夾的 `.local/ai-repair/export_589_sources.json`，實跑測試照案件的名稱與網址從裡面挑；要更新時從手機拿（`docs/agents/phone.md`「書源原文」）。
- **金鑰**：主資料夾的 `.local/ai-repair.key`（`C:\Users\benny\Desktop\Folder\projects\Night-Reader\.local\ai-repair.key`），git 忽略，worktree 也讀這一份。已經有就直接用；沒有或服務回金鑰不對時，用 `request_secret`（`delivery: "file"`）跟使用者要，存到這裡。不刪、不上傳、不印出。
- **服務**：使用者 2026-11-12 定的 `NR_AI_URL=https://opencode.ai/inference/go/openai/v1`、`NR_AI_MODEL=deepseek-v4.1-flash`、`NR_AI_EFFORT=low`。實跑用 `NR_AI_CONCURRENCY=6`（App 是 3）：OpenCode Go 官方文件沒寫並行上限，限制是 5 小時、每週、每月的用量額度；出現 429、「無法確認」或每輪等 AI 明顯變長就退回 4。平日台灣時間 09:00–12:00、14:00–18:00 是它的尖峰，要比耗時的兩輪都在非尖峰跑。

## 一輪怎麼跑

1. **整批跑**：`test/live/source_repair_batch_live_test.dart`，跑法與環境變數寫在檔頭；`NR_SOURCES` 給匯出檔、`NR_CASES` 給案件集，加 `FLUTTER_TEST_WALL=0`（`tool/flutter_test.sh` 預設 20 分鐘就停，整批沒跑完結果檔不會寫出來）。67 件、AI 同時修 3 個網站，11/13 那批光等 AI 與跑工具就 221 分鐘，放背景。一個改動只重跑出現過那類問題的件：`NR_ONLY=蜘蛛小说网,🎃涨姿势🎃`，名稱照案件集整個寫（含表情符號），對不上的測試直接停下；同名的會一起跑（饿狼小说有兩件）。
2. **整理成表、抽樣**：測試開頭與結尾都印出完整修復紀錄的資料夾（在暫存資料夾裡）。整個資料夾複製到主資料夾的 `.local/ai-repair/runs/<日期-名稱>/`，再跑 `dart run tool/ai_repair_table.dart <那個資料夾> --out <那個資料夾>/_table.md`：一件一列的評估表，下面是第 5 步的四組抽樣。跟上一輪的表比回合數、耗時、快取命中率。
3. **讀紀錄**：抽到的件逐份讀完。一份紀錄大半是整頁原文，先濾掉再從頭讀：

   ```sh
   awk '/^### 請求與網站回的原文|^### 工具$|^### 送給 AI（system|^### 送給 AI（tool/{skip=1; print; next} /^## |^### /{skip=0} !skip' <紀錄> | grep -v '^\s*$' | sed '/^## 怎麼查/,/^### 送給 AI（user/{/^### 送給 AI（user/!d}'
   ```

   要一輪一輪給使用者看某一件時，`dart run tool/ai_repair_view.dart <紀錄.txt> <輸出.html>` 轉成可以點開的頁面，放進對話。

## 夜讀的對應

照技能第 5 步評過程與歸因時，夜讀的正式系統是書源引擎與校驗，agent 以外的方法是 curl 與 Legado 原始碼：

- **用 curl 核對書源類的結論**，條件照書源實際送的：
  - 搜尋拿站上有的書名和不可能的詞（例如「夜讀查無此書ㄅㄆㄇㄈ」）各搜一次、比結果：夜讀的校驗只看搜得到書，網站不理關鍵字、回固定推薦書也算過。
  - 關鍵字照書源的 `charset` 編碼，GBK 的書源用 GBK 送。
  - 書源開了 Cookie 罐（`enabledCookieJar`），或網站靠工作階段 Cookie 驗證、限流時，curl 用 `-c`／`-b` 把 Cookie 帶著走。
  - 主站的功能壞了時，看書源裡圖片、轉址指到的網域有沒有同一套網站的完整版本。
- **引擎**：AI 寫的規則照 Legado 是對的、夜讀跑出不同的結果時，對照 Legado 原始碼（位置在 `docs/agents/environment.md`），照 Legado 修引擎。
- **親手做一份成品**：照 curl 查到的事實寫一份書源，用 `test/live/source_check_live_test.dart` 跑校驗；修了引擎後，改前改後也用它跑匯出檔裡碰得到的書源，報實際增減。
