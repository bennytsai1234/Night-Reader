# Reader V2 120Hz / 排版穩定性 — Evidence Ledger

這份 ledger 是本批次的共用證據帳本。目的只有一個：**任何 agent 在提出假設前，
先查這裡，不要重複跑已經有結論的實驗。**

規則：

- 每個假設一列，**包含負面結果**。負面結果和正面結果一樣重要。
- 「結論」欄只能寫實際觀測到的東西，不能寫推測。推測寫進「備註」。
- 任何在**無效量測窗口**下得到的數字，必須標記 `量測無效`，不得作為決策依據。
- P3（正確性迴圈）與 P4（效能迴圈）各自維護自己的區塊，每個迭代結束就更新。

---

## 量測有效性判定

一次 run 的數字只有在**同時**滿足以下條件時才可採信：

| 條件 | 門檻 | 理由 |
|---|---|---|
| frame 樣本數 | ≥ 300 | 16～19 個樣本的 P99 等同次大值，不是 P99 |
| frame 是否 vsync-paced | 是 | `pump(65ms)` 之間沒有幀，每幀都是冷幀，不代表連續滾動 |
| 顯示更新率 | `vsyncRate=120.00 Hz` | 非 120Hz 下的 8.33ms budget 無意義 |
| workload 是否真的執行 | 有 action marker 且 completedActions > 0 | profile-v1 曾產出零 action 的「正常」artifact |
| invariant hook | 效能 run 必須關閉 | hook 自身有成本，開著量 P99 不可信 |
| 第二來源 | driver 端 TimelineSummary 與 app 內 telemetry 相符 | 避免自己量自己 |

不滿足 → 該 run 標記 `INVALID`，不得產生 pass/fail 判定。

---

## 已知條目（P1 建立時的起始狀態）

| # | 假設 / 改動 | 執行者 | 結果 | 量測有效性 | 結論 |
|---|---|---|---|---|---|
| L-01 | Reader 的 120Hz 瓶頸來自 `LayoutPump` 的 Paragraph layout task | 前一輪 | profile task P99 2.5–3.0ms，`tasksOver8ms=0`，worst task 2.28–2.66ms | 量測無效（16–19 frames）但**否證方向可信**：task 絕對值遠低於 8ms budget，不受樣本數影響 | **已否證**。layout task 不是主要瓶頸。不要再回頭優化 LayoutPump 吞吐當作 P99 解法 |
| L-02 | 瓶頸來自 Flutter widget rebuild | 前一輪 | pure scroll build P99 3.5–4.0ms | 量測無效，但同上，絕對值低 | **已否證**（純 scroll 情境）。`profile-patch-v2` 的 build 14.5ms 出現在含 chapter jump 的情境，另計 |
| L-03 | 瓶頸在 raster / composition | 前一輪 | raster P99 23–88.5ms，遠高於 task 與 build | 量測無效（倍率不可信） | **方向成立，倍率待重測**。raster 是大頭，但 23ms / 88.5ms 這些數字是 16 個冷幀的最壞值 |
| L-04 | 關閉 Impeller 改用 Skia 可改善 | 前一輪 | Impeller P99 92ms / raster 88.5ms；Skia P99 28ms / raster 23ms | **量測無效**（16 vs 17 frames） | **待重測**。改動已從 baseline 抽出。在有效窗口下重跑 A/B 前，不得把任何 renderer 決定寫進 production；已於 P1 從 baseline 抽出，還原至 HEAD |
| L-05 | `context.setIsComplexHint()` 讓 compositor 快取靜態 paragraph layer | 前一輪 | 惡化：P99 100.5ms、raster 116ms、vsync 22ms、build 6ms | 量測無效，但惡化幅度遠超樣本噪音 | **已否證**。程式中已移除。不要再試 |
| L-06 | `RenderCachedBlock.isRepaintBoundary = false` 減少 layer composition | 前一輪 | run 在 Gradle build 階段被中止，**零數據** | 無 | **未驗證**。改動已從 baseline 抽出，列為 P4 的第一個假設；已於 P1 從 baseline 抽出，還原至 HEAD |
| L-07 | emulator 是 CPU 軟體光柵，raster < 8ms 物理上不可能 | 本輪 planner | `dumpsys SurfaceFlinger` → `Android Emulator OpenGL ES Translator (NVIDIA GeForce GTX 1660 SUPER)` | 直接查詢，有效 | **已否證**。emulator 走 host GPU。`config.ini` 的 `hw.gpu.enabled=no` 與實際 runtime 不符，不要據此下結論 |
| L-08 | `dumpsys gfxinfo` 的 `Total frames rendered` 可作為 Flutter FPS 依據 | 本輪 planner（一度誤判） | gfxinfo 顯示 1 frame，同時 Flutter `FrameTiming` 記到 16–19 frames 且有完整 action marker | 直接比對，有效 | **已否證**。gfxinfo 量的是 Android View/SurfaceView 層，與 Flutter 自有 surface 不對應。**不要用 gfxinfo 判斷 Flutter 是否在跑或跑多快** |
| L-09 | profile 模式的 integration workload 無法執行 | 本輪 planner（一度誤判） | 後續 profile runs 有 `READER_CONTINUOUS_ACTION` / `SAMPLE` / `PERFORMANCE` marker 且 completedActions=1 | 直接比對，有效 | **已否證**。profile 通道可執行。僅 `continuous-validation-20260913-120hz-profile-v1` 是真正的空跑 |
| L-10 | 切章後底部進度標籤沿用上一章 | 前一輪 | 已定位為 restore 完成後未 `_publishProgress()`，已修復並有 regression test | 有效（widget test） | **已修復**。留在 baseline |
| L-11 | `AndroidManifest.xml` 的 `EnableImpeller` meta-data 位置可控制 renderer | P1 | HEAD 的 `EnableImpeller` meta-data 位於 `<activity>` 內，實際無效，仍使用 Impeller | 直接檢視 HEAD manifest，有效 | **已確認觀察**。位置是否調整及 renderer 決定留待 P4 以有效 A/B 判定 |

---

## P3 正確性迴圈 — 迭代紀錄

| 迭代 | seed | 違反項 | 分類 | 根因 | 修復 | 重驗結果 |
|---|---|---|---|---|---|---|
| _(由 P3 worker 填寫)_ | | | | | | |

---

## P4 效能迴圈 — 迭代紀錄

| 迭代 | 假設 | 改動 | frames | totalSpan P99 | build P99 | raster P99 | vsync P99 | task P99 | 判定 | 保留/回退 |
|---|---|---|---|---|---|---|---|---|---|---|
| _(由 P4 worker 填寫；每列都必須先通過「量測有效性判定」)_ | | | | | | | | | | |
