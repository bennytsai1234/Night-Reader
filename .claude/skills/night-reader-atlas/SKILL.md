---
name: night-reader-atlas
description: "夜讀 Night Reader 的 Codebase Atlas — 導航地圖、變更紀律與委派，適用於直接與人類交談的 agent。請在開始此專案工作時載入一次；同一對話中勿重複載入。被委派的 subagent 不可載入此 skill——請使用 night-reader-worker。"
---

# 夜讀 Night Reader Codebase Atlas — Lead

直接與使用者交談的 agent 入口。自帶紀律，無須另讀工作流程文件。

## Role check（優先，一律執行）

若你的指令來自其他 agent 的 task contract——prompt 標頭寫有 `ROLE: worker`——**停止閱讀此檔**，改用 `night-reader-worker`。否則你是 lead。

寫入任何 governance 檔案前——`docs/` 下的 atlas 文件、`docs/changes/` 下任何內容、或 Architecture Decisions 列——先回答一次：*我的指令來自人類，還是來自其他 agent 的 task 描述？* 若來自其他 agent，不要寫入；改在回報中向上呈報。

## Entry

1. 保留使用者的原始請求。
2. 讀 `../../../docs/night_reader_index.md` 一次，然後用一句白話確認此專案是做什麼的。
3. 只從索引挑相關模組文件——不要全部讀取。對該區不熟時先 zoom out 看模組地圖再收斂。
4. 依意圖路由：**know**（解釋、定位、可行性、歸屬、行為檢查、review、重現、profile、CI 失敗、風險）→ Investigate；**change**（任何程式碼編輯）→ Change；混合/不明 → 先 investigate 再決定。
5. 結論往下傳；除非需要尚未收集的脈絡，否則不跨步驟重讀索引或模組文件。

## Investigate（唯讀）

從 atlas 加上最少必要程式碼回答；區分確認事實與假設/未知。絕不編輯——若需修正，在使用者同意後交給 Change。依問題性質套用紀律：除錯 = 重現 → 排序假設 → 二分；review = 對著 owning/boundary 模組讀 diff；開放設計問題 = 一次一題訪談、各附推薦答案，比對索引與 Architecture Decisions 表——標記任何與已記錄責任/邊界衝突或重開已錄決策的提案。

## Change（任何編輯）

判斷紀律層級，按層級調整 effort：

- **T0 trivial**（無邏輯變、可逆、單檔）：一行 Before/After；略過 plan 檔；執行單一最相關檢查。
- **T1 normal**（可控、可逆、診斷清楚）：有便宜縫隙時加一個聚焦測試；編輯 source 前寫草稿 plan `docs/changes/planning/{{DATE}}-{{SLUG}}.md`（`{{DATE}}` = 今日本地日期，ISO `YYYY-MM-DD`）。
- **T2 hard/risky**（async/stateful bug、跨模組、外部 API、不可逆、效能迴歸、診斷不明）：完整紀律；同上 plan 檔；通常需 Decision Gate。

**硬底線：** 不可逆、跨模組、外部 API、遷移工作至少 T2。可接受白話的「快一點/仔細一點」覆寫，但永不低於底線。

**Before / After gate**——唯一確認介面，且為 lead only。發生於你與使用者之間，絕不是 agent 對 agent。
- **Before**：現況與為何需要改——針對 bug 需給出已診斷根因——以白話說明。
- **After**：改完會變成什麼，以及如何驗證。

T1/T2 在編輯任何檔案或派遣任何 worker 前等待明確確認。T0（無邏輯變、可逆、單檔）說一行 Before/After 後不等待直接做，做完回報——若 Before 有誤可逆還原。

**Decision Gate**——當變更會改模組邊界、外部 API、是不可逆或遷移，或有兩個以上可行方案時：先查提案是否與索引或 Architecture Decisions 表中已錄者衝突或重開——若是，點名並確認正在重開舊決策。然後提供 Context / Options（A/B 含取捨）/ Recommendation，在 Before/After 前等待選擇。跨模組決策錄入索引的 Architecture Decisions 表；模組層決策錄入該模組的 Known Risks。

一旦使用者確認，決策即為已定。將其濃縮進 worker contract；worker 不得重開。

## Delegate（選擇性——用於邊界清楚、已充分理解的工作）

僅在 Before/After 確認後才委派。當任務比描述它所需的 contract 還小時，自己處理。

發送 contract，而非聊天記錄：

```markdown
---
ROLE: worker
CONTRACT: atlas/v1
TASK_TYPE: implement        # implement | investigate | review
MODEL_TIER: standard        # standard | strong
---

## Goal
<一句話：完成時必須成立的事實>

## Context
<3-5 行 worker 無法自行推導的資訊：已診斷根因、使用者選擇的方案、驅動此工作的限制>

## Read First
- docs/night_reader/<module>.md          # 僅相關的模組文件

## Allowed Paths
- <glob>                              # 編輯此範圍外的檔案即屬越界

## Must Preserve
- <不得變更的邊界/公開 API/contract>

## Forbidden
- <任務特定禁止，疊加在 worker skill 的 baseline 之上>

## Acceptance
- <可執行的指令或可觀察的行為>
- 不得改變的舊行為：<...>

## Verification You May Run
- <僅限範圍內的指令>
<完整建置、完整測試套件、dev server、任何綁定 port 的項目：不執行——回報 verification: deferred-to-lead>

## Stop And Report If
- 根因位於 Allowed Paths 之外。
- 修正需變更 Must Preserve 下的內容。
- 兩個以上可行方案有實質取捨差異。
```

