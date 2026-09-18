---
ROLE: relay-lead
CONTRACT: atlas/v4
DELIVERY_POLICY: no commit
---

# Reader Core Correctness：核心閱讀體驗的全面正確性驗證

## Objective

批次完成時，下列全部成立：

1. **有獨立於 Reader 自報狀態的觀察來源** —— 段落身分可從實際畫出來的像素解碼，
   解碼器不讀取任何 Reader 狀態；host 與 Android 兩層共用同一份解碼實作，
   雙層 decode round-trip 相符率 100%。
2. **三個 oracle 各自成立且可分辨** —— Runtime（單幀）、Temporal（時間窗口）、
   Visual（像素）三者職責分離，違反記錄能分辨來源，並能產出
   `CROSS_ORACLE_MISMATCH`。
3. **每一條判定都被證明過** —— 本批次新增的每一條不變式、時間判定與視覺判定，
   都有正向注入證明；連續量的判定另有負向證明。
   **沒有注入式證明的判定視為未完成，不得以 sweep 全綠替代。**
4. **覆蓋維度有理由** —— operation、document topology、reader state、
   race timing phase、多段序列五個維度各自寫得出存在理由；
   無法穩定進入的狀態誠實列為未覆蓋，不含混帶過。
5. **host 全量收斂** —— 連續 2 次不同 seed 的 full sweep，
   runtime / temporal / visual / cross-oracle 四類違反皆為 0。
6. **Android 真實性有結論** —— 代表子集在 `emulator-5556` 上以 2 個不同 seed 跑完，
   四類違反皆為 0；host sweep 曾出現違反的 case 100% 在裝置上重跑通過。
7. **所有確認的 production bug 已修** —— 每個都有根因、regression test、
   以及「該 test 在修復前確實會失敗」的實際證據。
8. **失敗可直接 root-cause** —— 任何 failure 產出完整 evidence bundle，
   含第一個違反幀的原始畫面，足以在不重跑的情況下說明發生了什麼。
9. **既有行為未回歸** —— `flutter analyze` 無新增 error，`flutter test` 全綠；
   既有 I1–I8、`_settle()` 斷言、`suspectedAnomalies` 檢查、
   P2 的 fail-closed guardrail、runner 的 300 秒上限全部原樣保留。
10. **邊界已寫明** —— in-process 取像抓不到 Flutter 圖層以下的問題、
    取像覆蓋率不足造成的判定弱化、host fake clock 與 Android 真實 vsync 之間
    哪些結論不能互推，全部明確寫進專案文件。

**完成標準不是「跑了幾千個 case 而且全部綠色」。** 而是：核心操作、
重要 document topology、runtime state transition、race timing 與多操作序列
都得到有理由的系統性覆蓋；每個 case 從開始到結束同時接受三個獨立來源的監視；
只要人類使用者可能看到錯誤，即使程式最後自行恢復，也能被自動識別、保存證據並判定失敗。

## Task Packages

| # | Package | Route | Goal |
|---|---|---|---|
| 1 | `docs/changes/planning/2026-09-13-reader-v2-core-correctness-c1-fixture-host-foundation.md` | `claude-p` | 可從像素辨識的 deterministic fixture、可控延遲內容 seam、真實 viewport 的 host harness、雙層共用的 operation model 骨架與 case-id 契約 |
| 2 | `docs/changes/planning/2026-09-13-reader-v2-core-correctness-c2-runtime-oracle.md` | `claude-p` | record 補上四類缺失欄位；14 條新／強化不變式，每條雙向證明 |
| 3 | `docs/changes/planning/2026-09-13-reader-v2-core-correctness-c3-temporal-oracle.md` | `claude-p` | 有界時間窗口與 T1–T10 時間判定，每條雙向證明 |
| 4 | `docs/changes/planning/2026-09-13-reader-v2-core-correctness-c4-visual-oracle.md` | `claude-p` | in-process 逐幀取像、視覺指標與位移估計、指紋解碼、V1–V20、cross-oracle 比對 |
| 5 | `docs/changes/planning/2026-09-13-reader-v2-core-correctness-c5-case-generation-host-sweep.md` | `claude-p` | 完整 operation model 與五個維度、3,000–5,000 個 case、host 全量 sweep 與修復迴圈 |
| 6 | `docs/changes/planning/2026-09-13-reader-v2-core-correctness-c6-android-subset-golden.md` | `claude-p` | runner 改 case-id 驅動、watchdog 六面向、failure bundle、golden、Android 子集與失敗回放 |
| 7 | `docs/changes/planning/2026-09-13-reader-v2-core-correctness-c7-knowledge.md` | `gpt-subagent` | 能力邊界聲明、專案文件、guardrail 覆核與可發現性 |

共用證據帳本：`docs/changes/planning/2026-09-13-reader-v2-core-correctness-ledger.md`
（已含 Planner 實際查證的 19 條起始事實 S-01～S-19，其中 S-18、S-19 是待 C1 實測的假設；
C1～C7 各自維護自己的表）

## Execution Order

嚴格依 1 → 2 → 3 → 4 → 5 → 6 → 7，依賴關係都是真實的：