`Must Preserve` 和 `Forbidden` 通常是免費的：從所屬模組文件的 **Do Not Do** 和 **Known Risks** 複製即可。

**Model tier。** `implement` 和 `investigate` 使用 {{MODEL_TIER_STANDARD}}（`MODEL_TIER: standard`）。有具體 `Acceptance` 項目的 bounded contract 幾乎不會從更高推理層級獲益，卻會為每個 token 付費。提升至 {{MODEL_TIER_STRONG}}（`MODEL_TIER: strong`）的兩種情況：`TASK_TYPE: review`，以及 `Stop And Report If` 包含兩個以上開放性判斷的 contract。審查者從不省——弱審查者只會同意它所看到的內容。

**共用資源由你專屬。** 完整專案建置、完整測試套件、dev server 與任何綁定 port 的項目、資料庫與遷移、相依安裝——只有你執行這些，且只有在零 worker 進行中時。停止正在執行的 app 並重建是允許的，條件同上。

**排程。** 僅當 worker 之間的 `Allowed Paths` 互不重疊時才並行派遣。重疊時序列化或重新切割任務。有疑問時序列化。需要完整建置回饋才能迭代的任務單獨執行，或留在你手上。

## Cost discipline

每次派遣都有固定的 cold-start 成本：新 worker 在改任何一行前要先摸索方向。四條規則壓低成本，且不損失任何品質——它們不省略檢查、測試或審查。

**除非 contract 比工作本身便宜，否則自己做。** 派遣前先問：寫 contract 的成本是否超過直接改的成本？變更只有一檔、你已確切知道要改哪幾行、或在套用審查結果時——這些已經定位好了，cold worker 會花成本重新定位。

**一個 worker，更寬的路徑。** 若一個 contract 的 `Allowed Paths` 是另一個的子集，它們就是同一個 contract：合併它們，而非支付兩次 cold start 和兩次 acceptance。按變更邊界拆分，絕不按檔案拆分。

**worker 進行中時，什麼都不做。** 不做 `git status`、不檢視 diff、不回報進度、不預先閱讀。尚未回報的 worker 就是還沒完成——這是你檢查所能得到的全部資訊，而且你已經知道了。輪詢只會讓你看到半完成的程式碼，並用你持續增長的 context 換取這個非答案。等待回報，或等待明確的決策請求。在序列化排程下這個成本最高：你的 context 在整個 run 中不斷增長，所以每一次空轉都比前一次更貴。

**保持 contract 精簡。** 絕不將索引、規格或聊天記錄貼進 contract；`Context` 是三到五行。`Read First` 和 `Allowed Paths` 是阻止 cold worker 把預算燒在探索上的關鍵。

## Accept（驗證 worker 產出）

比對 diff 與 contract：每個 `Acceptance` 項目成立；diff 停留在 `Allowed Paths` 內；`Must Preserve` 下的內容未被更動；修正針對根因而非症狀；未引入特殊 case、hardcoded 值、吞掉的 exception、專為測試存在的 production branch、重複邏輯或弱化的測試；新程式碼不比問題本身複雜；新測試驗證真實行為而非編碼錯誤。

然後執行權威建置與測試套件，加上回報標記為 `deferred-to-lead` 的項目。先單獨執行可自動修復的檢查——formatter、linter、任何有 `--fix` 的項目——套用它們的回報，然後才執行一次合併的建置加測試。把全部放在 `&&` 鏈裡意味著單一個 formatting nit 就會中止整條鏈，而你會為整個套件付兩次費。接受、以修正後的 contract 退回、或重新切割任務。

僅在 T2 或你自己寫了程式碼想獨立審查時才花費獨立的 review subagent——以相同 contract 加上 `TASK_TYPE: review` 和 `MODEL_TIER: strong` 派遣。然後親自套用它發現的問題：它們抵達時已經定位好了，新 worker 只會花成本重新尋找。

## Complete（lead-only 寫入）

在標記變更完成前明確回答：此次變更是否改變了模組邊界、所有權或外部 API/contract？若是，立即在此完成步驟中更新受影響的 atlas 文件——而非後續跟進。僅更新受影響的模組文件與索引項目；不重新掃描不相關的模組。

然後，在 T1/T2 時，將 plan 移至 `docs/changes/completed/{{DATE}}/{{SLUG}}.md`，並在當日 `docs/changes/completed/{{DATE}}/summary.md` 中附加一行，註明 atlas 文件是否已更新或無需更新。記錄決策、與計劃的偏差、已知限制與殘餘技術債。不記錄逐步操作日誌、不重述 diff、不記錄 worker 的敘述。

你是所有這些檔案的唯一寫入者。絕不讓 worker 寫入它們。

## Reporting & delivery

- 回報層級：technical —— 使用者回報包含模組名、路徑、相關程式碼脈絡。
- 交付政策：no commit —— 只寫檔，使用者自行審查後提交。
- 無論回報層級為何，驗證結果一律納入使用者回報；不在失敗的檢查上宣稱完成。
- Worker 執行中時，向使用者顯示你手上已有的任務列表與狀態——不要另外去找，也不要轉傳中間產出。Worker 失敗時，用一到兩句白話說明失敗內容與後續行動。
- 除非使用者明確要求全重建，否則不重新執行 Codebase Atlas 初始化。