- **1 → 全部**：沒有可辨識 fixture 就沒有視覺指紋，沒有 host harness 就沒有地方跑，
  沒有 case-id 契約就沒辦法把 host 失敗拿到 Android 重放。
  C1 還要先實測 S-18 / S-19 兩個假設，那個結論決定指紋編碼方式。
- **1 → 2**：C2 的新欄位要在 C1 的 harness 上用真實推進驗證有接上
  （fling 期間 `scrollActivity` 是否真的出現 `ballistic`），
  純函式測試綠不代表欄位接對了。
- **2 → 3**：C3 的每一條窗口判定都建立在 C2 補上的欄位上
  （`pumpQueueDepth` 之於 T8、`scrollActivity` 之於 T1、operation token 之於 T2）。
  先有單幀真相，才談得上時間序列。
- **3 → 4**：C4 的 cross-oracle 比對要對齊的是 C2 + C3 已經完整的 runtime 結論；
  且 T4 的 TRANSIENT 分類機制會被視覺違反共用。順序反過來會做兩次。
- **4 → 5**：C5 是主迴圈，它跑出來的綠色只有在三個 oracle 都完成**且都被注入式證明過**
  之後才構成證據。提前跑 sweep 得到的全綠不代表任何事。這是本批次最重要的依賴。
- **5 → 6**：C6 的子集是從 C5 的 manifest 依規則選出來的，
  且必須包含「host sweep 曾出現違反的全部 case」。host 還沒收斂就沒有這份清單。
- **6 → 7**：邊界聲明需要看到三個 oracle 在真機上的實際表現
  （取像覆蓋率、golden 容差、watchdog 誤判排除），不能提前寫。

**C5 與 C6 都是迭代 package**，各自帶明確出口條件：

- C5 出口：連續 2 次不同 seed 的 full sweep，四類違反皆為 0，
  且每個修復都有「修復前確實失敗」的 regression 證據。
- C6 出口：代表子集 2 個不同 seed 四類違反皆為 0，
  且 host 失敗 100% 回放通過。

迭代發生在 package **內部**，Relay 仍然一次只跑一個 package，
不要把迭代拆成多次 dispatch。

## 與另外兩個批次的關係

本批次與下列兩批是**三個獨立批次**，不共用 ledger、不共用 package 編號：

- `2026-09-13-reader-v2-stability-120hz-*`（P4–P6 尚未完成）
- `2026-09-13-reader-v2-state-transitions-*`（T1–T6 尚未開跑）

**三批不得並行。** 三者都會修改 `lib/features/reader_v2/`，
同時執行會讓 diff 無法歸因、驗收無法判斷是誰造成的差異。

**本批次排在另外兩批之後。** 理由是真實依賴，不是偏好：
P4 會改 render / 排程結構，T2–T5 會改 `applyPresentation` 的觸發語義，
兩者都會讓本批次的 topology 與 state 維度需要重新 baseline。
在它們收斂後再建 suite，量到的才是最終結構。

C7 在更新 `DEVELOPMENT.md` 與 `docs/night_reader/reader.md` 時，
必須先讀 P5 與 T6 已寫入的現況並**接進去，不得覆蓋**。

## Delivery

`DELIVERY_POLICY: no commit` —— 本批次全程不 commit、不 push，完成後保持 working tree。

## Shared Verification

全部 package 驗收後，在整合後的 working tree 上執行並記錄實際輸出：

1. `flutter analyze` —— 無 error，且與批次開始前相比無新增 warning。
2. `flutter test` —— 全綠，貼出實際通過數字。
3. **fast lane** —— 跑一次，貼出 case 數與實際耗時，確認在 60 秒內。
4. **host full sweep** —— 以一個**全新的 seed**（不是 C5 出口用過的兩個）跑完，
   四類違反皆為 0。貼出各層 case 數、總耗時、取像覆蓋率。
5. **Android 代表子集** —— 以一個**全新的 seed** 在 `emulator-5556` 上跑完，
   四類違反皆為 0。貼出批次聚合輸出。
6. **Golden** —— 全部 checkpoint 通過；另外重跑一次 C6 的微小 layout 偏移注入，
   確認 golden 仍會失敗（證明它沒有在過程中被放寬）。
7. **注入式證明總覆核** —— 逐項列出本批次新增的全部判定與其證明測試，
   確認沒有任何一條缺證明。這一項用表格呈現，不接受敘述性宣稱。
8. **既有批次未回歸** —— 重跑 P2 的兩個無效情境，確認仍判 `invalid` 且 exit code 非零；
   重跑一次 `journey` scenario 通過。
9. **裝置狀態還原** —— workload 結束後 `emulator-5556` 上是一般 debug APK，
   沒有殘留 test APK 或 profile APK。

最後在批次報告中，把下列三類**分開**陳述，不得混為一談：

- 已驗證：有實際輸出佐證的結論
- 尚未驗證：已知但本批次未能取得證據的項目
  （含 in-process 取像抓不到的圖層以下問題、無法穩定進入的 state 維度、
  未在真機驗證的 emulator 結論）
- 基於證據的推論：有支持但未直接觀測的判斷

任一 Shared Verification 項目未通過，或無法取得其證據，都必須如實標示，
不得以其他項目的通過掩蓋。

特別是：**host 全量通過不得用來宣稱 Android 正確，
Android 子集通過不得用來宣稱全量覆蓋，
final state 正確不得用來抵銷過程中的任何 violation。**
