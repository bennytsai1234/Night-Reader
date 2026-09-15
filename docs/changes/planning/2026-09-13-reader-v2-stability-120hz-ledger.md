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
| L-03 | 瓶頸在 raster / composition | P2 | 同一 valid profile window：Impeller app frame P99 100.5ms、build 11.5ms、raster 118.5ms、task 3.5ms；driver build 11.223ms、raster 118.359ms；Skia app frame P99 100.5ms、build 8.5ms、raster 119.5ms、task 3.5ms | **有效**（兩組均 120Hz、35 actions、app 2106 frames、driver 2074/2069 frames，兩來源在 tolerance 內） | **方向成立且倍率已重測**：Impeller app raster/task 約 33.9x、driver raster/build 約 10.5x；Skia 約 34.1x／14.2x。raster/composition 仍遠高於 task/build；strict 8ms P99 未達標，交 P4 處理 |
| L-04 | 關閉 Impeller 改用 Skia 可改善 | P2 | 同一 seed `9132026`、35 actions：Impeller app build/raster P99 11.5/118.5ms，driver 11.223/118.359ms；Skia app 8.5/119.5ms，driver 8.301/118.087ms | **有效**（兩組均 frames>=300、120Hz、action marker、hook=false、兩來源存在且相符） | **本輪未證明 Skia 改善 raster**：Skia build 較低，但 app raster 略高；兩組 strict 8ms gate 都 failed。renderer 最終決定留給 P4，不把暫時 manifest 位置改動帶入 production；原 manifest 已還原 |
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
| 1 | 9132027 | I6 × 2：initial short-preface boundary；fling chapter boundary | production；harness | production：`_publishProgress()` 只以 anchor-line 的 `worldY` 計算進度，短前言尚未離開其 admitted range 時，anchor 已落入下一章，造成公開 progress label 與 runtime/title chapter 不一致。harness：fling 期間 raw anchor 暫落前章，但 runtime visible chapter 與 progress 都為目標章；以 raw anchor 當 dominant chapter 不符合 Reader 的 short-chapter / published-location 語意。 | production：`_publishProgress()` 先取得既有 capture location；若 capture 語意仍保留目前章，依 capture 的章節/字元位置發布 `HybridProgressSnapshot`。harness：I6 record 的 dominant chapter 改採 runtime published visible location，另保留 `anchorVisibleChapter` 作診斷，不放寬 I1–I8。 | 修復前 regression 實測失敗：`短章節初始定位的公開進度不會被 anchor 線改成下一章` expected chapter `0`, actual `1`；修復後同測試通過。hook-on seed 9132027：965 app frames / 936 driver frames / 18 actions / 120Hz，除上述兩筆外 I1/I2/I3/I4/I5/I7/I8=0；semantic status passed，hook run 未作 P99 判定。 |
| 2 | 9132028 | I7 × 1：`next_or_previous_chapter` 後跨 reset generation 的 idle frame comparison | harness | 前一幀 `phase=ready`, idle, chapter 19, `resetGeneration=3`；當幀 `phase=ready`, idle, chapter 18, `resetGeneration=4`，且 index center 也不同。這是 chapter restore 完成後的新座標系，不是同一 idle 狀態下仍持續移動。 | I7 只在兩幀的 `resetGeneration`、`indexCenter`、`epoch`、`layoutGeneration` 都一致時比較 offset/visible keys；同一座標世代的 idle 穩定守衛未放寬。 | 修正後待新 seed 重驗；原始 run：762 app frames / 729 driver frames / 18 actions / 120Hz，其他 I1/I2/I3/I4/I5/I6/I8=0，hook status `observed`，未作 P99 判定。 |
| 3 | 9132029 | I6 × 11：`chapter_switch_while_ballistic` jump restore cleanup window | harness | 每筆均有 `pendingChapterJumpTarget={chapterIndex:0,...}`；雖然 `phase=ready`，仍在 jump 的 pending target 清理前，這不是已完成操作後的穩定對外狀態。11 筆是同一 transition 在連續 frame 被 bounded history 記錄，非 11 個獨立 production bug。 | I6 只在 `pendingChapterJumpTarget == null` 時判定，保留 pending target 與完整 violation record 供診斷，不放寬穩定 frame 的 I6。 | 修正後待新 seed 重驗；原始 run：1013 app frames / 981 driver frames / 18 actions / 120Hz，I1/I2/I3/I4/I5/I7/I8=0，hook status `observed`，未作 P99 判定。 |
| 4 | 9132030 | 0 | — | 前三項條件修正後的首次重驗。 | 無新增修復。 | 913 app frames / 877 driver frames / 18 actions / 120Hz；hook `true`、`suspectedAnomalies=0`、0 violations；performance `observed`，未作 P99 判定。 |
| 5 | 9132031 | 0 | — | 相同 production/harness 修正下的獨立 seed 重驗。 | 無新增修復。 | 768 app frames / 736 driver frames / 18 actions / 120Hz；hook `true`、`suspectedAnomalies=0`、0 violations；performance `observed`，未作 P99 判定。 |
| 6 | 9132032 | I6 × 19：`next_or_previous_chapter` 與 `chapter_switch_while_ballistic` settled frame | production | runtime 已在 `ready` 狀態發布目前章節 0，但 `_publishProgress()` 仍只用 anchor-line 的 `DocumentIndex` hit，短章節在 anchor 前時誤把公開 progress 發成章節 1；每筆 current frame 均 `ready/idle`、無缺段、無 pending，故不是 hook 或 harness 瞬態。 | ready runtime publication 變更時同步發布窄通道進度；settled 且非 drag/scroll 時，若 progress 的 anchor chapter 與 runtime visible chapter 不同，改用 runtime 的 chapter/char offset 計算。新增短章節回跳 progress regression。 | 修正前測試實測 `Expected 0 / Actual 1`；修正後同測試通過。原始 seed：968 app frames / 937 driver frames / 18 actions / 120Hz、hook `true`、`suspectedAnomalies=0`；I6 × 19，其餘 I1/I2/I3/I4/I5/I7/I8=0。 |
| 7 | 9132033 | 0 | — | 第二個 production progress race 修正後的新 seed。 | 無新增修復。 | 1211 app frames / 1176 driver frames / 18 actions / 120Hz；hook `true`、`suspectedAnomalies=0`、0 violations；performance `observed`，未作 P99 判定。 |
| 8 | 9132034 | 0 | — | 獨立新 seed 重驗。 | 無新增修復。 | 964 app frames / 930 driver frames / 18 actions / 120Hz；hook `true`、`suspectedAnomalies=0`、0 violations；performance `observed`，未作 P99 判定。 |
| 9 | 9132035 | 0 | — | 獨立新 seed 重驗。 | 無新增修復。 | 1216 app frames / 1185 driver frames / 18 actions / 120Hz；hook `true`、`suspectedAnomalies=0`、0 violations；performance `observed`，未作 P99 判定。 |
| 10 | 9132036 | 非 invariant failure：第 148 action 的 jump restore 失敗，未產生 Completion metadata | env / 未結案 production risk | 受控證據顯示 app 在 `chapter-switch-while-ballistic` 遠距 jump 時進入 `phase=error`（`Hybrid jump restore failed`），同時 emulator log 有 slow-dispatch、skipped frames、`maxConsecutiveMissedFrames=7733`；既有 `_settle()` 因 error 狀態而失敗，不能分類成 invariant pass。另有 runner restore 的 `INSTALL_FAILED_VERSION_DOWNGRADE`。 | 不放寬 `_settle()`、不以 hook-on timing 作效能結論；保留完整 failure artifacts，改以同 runner 的受控 action 重試長時間 window。 | 約 576 秒（driver `elapsed=576s`；app workload 約 506 秒）/ 149 actions 後失敗；hook-on、4 個 suspected anomalies；未達 7200 秒，**INVALID，不能作出口條件證據**。 |
| 11 | 9132043 | 非 invariant failure：第 29 次 `chapter_switch_while_ballistic` restore 回傳 false，隨後 watchdog 中止 | production | ballistic 尾端 notification 在 async restore 期間把 `LayoutPump` 狀態切回 `dragging`；anchor task queue 仍有工作但 `pumpPending()` 回傳 0，`_pumpUntilAnchorReady()` 將其誤判為不可恢復，造成 `phase=error` 與 `Hybrid jump restore failed`。 | restore transaction 每個 bounded pump pass 重新維持 `PumpState.rebuilding`；queue 尚有工作時不把 zero-completion 當 terminal。保留 dragging 期間一般 pump 的禁止規則。 | `artifacts/android-reader/p3-postfix-seed-9132043`：約 243 秒 workload、30 actions；production failure，watchdog 約 15 秒後中止；failure-logcat/driver-output/workload-logcat 已保留。 |
| 12 | 9132043 | 0 | — | 修正 11 後的同 seed 重驗；每次 ballistic jump 均 `restored=true`、`completed=true`、`phase=ready`、target match。 | 無新增 production 修復。 | `artifacts/android-reader/p3-postfix-seed-9132043-final2`：412 app frames / 397 driver frames / 18 actions / 約 139.968 秒 / 120Hz；hook `true`、suspectedAnomalies=0、0 violations；semantic `passed`、performance `observed`，未作 P99 判定。 |
| 13 | 9132044 | 0 | — | 獨立 seed 驗證 ballistic/chapter jump restore 與 I1–I8。 | 無新增修復。 | `artifacts/android-reader/p3-postfix-seed-9132044`：376 app frames / 364 driver frames / 18 actions / 約 152.156 秒 / 120Hz；hook `true`、suspectedAnomalies=0、0 violations；semantic `passed`、performance `observed`，watchdog 未觸發。 |
| 14 | 9132045 | 0 | — | 第三個獨立 seed 驗證 ballistic/chapter jump restore 與 I1–I8。 | 無新增修復。 | `artifacts/android-reader/p3-postfix-seed-9132045`：422 app frames / 410 driver frames / 18 actions / 約 155.612 秒 / 120Hz；hook `true`、suspectedAnomalies=0、0 violations；semantic `passed`、performance `observed`，watchdog 未觸發。 |
| 15 | 9132043 | semantic workload 已完成但 runner 初版判 INVALID：hook-on 時 app/driver `rasterP99` 差異被誤當 acceptance failure | harness | hook-on package contract 是只觀察、不作效能結論；app `rasterP99=200500µs`、driver `333.688ms` 的差異不能否定 semantic/invariant result。 | runner hook-on 仍保存 cross-source comparison，但不以 P99 discrepancy 或缺少非 gating P99 percentile 使 hook-on workload invalid；hook-off strict check 保持不變。 | `artifacts/android-reader/p3-postfix-seed-9132043-final`：18 actions、driverExit=0、timedOut=false、semantic `passed`、0 violations；修正 runner 後 `final2` 取得正式 `observed`。 |
| 16 | 9132046 → 9132047 | 既有 `journey` 第一次 post-fix run 在 target 50 後無法重新顯示 controls | harness timing | 第一次 failure 的 runtime log 已先記錄 target 50 `phase=ready visible=50 matches=true`；failure stack 只落在 `ReaderTestHarness.showControls()`。`ScaffoldState.isDrawerOpen` 已先變 false，但 failure screenshot 仍見 drawer，表示 route/遮罩 transition 尚未完成；沒有 production exception 或 invariant violation。 | 在 `reader_test_support.dart` 將 drawer close 條件由單一 logical `isDrawerOpen=false` 擴為 logical + `ReaderV2ChaptersDrawer.hitTestable=false`，以 `readerVsyncStep`、2 秒 bounded wait 等待視覺 transition；未修改 production Reader。 | `artifacts/android-reader/p3-journey-postfix-seed-9132046` 保留 failure-logcat、screenshot、49.116s workload 與 metadata（300s cap，watchdog 未觸發）；`artifacts/android-reader/p3-journey-postfix-seed-9132047`：journey `READER_E2E_RESULT status=passed`、provision 101 chapters、chapter markers `0,1,50,3,100,99,0`、reopen success、workload 43.075s、exit 0、timedOut=false、hook=false。 |

---

## P4 效能迴圈 — 迭代紀錄

| 迭代 | 假設 | 改動 | frames | totalSpan P99 | build P99 | raster P99 | vsync P99 | task P99 | 判定 | 保留/回退 |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 (baseline) | HEAD renderer baseline / Impeller-effective manifest placement | 無 production 優化；vsync-paced continuous runner + driver/app cross-source reporting | app 2106 / driver 2074 | app frame P99 100.5ms | app 11.5ms / driver 11.223ms | app 118.5ms / driver 118.359ms | app 29.0ms | app 3.5ms | **valid measurement, performance failed** (`<8000µs` 未達) | 保留 baseline 證據；不在 P2 優化 |
| 1a | `isRepaintBoundary=false` 可減少每個 block 的 layer composition | `RenderCachedBlock.isRepaintBoundary` 改為 `false`；同步更新 sliver 註解。第一次實測使用 seed `9132050` | **INVALID**：driver 8504 frames / 35 actions；app telemetry 未產出，continuous test 因既有 `suspectedAnomalies=1` 失敗 | — | — | driver raster P99 21.778ms（僅診斷，無效不得採信） | — | — | **INVALID，未作效能判定**：`previous-chapter-start-target-12` reverse-jump anomaly；非 P3 語義修改對象 | 保留 invalid artifact `artifacts/android-reader/p4-iter-1-no-repaint-boundary-seed-9132050-valid`；以 P2 已驗證 seed `9132026` 重跑同一變數 |
| 1b | `isRepaintBoundary=false` 可減少 layer composition（P2-valid seed 重驗） | 保留 `cached_block_widget.dart` 的 `false` 與 sliver 註解更新；無第二個 production 變數 | app 9550 / driver 9377；35 actions；hook=false；semantic passed；120Hz；cross-source valid | 41000µs | app 4000µs / driver 3771µs | app 21000µs / driver 20613µs | 11000µs | 3000µs | **valid measurement, performance failed** (`<8000µs` 未達)；相對 baseline total/raster `100500/118500µs` 明顯下降 | **保留**；artifact `artifacts/android-reader/p4-iter-1-no-repaint-boundary-seed-9132026-valid` |
| 1c | `isRepaintBoundary=false` 在獨立 seed 下可重現 iteration 1b 的改善 | 同 iteration 1b；seed `9132073`；無新增 production 變數 | **INVALID**：35 actions 已完成但 `_ContinuousReaderProbe` 捕捉 `previous-chapter-start-target-26` reverse-jump anomaly（`suspectedAnomalies=2`）；app telemetry 未產出 | — | — | — | — | — | **INVALID，未作效能判定**；不把這次 seed 的 anomaly 當成 renderer/paint regression | **保留 artifact `artifacts/android-reader/p4-iter-1c-no-repaint-boundary-seed-9132073-valid`；回到已驗證 seed `9132026` 做 final reproduction** |
| 1d | 保留版 `isRepaintBoundary=false` 的 final full workload 重驗 | 同 iteration 1b；P2-confirmed seed `9132026`；無新增 production 變數 | app 5898 / driver 5801；35 actions；hook=false；semantic passed；suspectedAnomalies=0；120Hz；cross-source valid | 75000µs | app 6000µs / driver 5709µs | app 40500µs / driver 40157µs | 19500µs | 4000µs | **valid measurement, performance failed** (`<8000µs` 未達)；final reproduction 未達 strict gate，且比 iteration 1b `41000µs`較慢，未改 production | **保留 artifact `artifacts/android-reader/p4-final-no-repaint-boundary-seed-9132026`；不以單次較差結果回退已證明優於 P2 baseline 的 boundary change** |
| 2 | effective renderer A/B：Skia 是否在 `isRepaintBoundary=false` 下進一步降低 raster | 暫時將 `EnableImpeller=false` 移至 `<application>`，只改 renderer；run 完成後還原至 activity 內的 P1 baseline placement | app 9335 / driver 9189；35 actions；hook=false；semantic passed；120Hz；cross-source valid | 40000µs | app 3500µs / driver 3083µs | app 21000µs / driver 20823µs | 11500µs | 2500µs | **valid measurement, performance failed**；Skia raster 與 Impeller-effective iteration 1b 的 `21000/20613µs` 相當，未證明改善；全域 renderer opt-out 亦有 deprecated/真機未驗證風險 | **回退 renderer**；manifest 已還原；artifact `artifacts/android-reader/p4-iter-2-skia-no-boundary-seed-9132026-valid` |
| 3 | 對完全落在單 block extent 的 Paragraph 省略冗餘 `clipRect` 可降低 paint raster 成本 | `RenderCachedBlock.paint()` 僅在 `localTop==0` 且 paragraph height 不超過 block 時省略 clip；continuation group 仍 clip | app 10214 / driver 10056；35 actions；hook=false；semantic passed；120Hz；cross-source valid | 42000µs | app 4000µs / driver 3891µs | app 21500µs / driver 21125µs | 13500µs | 3000µs | **valid measurement, performance failed**；相對保留版 iteration 1b total/raster `41000/21000µs` 惡化為 `42000/21500µs` | **回退**；artifact `artifacts/android-reader/p4-iter-3-paint-clip-elision-seed-9132026-valid` |
| 4 | chapter jump 是否是 full continuous P99 惡化的主要來源 | 維持 iteration 1b 的 `isRepaintBoundary=false`；使用 `chapter_switch_while_ballistic` 強制動作隔離 jump restore；未新增 production 變數 | app 4867 / driver 4683；35 actions；hook=false；semantic passed；120Hz；cross-source valid | 45500µs | app 4500µs / driver 4145µs | app 19500µs / driver 19518µs | 22000µs | 2000µs | **valid measurement, performance failed**；jump window 中 build/task 均低於 8000µs，但 vsync/raster 仍高於門檻；可歸因 jump 不是 build/task ceiling，不能取代 full-session gate | **保留 attribution artifact，不變更 production**；`artifacts/android-reader/p4-iter-4-chapter-jump-attribution-seed-9132060-valid` |
| 5a | 單一巨型 `Text` 的簡化 scroll control 可直接作為 equal-area ceiling control | harness 新增 `-SimpleScrollControl` 後第一次嘗試；`SingleChildScrollView + 53MB Text`；有限批次執行時手動中止以避免 35 actions 超出 600 秒上限 | **INVALID**：fixture race 導致 control 在 fixture watcher 尚未完成推送時退出；無 action、無 app telemetry、無 driver TimelineSummary | — | — | — | — | — | **INVALID，未作效能判定**；後續未採用單一巨型 paragraph control | **保留 artifact `artifacts/android-reader/p4-ceiling-control-simple-scroll-seed-9132070`；改為 lazy chunked control** |
| 5b | 等面積、較簡單的 scroll control 若仍有 raster ceiling，可支持 emulator/control ceiling attribution | harness-only：同一 53MB fixture 按換行邊界切成約 2000 字 chunks，以 lazy `ListView` 顯示；同 viewport、35 個有限 simple-scroll actions；未改 production Reader | app 1351 / driver 1259；35 actions；hook=false；semantic passed；120Hz；cross-source valid | 100500µs | app 7000µs / driver 6672µs | app 56500µs / driver 56174µs | 18000µs | 0µs | **valid control measurement, performance failed**；簡化 control 的 build/task <8000µs，但 raster P99 `56500µs`、vsync P99 `18000µs`，故支持 **emulator-only/control raster ceiling evidence**；不代表 Reader pass | **保留 control artifact 作 ceiling 證據；不把 control route 帶入 production**；`artifacts/android-reader/p4-ceiling-control-chunked-list-seed-9132072` |

### Runner / environment handoff note

- P4 最初幾次 supervisor 啟動命令使用 Windows PowerShell 5.1 的 `powershell -NoProfile`；P2/P4 runner 內的 `.NET ProcessStartInfo.ArgumentList` 在該版本為 `null`，所以在 adding arguments 階段失敗。這是 runner shell compatibility pitfall，不是 production 或 P2 measurement 根因。
- 後續所有有效 Android driver run 改用 PowerShell 7 的 `pwsh -NoProfile`。runner 的 fixture replacement watcher、進度觀測與 120 秒 no-progress watchdog 仍保留，因為它們是 package 的安全條件，不應因 shell pitfall 移除。

---

## P4G 操作類別量測與歸因（追加；不改寫 P1–P4）

### A0 — P1–P4 artifact 離線盤點（2026-09-13）

本次先以唯讀方式盤點 `artifacts/android-reader/` 下的 113 個 run directory，未
啟動新 workload。判定依 package 的完整條件：`metadata.json`、
`continuous-samples.jsonl`、driver `TimelineSummary`、app telemetry、
completed action marker、120Hz、`hook=false`、兩來源一致，且 frame count 必須
在分類後仍 `>=300`。`journey` / `monkey` 目錄即使有 metadata，也只有一般
scenario 輸出，沒有可供 P4 類別重算的 continuous frame stream，因此不列為
continuous 類別證據。

可重算（保留 continuous sample 與足夠 action checkpoint，但重算能力分級）：

- **P4 有效性能來源**：`continuous-p2-profile-20260913-valid-window`、
  `continuous-p2-profile-20260913-skia-ab`、
  `p4-final-no-repaint-boundary-seed-9132026`、
  `p4-iter-1-no-repaint-boundary-seed-9132026-valid`、
  `p4-iter-2-skia-no-boundary-seed-9132026-valid`、
  `p4-iter-3-paint-clip-elision-seed-9132026-valid`、
  `p4-iter-4-chapter-jump-attribution-seed-9132060-valid`。
  這些有 app/driver source、`hook=false`、120Hz、35 actions 與至少 300 個
  session frame；但既有 stream 只有舊的 scroll/jump 動作，不能從中合法
  推論控制項、翻頁、選單、TTS、熱啟、冷啟或書籤等缺少 marker 的類別。
- **可作語意/marker 參照但不可作性能判定**：
  `p3-iter-1-seed-9132027`、`p3-iter-2-seed-9132028`、
  `p3-iter-3-seed-9132029`、`p3-iter-4-seed-9132030`、
  `p3-iter-5-seed-9132031`、`p3-iter-6-seed-9132032`、
  `p3-iter-7-seed-9132033`、`p3-iter-8-seed-9132034`、
  `p3-iter-9-seed-9132035`、`p3-final-seed-9132039`、
  `p3-postfix-seed-9132043-final2`、`p3-postfix-seed-9132044`、
  `p3-postfix-seed-9132045`。它們有完整 continuous markers 與 app/driver
  frame stream，但 `invariantHookEnabled=true`，依契約只能是 semantic/
  performance observed，不能作 8ms 性能出口。
- **可重算但已明確 INVALID，僅保留負面證據**：
  `continuous-p2-negative-under-300`（app 57 / driver 24 frames）、
  `continuous-p2-negative-missing-json`（無 driver/app response）、
  `p4-iter-1-no-repaint-boundary-seed-9132050-valid`、
  `p4-iter-1c-no-repaint-boundary-seed-9132073-valid`（semantic anomaly，
  app telemetry/driver 對性能判定不完整）、`p3-postfix-seed-9132043-final`
  （hook-on 且 raster cross-source discrepancy）、以及
  `p3-long-2h-seed-9132036`（長批次在 failure 前終止）。
  INVALID 數字不進任何類別結論。
- `p3-long-2h-seed-9132037-slow-read` 有大量 slow marker 與 frame，但 hook-on
  且是超長觀測 run；只可作診斷/marker 參照，不能替代新的有限、hook-off
  類別測量。

不可重算或不足以重算 P4 類別性能的 artifact：其餘所有 run，包括
  `continuous-p2-debug-20260913`、`continuous-p2-debug-20260913-current`、
  `continuous-p2-debug-20260913-final`、`continuous-p2-debug-20260913-rerun`、
  `continuous-p2-debug-20260913-rerun2`、`continuous-p2-debug-20260913-rerun3`、
  `continuous-p2-debug-20260913-validated`、
  `continuous-validation-120hz-patch-v1`、
  `continuous-validation-120hz-profile-patch-v1`、
  `continuous-validation-120hz-profile-patch-v2`、
  `continuous-validation-120hz-profile-slow-scroll-cachehint-v1`、
  `continuous-validation-120hz-profile-slow-scroll-norepaint-v1`、
  `continuous-validation-120hz-profile-slow-scroll-skia-v1`、
  `continuous-validation-120hz-profile-slow-scroll-v1`、
  `continuous-validation-20260913-120hz-policy120-v1`、
  `continuous-validation-20260913-120hz-policy120-v2`、
  `continuous-validation-20260913-120hz-profile-v1`、
  `continuous-validation-20260913-120hz-v2`、
  `continuous-validation-20260913-120hz-v3`、`continuous-validation-20260913-v1`、
  `p3-final-seed-9132040`、`p3-final-seed-9132041`、`p3-final-seed-9132042`、
  `p3-iter-10-seed-9132038`、`p3-postfix-seed-9132043`、
  `p3-postfix-seed-9132043-rerun`、`p3-postfix-seed-9132043-rerun2`、
  `p3-postfix-seed-9132043-rerun3`、`p4-ceiling-control-chunked-list-seed-9132072`,
  `p4-ceiling-control-simple-scroll-seed-9132070`、
  `p4-ceiling-control-simple-scroll-seed-9132071`、
  `p4-harness-diagnostics-9132052`、`p4-harness-diagnostics-9132053`、
  `p4-harness-diagnostics-9132054`、以及所有 `journey-*` / `monkey-*`。
  原因依序是 zero/short stream、缺 driver response、hook/semantic failure、
  control route 無 Reader action marker，或 scenario 本身沒有 continuous
  FrameTiming 與 action checkpoint。它們保留在磁碟上，不刪除、不補湊樣本。

標記語意查證：`debugSnapshot()` 的 `scrollDirection` 是相鄰 snapshot 的
`scrollOffset` 差值（絕對值大於 `0.5` 才是 forward/backward，否則 idle）；
`isScrolling` 直接來自 `ScrollPosition.isScrollingNotifier`，表示目前有
scroll activity，不是「此 viewport 具備可捲動能力」。因此 P4 第一行
`label=open, dir=idle, scrolling=true` 是 open/initial restore 的 transient
scroll activity，`idle` 代表該次 snapshot 沒有足夠的 offset delta；它既不是
使用者正在滾動的 action，也不能當作可捲動能力樣本。分類從 `initial-settled`
之後開始，並排除 `open` / `initial-settled` warm-up。

既有欄位的實際語意：`phase` 為 runtime phase；`location`（compact stream 的
`location`）為當下 `capturedLocation`，不是單純 raw anchor；`reset` 為
`documentIndexResetGeneration`；`epoch` 為 Reader paragraph/layout epoch；
`layout` 為 runtime layout generation；`scrolling` / `dragging` 分別為
ScrollPosition activity 與 pointer drag 狀態；`j8/j16/j33` 是 session/rolling
window 中 frame total span 大於 8.333/16.667/33.333ms 的計數；`streak` 是
當下連續超過 8.333ms 的 streak，`maxStreak` 是迄今最大 streak；`p50/p95/p99`
與 `worst` 是 frame total span 的 rolling checkpoint 摘要；`taskP99` 與
`taskOver8` 是 LayoutPump task 的 elapsed percentile/count，不是整幀；
`vsync`、`build`、`raster` 是 FrameTiming component percentile，其中
`raster` 是 rasterizer/composition 時間。Metadata/response 的 `build`、
`raster` 是 driver TimelineSummary 的同名全 run P99；不能冒充分類後 P99。

### A1 — 固定操作類別與 marker/checkpoint 映射

以下映射在後續所有 P4G run 固定使用；名稱是 action identity，checkpoint
是該 action 內的 conversion/steady boundary，不因結果改名或合併：

| 類別 | action identity | 必要 marker/checkpoint | warm-up / idle 規則 |
|---|---|---|---|
| scroll | `scroll_slow`、`scroll_fast`、`scroll_long_distance`、`scroll_variable_speed`、`scroll_brake`、`scroll_cross_chapter_ballistic`、`scroll_reverse`、`scroll_short_chapter_chain`、`scroll_book_start_boundary`、`scroll_book_end_boundary` | `action-start`、每個 vsync-paced move/fling sample、`action-end`、`settled`；ballistic 類另記 cross-chapter | 只收 action 期間 frame；settled/idle 只作邊界與診斷，不列 idle 判定 |
| interaction | `interaction_control`、`interaction_page`、`interaction_menu_open_close`、`interaction_tts_toggle` | `conversion-start`、轉換期間 frame、`conversion-end`、`settled`；起訖 wall-clock duration | controls/menu/TTS 的 overlay/sheet transition 必須獨立 marker；不能由 scroll marker 推論 |
| navigation | `navigation_next_chapter`、`navigation_previous_chapter`、`navigation_directory_jump`、`navigation_directory_jump_then_immediate_read`、`navigation_bookmark_jump` | `conversion-start`、首屏可讀 `first-readable`、完全穩定 `fully-stable`、`conversion-end`、轉換期間 frame | `chapter_switch_while_ballistic` 固定歸 **scroll_cross_chapter_ballistic**；runtime `jumpToChapter` action 另歸 navigation，不混用 |
| entry | `entry_hot_open_book`、`entry_cold_open_book` | `entry-start`、首屏可讀 `first-readable`、完全穩定 `fully-stable`、`entry-end`、轉換期間 frame | cold：app 從書庫/未在 Reader 進入；hot：已在 Reader route 內換書；兩者不合併 |
| idle (diagnostic only) | `idle_diagnostic`（非判定 action） | 只記 heartbeat/frame snapshot | 永不進 8ms 類別判定，亦不拿來補 frames>=300 |

舊 `-Action` 的 7 個值已確認：`slow_read_forward`、`small_correction`、
`fling_forward_then_reverse`、`fling_reverse_then_continue` 是 scroll；
`next_or_previous_chapter` 是 navigation；`directory_jump_then_immediate_read`
是 navigation；`chapter_switch_while_ballistic` 目前實作為「先 fling、再呼叫
runtime jump」的跨章 ballistic race，故在 P4G 映射為
`scroll_cross_chapter_ballistic`，不是純 navigation jump。未來純
`navigation_*` marker 不得再用該舊名稱代替。

### A2 — 分類後 frame summary 與原 session gate（2026-09-14）

下表只列通過 A4 的新 P4G artifact；時間單位為 ms，`j8/j16/j33` 是該
performance window 的 frame count，`taskP99/taskOver8` 是 LayoutPump task，
不是整幀。每個 forced-action window 只包含一個 action identity，故這些數字
可作該類別的 observed attribution；`performance.status=failed` 仍保留，因為
8ms gate 沒有放寬。

| action | app/driver frames | p50 / p95 / p99 / worst | j8 / j16 / j33 | maxStreak | taskP99 / taskOver8 | session gate |
|---|---:|---:|---:|---:|---:|---|
| `scroll_slow` | 1574 / 1485 | 41 / 64.5 / 84 / 115.656 | 1572 / 1560 / 1252 | 880 | 6.5 / 0 | failed |
| `scroll_fast` | 7788 / 7696 | 41.5 / 59.5 / 76 / 106.437 | 7786 / 7765 / 6785 | 3631 | 8.5 / 0 | failed |
| `scroll_long_distance` | 2319 / 2234 | 42 / 62 / 82 / 129.323 | 2319 / 2312 / 1983 | 2319 | 11 / 2 | failed |
| `scroll_variable_speed` | 459 / 370 | 41.5 / 66.5 / 83 / 88.218 | 459 / 452 / 370 | 459 | 3.5 / 0 | failed |
| `scroll_brake` | 2275 / 2240 | 100.5 / 100.5 / 100.5 / 254.365 | 2275 / 2275 / 2274 | 2275 | 4 / 0 | failed |
| `scroll_cross_chapter_ballistic` | 478 / 446 | 100.5 / 100.5 / 100.5 / 289.344 | 478 / 478 / 476 | 478 | 3.5 / 4 | failed |
| `scroll_reverse` | 2248 / 2216 | 100.5 / 100.5 / 100.5 / 255.931 | 2248 / 2248 / 2247 | 2248 | 3 / 0 | failed |
| `scroll_short_chapter_chain` | 1191 / 1159 | 100.5 / 100.5 / 100.5 / 281.048 | 1191 / 1190 / 1186 | 1191 | 4 / 0 | failed |
| `scroll_book_start_boundary` | 1164 / 1130 | 100.5 / 100.5 / 100.5 / 227.75 | 1164 / 1164 / 1163 | 1164 | 0 / 0 | failed |
| `scroll_book_end_boundary` | 1165 / 1135 | 100.5 / 100.5 / 100.5 / 421.614 | 1165 / 1165 / 1165 | 1165 | 18 / 1 | failed |
| `interaction_control` | 2310 / 2225 | 41.5 / 70 / 100.5 / 142.31 | 2310 / 2298 / 1913 | 2310 | 1.5 / 0 | failed |
| `interaction_menu_open_close` | 1576 / 1350 | 7.5 / 18 / 35 / 56.86 | 622 / 99 / 17 | 67 | 0 / 0 | failed |

歷史 P4 的 session-level gate 欄位與 completion report 未改寫；上表是 P4G
追加的重新計算，不能把舊的「session failed」直接套成所有操作類別的結論。
所有上表 run 都是 `hook=false`、120Hz AVD、app/driver cross-source valid，且
app 與 driver frame count 均 `>=300`。`p4g-interaction-page-seed-9140105`
只有 212 / 180 frames，保留為 INVALID；它的 observed p99 100.5ms 不進類別
結論。

### A3 — 操作類別實測、marker 與缺口

- 捲動的 slow、fast、long-distance、variable-speed、brake、reverse、短章節
  連續跨越、書首與書尾邊界，以及跨章 ballistic race 都已各自用固定
  `scroll_*` identity 實測。`scroll_short_chapter_chain` 的 fling 距離足以
  驅動連續章節候選，但現有 snapshot 沒有「實際跨越章節次數」欄位，因此
  只能結論為該操作序列已執行，不能宣稱每次都完成跨章。
- 已由 source 與 marker 確認 `chapter_switch_while_ballistic` 是先 fling、
  等待短時間後再 `runtime.jumpToChapter` 的 cross-chapter ballistic race，
  歸 `scroll_cross_chapter_ballistic`，不是純 navigation jump。
- `interaction_control` 與 `interaction_menu_open_close` 已有效；
  `interaction_page` 有 marker 與 duration 但低於 frame 門檻；
  `interaction_tts_toggle` 因 ADB package service transport 失聯中止，沒有
  可用 continuous result。兩者均不能以 control 代替。
- 導覽 `navigation_next_chapter` 已嘗試 14 actions，但 app/driver
  cross-source invalid（715 / 484 frames，rasterP99 29.5ms / 41.908ms）；
  previous、directory、directory-then-immediate-read、bookmark 尚未取得
  有效新分類樣本。entry hot/cold 也尚未取得有效樣本。這些缺口明列保留，
  不用舊 P4 session-level 結果補推。

### A4 — validity、frames 門檻與來源

分類後才套用 validity：action identity marker、completed action、
`hook=false`、120Hz、vsync-paced workload、app telemetry 與 driver
TimelineSummary cross-source 一致、app/driver 各至少 300 frames。上表的
`exclusiveAction=true` 且 frame scope 是「performance window contains only
this forced action」；因此沒有用總 session frame 湊分類門檻。idle/open 的
初始 transient snapshot 不列入任何判定。失敗或中斷 artifact 仍留在
`artifacts/android-reader/p4g-*`，但標為 INVALID/未完成。

### A5 — 互動 conversion timing

`interaction_control`：35 actions 的 conversion duration p50/p95/p99/worst
為 1479.471 / 1521.211 / 1586.009 / 1586.009ms；first-readable p50/p95
為 259.989 / 266.109ms；fully-stable p50 與 conversion p50 同為
1479.471ms。`interaction_menu_open_close`：duration p50/p95/p99/worst 為
898.988 / 941.643 / 967.030 / 967.030ms；first-readable p50/p95 為
257.662 / 263.465ms；fully-stable p50 與 duration p50 同為 898.988ms。
這些是 observed 起訖總時長與 marker 期間的統計，8ms 仍是目標；不是把
transition 拆開後放寬。page 因 `frames<300` invalid，TTS 因環境中止。

navigation 與 entry 沒有有效 artifact，所以沒有填入首屏可讀、完全穩定、
轉換期間 frame 或起訖總時長；這是未驗證，不是零值。

### A6 — raster / layout attribution（診斷，不改 production render）

有效 P4G driver TimelineSummary 的 layer cache count/bytes 與 picture cache
count/bytes 的 p99 都為 0；這是目前 driver export 的診斷值，不足以證明畫面
沒有 implicit compositing。現有 production source 的明確 `canvas.saveLayer`
只有 `lib/features/reader_v2/hybrid/view/cached_block_widget.dart:189` 的
收斂 clip path；menu 有 `BoxShadow`，TTS highlight 有 blur `MaskFilter`，而
transition 的 implicit clip/opacity/shadow/mask 沒有從現有 artifact 得到逐項
saveLayer/overdraw 計數。依此只能列為 attribution limitation，不能在取得新
數據前改 render 結構。

LayoutPump observed count / taskP99 顯示：control 3780 / 1.5ms、menu 0 / 0ms；
scroll slow 56 / 6.5ms、fast 130 / 8.5ms、long 130 / 11ms、variable 25 /
3.5ms、brake 118 / 4ms、cross-chapter ballistic 2753 / 3.5ms、reverse 25 /
3ms、short-chain 130 / 4ms、book-start 0 / 0ms、book-end 70 / 18ms。
其中 cross-chapter 與 control 的 task count 偏高，book-end 有 taskOver8=1，
可作 layout/pump 方向的診斷線索；沒有 per-category paragraph count 或
paragraph-time ratio，且 paragraph cache hit/miss export 為 0，不能推論
「paragraph 佔比」。導覽/entry 沒有有效樣本，故沒有填 layout 比例。

### A7 — 以新表重解讀 P4（不改歷史）

仍可成立的是：在目前 emulator/profile workload 與 A4 validity 下，所有已
量測的 scroll identity 以及 control/menu 都未通過 8ms gate；scroll 類尤其
顯示 fast/long/variable 的 p99 約 76–83ms，brake/reverse/boundary 類 p99
被 100.5ms 長尾主導，control 為 100.5ms、menu 為 35ms。這些是逐類別
observed failure，不是 idle 結論，也不改 P4 原有 session-level rows。

尚不能推論的是：page、TTS、任何 navigation identity、hot/cold entry，以及
short-chain 是否每次真的跨章；也不能由 layer/picture cache=0 推論沒有
saveLayer/overdraw，更不能用 emulator 推論實機結果。原 P4 artifact 的
歷史解讀保持原樣，僅由本 P4G 表補上「哪些操作已重新量測」的邊界。

### A8 — 實機狀態

本工作階段沒有使用者提供的實機；唯一 Android target 是
`emulator-5554`（`sdk_gphone64_x86_64`，同一 `NightReader_120Hz` AVD，
`vsync-rate 120`），所有 Android run 都是 bounded iterations/timeout 且
保留 watcher/no-progress watchdog。故本 P4G 沒有 release 真機驗證；缺少
至少一台實際 120Hz Android 裝置的 release build、真實 refresh/thermal/CPU
GPU 狀態與同一操作矩陣。emulator 結果只作 emulator observed evidence，
不作真機性能結論。

## P4V B1/B2 失敗模式與獨立觀察映射（2026-09-14；量測前建立）

本區段在 P4V 任何 A/B screenshot、hook-on invariant 或 paired performance
measurement 之前建立。它是 P4V 的 evidence ledger，不改寫 P1-P4 既有條目，也
不將 P4/P4G 的跨 run 絕對數字重用為本次 A/B 結論。以下「初始狀態」代表在
量測開始前尚未觀察，不代表通過；完成 B3-B6 後會以實際 artifact 對應更新的
P4V evidence file 記錄 observed、environment noise、not observable 或 missing
coverage。

### B1 failure-mode inventory

| ID | 可能失敗模式 | 內容改變／觸發路徑 | 獨立觀察面 | 量測前狀態與判定邊界 |
|---|---|---|---|---|
| V1 | 視覺殘影：舊文字、舊顏色或舊高亮留在畫面 | scroll、chapter jump、任何 repaint 後的 settled viewport | 固定 checkpoint 的 Android screenshot pixel diff；必要時保存 before/after PNG | pending；非環境性固定區域差異才算 bug |
| V2 | 漏繪／空白 block／局部未重繪 | lazy admission、paragraph 尚未 ready、長距離 scroll、source reload | screenshot diff + 同 checkpoint semantic visible keys／block coverage | pending；只在像素與語意邊界都能定位時宣稱 observed |
| V3 | 疊錯／錯誤 stacking、重複文字或 z-order 錯置 | continuation blocks、overlay、TTS highlight、menu/drawer transition | screenshot diff；semantic route state 僅作輔助，不能代替像素證據 | pending；固定內容的非噪音差異為 regression candidate |
| V4 | 局部 repaint 遺留／只更新部分 layer | scroll surface 與 block window 交界、padding／rotation／theme conversion 後 | screenshot diff 於 block 邊界與 overlay 邊界取樣 | pending；無逐 layer Android observation 時記 not observable，不以綠測試取代 |
| C1 | cache invalidation 遺漏、舊 paragraph／metrics／namespace 誤命中 | 字級、行高、字距、字型、theme/textColor、簡繁、rotation/padding、source reload | hook-on invariant I1-I8 差分 + final phase/queue/visible keys；pixel diff 驗證實際畫面 | pending；cache hit/miss 本身不是可用證據，若無 export 記 not observable |
| C2 | cache invalidation 過度或錯誤世代：畫面短暫空白、舊高度／錨點 | 上述所有 layout/content signature 變動 | settled screenshot checkpoints + semantic epoch/layout/reset/location | pending；須區分正常 settling 與 settled 後殘留 |
| P1 | 字級變更後 paragraph、行界、block 高度或錨點未更新 | font size | Android screenshot before/after settled + hook-on invariants；widget fallback 僅能證明 host boundary | pending；若 Android route 不可執行，列 missing Android pixel coverage |
| P2 | 行高變更後行距／總高度／可見連續性錯誤 | line height | 同上，另觀察 visible keys/queue/epoch/layout | pending |
| P3 | 字距變更後文字寬度、換行或局部 layer 不一致 | letter spacing | 同上 | pending |
| P4 | 字型變更後 glyph、metrics 或快取鍵錯配 | font family | 同上；需固定實際字型與 fixture | pending；若裝置無法固定字型，列 environment limitation |
| T1 | theme 切換後背景、文字與 cache 內容不同步 | theme | settled screenshot pixel diff；hook-on final invariant | pending |
| T2 | `textColor` 變更後舊文字色／overlay 色殘留 | textColor | settled screenshot diff，特別取文字區與 TTS 區；semantic 僅作狀態輔助 | pending |
| X1 | 簡體／繁體轉換後內容、長度、換行與 anchor 不一致 | simplified/traditional conversion | screenshot diff + hook-on invariant + final chapter/location/visible keys | pending；需明確標記 conversion-end/settled |
| R1 | rotation 後 viewport、content width、block positions 或 restore 錯誤 | device rotation | Android screenshots in both orientations + final semantic snapshot | pending；若 emulator tooling 不支援穩定旋轉，列 not observable |
| R2 | padding 變更後首行、邊界、可見範圍或 repaint 遺留 | reader padding | settled screenshot diff + semantic visible keys/anchor | pending |
| H1 | TTS highlight 跟隨停步、跳錯、舊 highlight 殘留或疊錯 | TTS highlight following／ensureCharRangeVisible | screenshot diff at highlight checkpoints + hook-on invariant/queue/phase; audio-service harness limitation must be separated | pending；若只能 host/widget，禁止宣稱 Android pixel coverage |
| S1 | source reload 後舊 source 文字／metrics／chapter 留在畫面 | source reload／change source | screenshot diff after reload settled + final phase/reset/epoch/visible keys + anomaly log | pending |
| S2 | source reload race 造成 blank、重複、錯誤 chapter 或 stale pending jump | source reload during active viewport／scroll | same as S1, with action-start/conversion-end/settled markers | pending |
| J1 | ordinary reading scroll 的 scroll surface composition 改變造成 ghosting 或 jank | ordinary reading／slow and fast scroll | B3 pixel checkpoints；B5 P4G `scroll_*` paired performance with hook=false | pending |
| J2 | long scroll／chapter jump 的 admission、continuation 或 layer stacking regression | long-distance scroll、chapter jump | B3 screenshots + B4 I1-I8 + B5 mapped `scroll_long_distance`, `navigation_*`, or `scroll_cross_chapter_ballistic` | pending |
| O1 | overlay/menu/page interaction 造成 block 或 layer 遮罩錯誤 | menu open/close、page control | screenshot diff at conversion-end/settled + semantic phase/visible keys | pending；P4G `interaction_*` identity only |

### B2 observation mapping and independence rules

1. Pixel evidence observes the rendered output from outside the repaint-boundary
   implementation: same device, build mode, seed, fixture, font, viewport and
   settled checkpoint for baseline=true and candidate=false. A pixel difference is
   retained as raw metric even when later classified as environment noise.
2. Semantic evidence observes runtime invariants through the hook-on path, not
   paint timing: for both builds record I1-I8 counts, `suspectedAnomalies`, final
   phase, queue depth, visible keys, epoch/layout/reset and any blank/duplicate
   evidence. Hook-on frame timings are excluded from B5.
3. Performance evidence observes the app/driver timing sources with hook=false,
   120Hz, vsync-paced input, category-scoped frames>=300 and cross-source validity.
   It must use same-session or rigorously alternating paired runs and the P4G A1
   action identity/marker table; no P4 absolute P99 is an A/B conclusion.
4. Cache/paint diagnostics are only independent when they come from a separate
   read-only diagnostic boundary. Existing cache/picture-cache counters of zero,
   or a frame timing produced by the same render path, cannot prove cache
   invalidation correctness, absence of overdraw, or absence of implicit layers.
   Without a cache hit/miss, overdraw or layer-specific observation, mark that
   subclaim not observable and retain the exact missing tooling.
5. A route is `observed` only with an actual artifact at the stated observation
   boundary; `environment noise` requires a reproducible non-semantic device/tool
   difference; `not observable` means the requested boundary cannot be seen with
   available tooling; `missing coverage` means the route was not run or did not
   reach a valid settled checkpoint. Passing widget tests alone never upgrades an
   Android pixel route to observed.

### P4V B5 pre-declared regression/reproducibility threshold (2026-09-14)

This threshold is recorded before interpreting the paired raw numbers. A valid
category regression requires all of: (a) both baseline and candidate runs are
hook=false, 120Hz, vsync-paced, category-scoped frames>=300, and app/driver
cross-source valid; (b) candidate `P99 - baseline P99 >= 4000µs` and is also at
least 10% of the baseline P99; and (c) the same-direction P99 regression is
reproduced by a second independently seeded pair under the same device/build/
fixture conditions. One noisy pair is only an observed delta, not a regression.
`worst`, j8/j16/j33 and `maxStreak` are reported as supporting raw signals and
must not be silently replaced by P99. Any non-environmental fixed-checkpoint
pixel difference, I1-I8 production violation increase, semantic anomaly/blank/
ghost/duplicate content, or test failure remains an immediate revert trigger
under the P4V package even if this performance threshold is not reached.

### P4V follow-up evidence append (2026-09-14; Relay audit response)

This is an append-only follow-up. The preceding B1/B2 list, observation mapping,
threshold, P4 history, and existing P1-P4 rows are unchanged.

#### Settled screenshot seam and B3

The follow-up added a test/driver-only settled capture path using
`IntegrationTestWidgetsFlutterBinding.convertFlutterSurfaceToImage()` and
`takeScreenshot()` after the existing semantic settled predicate, with two
additional vsync-paced frames before capture. The driver writes PNG bytes only
under runner-provided `NIGHT_READER_SCREENSHOT_DIR`; the runner restores that
environment variable and retains the finite iteration/timeout, fixture watcher,
and 120-second no-progress watchdog. There is no production runtime knob.

The fixed matrix pair (seed `9145003`) captured real Reader surface PNGs for
ordinary reading, long scroll, chapter jump, typography (font size/line height/
letter spacing), theme/textColor, padding, simplified/traditional conversion,
and source reload. Raw RGB differences were: initial 0; ordinary 43 pixels,
ratio 0.00001176, MAE 0.001611, max 137; long scroll 0; chapter jump 0;
typography 0; theme/textColor 0; padding 0; conversion 0; source reload 0.
Ordinary's 43-pixel result is retained as tiny environment/capture noise; the
others are observed equal at the fixed checkpoint.

The first matrix TTS capture was invalid/missing coverage because candidate was
a Replacement Rules sheet. After explicit transient-sheet cleanup and a second
settle, the dedicated TTS pair (seed `9145004`) produced initial diff 0 and TTS
settled diff 312,976 pixels, ratio 0.08561362, RGB MAE 0.754087, max 67,
`gt10=121,510`. The raw candidate PNG visibly contains only the Reader header/
title region followed by a large blank content area while baseline contains the
full Reader page. Classification: observed candidate visual divergence, not
environment noise. Hook invariants being zero does not erase this pixel result.

#### B4 deterministic hook-on

Seed `9145005`, same `visual_checkpoint_matrix` action and hook-on, now yields
the same final semantic state:

| field | baseline=true | candidate=false |
|---|---:|---:|
| semantic / completed action | passed / 1 | passed / 1 |
| action marker | `#0 visual_checkpoint_matrix` | `#0 visual_checkpoint_matrix` |
| I1-I8 violations / suspected anomalies | 0 / 0 | 0 / 0 |
| final phase / queue | ready / 0 | ready / 0 |
| final location | c4, char36, visual0 | c4, char36, visual0 |
| layout / epoch / reset | 4 / 4 / 18 | 4 / 4 / 18 |
| visible keys / contiguous / missing | `4:0,4:1,4:2` / true / `[]` | `4:0,4:1,4:2` / true / `[]` |

The prior end-state divergence is not reproduced with the deterministic fixed
checkpoint and is classified as an action/settling/runner observation race,
not a reproduced semantic regression. This does not waive the separate TTS
pixel divergence.

#### B5 second seed

`scroll_slow` was rerun with seed `9145006`, 35 iterations, profile mode,
hook=false, 120 Hz, vsync-paced input, category-scoped frames>=300, and
app/driver cross-source valid. Raw operation-attribution metrics in µs:

| metric | baseline | candidate | delta |
|---|---:|---:|---:|
| frames | 609 | 613 | +4 |
| P50/P95/P99 | 100500 / 100500 / 100500 | 100500 / 100500 / 100500 | 0 / 0 / 0 |
| worst | 216109 | 209906 | -6203 |
| j8/j16/j33 | 609 / 608 / 608 | 613 / 613 / 613 | +4 / +5 / +5 |
| maxStreak | 609 | 613 | +4 |
| taskP99 / vsyncP99 | 2500 / 28000 | 7000 / 27500 | +4500 / -500 |
| buildP99 / rasterP99 | 7000 / 119500 | 9000 / 120500 | +2000 / +1000 |

Both paired runs were semantically passed and cross-source valid, while the
strict performance gate failed on the emulator timing/raster tail. The first
`scroll_slow` seed `9142001` also had P99 delta 0; `scroll_fast` seed `9142002`
had P99 delta +1000. Therefore no category satisfies the pre-declared
`candidate P99 - baseline P99 >= 4000µs and >=10%` plus second-seed same-direction
reproduction rule.

#### B6/B7 and disposition

Android pixel coverage is now observed for ordinary/long/jump/style/theme/
textColor/padding/conversion/same-source reload at the fixed settled boundary.
Font family, rotation, real TTS highlight following, different-source switch,
cache hit/miss, and overdraw/layer-specific proof remain not observable or
missing with exact reasons recorded in the evidence report; host/widget tests
are not promoted to Android pixel claims.

Because the integration test, driver, and runner changed, both variants were
rerun: `flutter analyze` had no issues; `flutter test test/features/reader_v2`
was `220 passed, 0 failed`; full `flutter test` was `1041 passed, 0 failed` for
both baseline=true and candidate=false, with matching test lists/counts.

Follow-up recommendation: do not mark P4V visual/semantic closure complete.
Relay should review the reproducible candidate TTS blank-content screenshot as
an acceptance/revert trigger. The final source is intentionally left at the
retained candidate value `isRepaintBoundary=false` per the worker package; no
production optimization, P4 completion-record write/move, or P4 history edit
was made.

### P4V follow-up / revert decision (2026-09-14; Relay-directed)

This append-only entry records Relay's acceptance decision. It does not modify
P4 history, the P4 completion report, the preceding P1-P4 rows, or the P4V
completion record.

The explicit revert trigger was the dedicated fixed-checkpoint Android TTS
pair:

- baseline=true artifact: `artifacts/android-reader/p4v5-b3-baseline-tts-seed-9145004`
- candidate=false artifact: `artifacts/android-reader/p4v5-b3-candidate-tts-seed-9145004`
- same device: `emulator-5554`, Android 17/API 37, 1280x2856, 120 Hz
- same fixture/font/viewport/seed/action and in-app settled capture boundary

Raw screenshot metrics for `interaction-tts-1.png` were:

| metric | value |
|---|---:|
| diff pixels | 312,976 |
| image pixels | 3,655,680 |
| diff ratio | 0.08561362 |
| RGB MAE | 0.754087 |
| max channel difference | 67 |
| pixels with channel difference >10 | 121,510 |
| baseline visual | complete Reader正文 |
| candidate visual | Reader header/title followed by blank正文 area |

The initial pair was identical (`diff pixels=0`). Both TTS action runs reported
semantic `passed`, `phase=ready`, `queue=0`, and I1-I8 violations `0`, but those
semantic results do not invalidate the independent pixel observation. The
candidate blank正文 was therefore classified as a reproducible non-environment
fixed-checkpoint visual failure, satisfying the P4V revert policy.

Safe rollback executed immediately after Relay's decision:

```dart
// lib/features/reader_v2/hybrid/view/cached_block_widget.dart:199
bool get isRepaintBoundary => true;
```

This was the only production source change in the rollback. All p4v/p4v5
artifacts and evidence remain retained. The final production state is now
`true`. No runtime switch was added, and no attempt was made to hide, reclassify,
or explain away the TTS blank.

Post-rollback validation:

```text
flutter analyze
flutter test test/features/reader_v2
flutter test
```

Results after rollback: `flutter analyze` reported no issues;
`flutter test test/features/reader_v2` reported `220 passed, 0 failed`; full
`flutter test` reported `1041 passed, 0 failed`. The full suite was finite and
completed normally. No P4V completion record was filled or moved.

## P4O 條件式操作／進入優化（追加；2026-09-14；不改寫 P1–P4）

### Trigger and method

P4G 的有效類別表已有多個指標超過未變更的 8ms gate，故 P4O 必須執行。本段
只追加 P4O 證據，不修改 P4、P4G、P4V 歷史或 completion record。P4V 的安全
控制是 production `bool get isRepaintBoundary => true;`；H1 候選期間也未改動
此值，候選回退後目前 source 仍為 `true`。所有 Android workload 均使用
`pwsh -NoProfile -ExecutionPolicy Bypass` 呼叫既有
`tool/run_android_reader_workload.ps1`，profile build、`emulator-5554`、
`NightReader_120Hz`、vsync-paced、hook=false；runner 的 bounded iterations、
fixture watcher 與 120 秒 no-progress watchdog 均保留。沒有使用 hook-on 作
效能判定，沒有 7200 秒或無上限 workload。

P4O 的單變量 queue 順序為 H1→H2→H3→H4→H5。P4G 的 layout task 與 raster
歸因先決定優先級：H1–H3/H5 針對 layout/restore，H4 針對 conversion frame；
目前可觀測資料顯示 raster 長尾約 110–125ms，而 layout task P99 大多
2–7ms，且 navigation/entry 沒有有效 P4G baseline。因此不把排版或 restore
猜測當成改善，亦不捏造未量測的 navigation/entry 數字。

### P4O control measurements (raw)

下列 artifact 都有明確 action marker、exclusive action window、app/driver
各自 frames >=300、120Hz active mode、hook=false 與 runner
`crossSourceValidation.status=valid`。時間單位：frame/task/conversion 為 µs；
`j8/j16/j33` 是超過 8.33/16.67/33.33ms 的 frame counts。每個 run 的
`driver-response-data.json`、`metadata.json`、`continuous-samples.jsonl`、
logcat 與 finite-run ancillary artifacts 均保留。

| identity / artifact | app/driver frames | P50/P95/P99/worst | j8/j16/j33 | maxStreak | taskP99 | buildP99 / rasterP99 (app) | driver buildP99 / rasterP99 (ms) | conversion duration P50/P95/P99/worst | first-readable P50/P95 | fully-stable P50/P95/P99 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `scroll_slow`, `p4o-control-scroll-slow-seed-9151001` | 364/333 | 100500/100500/100500/214869 | 364/363/363 | 364 | 5000 | 8000/117000 | 7.429/116.977 | 1004685/1116614/1356751/1356751 | 116770/126005 | 965965/1083381/1324715 |
| `scroll_slow`, `p4o-control-scroll-slow-seed-9151002` | 379/345 | 100500/100500/100500/214161 | 379/379/379 | 379 | 4000 | 8500/118500 | 7.496/116.318 | 1018084/1270457/1413875/1413875 | 122680/143550 | 982370/1233581/1386997 |
| `scroll_fast`, `p4o-control-scroll-fast-seed-9151001` | 1712/1679 | 100500/100500/100500/231412 | 1712/1711/1711 | 1712 | 7000 | 8500/112000 | 7.104/110.653 | 5031756/5215193/5312256/5312256 | 741508/786069 | 5002270/5185958/5285630 |
| `scroll_long_distance`, `p4o-control-scroll-long-seed-9151001` | 718/682 | 100500/100500/100500/250769 | 718/718/717 | 718 | 6000 | 10500/122000 | 10.303/121.709 | 5132241/5524261/5524261/5524261 | 784058/915762 | 5101526/5492037/5492037 |
| `interaction_menu_open_close`, `p4o-control-interaction-menu-seed-9151003-18` | 346/313 | 100500/100500/100500/225094 | 346/346/346 | 346 | 0 | 12000/118500 | 11.621/118.125 | 1071864/1128661/1150712/1150712 | 363683/384862 | 1071864/1128661/1150712 |

The first menu attempt, `p4o-control-interaction-menu-seed-9151003`, was retained
but invalid under A4 because it had only 201 app / 175 driver frames; it is not
used as evidence. The valid menu rerun above used 18 actions. The P4O controls
confirm the P4G attribution: all inspected scroll categories and the interaction
transition fail the unchanged 8ms category gate, while the layout task signal is
not the dominant residual in these runs. Conversion wall-clock values remain raw
diagnostic observations and do not relax the per-frame gate.

### H1 — adjacent-chapter first-prefix priority

Hypothesis: after reading chapter N, promote the first 12 blocks of adjacent
chapters N±1 from `LayoutTaskPriority.prefetch` to `visible`, leaving cache
capacity 512, dragging prohibition, paragraph grouping, restore semantics and
repaint boundary unchanged. This was one production scheduling variable in
`hybrid_reader_screen.dart`; it was not combined with any other hypothesis.

Baseline/candidate pairs were run with the same seed, fixture, device, profile
mode and `scroll_slow` identity. Raw operation-attribution values:

For each H1 workload the driver emitted the P4G A1 identity markers
`READER_CONTINUOUS_ACTION seed=9151001 #0..#19 scroll_slow` or
`READER_CONTINUOUS_ACTION seed=9151002 #0..#19 scroll_slow`; each completed
20 actions, and `continuousResult.operationAttribution` recorded
`exclusiveAction=true`, `frameScope="performance window contains only this
forced action"`, `semanticStatus=passed`, `finalPhase=ready`,
`finalQueueDepth=0`, and `invariantViolationCount=0`. The same marker and
checkpoint definition was used for the paired controls.

| seed / variant / artifact | app/driver frames | P50/P95/P99/worst | j8/j16/j33 | maxStreak | taskP99 | buildP99 / rasterP99 (app) | driver buildP99 / rasterP99 (ms) | duration P50/P95/P99/worst | first-readable P50/P95 | fully-stable P50/P95/P99 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 9151001 baseline / `p4o-control-scroll-slow-seed-9151001` | 364/333 | 100500/100500/100500/214869 | 364/363/363 | 364 | 5000 | 8000/117000 | 7.429/116.977 | 1004685/1116614/1356751/1356751 | 116770/126005 | 965965/1083381/1324715 |
| 9151001 H1 / `p4o-h1-candidate-scroll-slow-seed-9151001` | 382/346 | 100500/100500/100500/235077 | 382/382/381 | 382 | 2000 | 9500/125000 | 8.056/124.855 | 1074114/1191588/1240003/1240003 | 131834/193934 | 1022897/1158677/1216872 |
| 9151002 baseline / `p4o-control-scroll-slow-seed-9151002` | 379/345 | 100500/100500/100500/214161 | 379/379/379 | 379 | 4000 | 8500/118500 | 7.496/116.318 | 1018084/1270457/1413875/1413875 | 122680/143550 | 982370/1233581/1386997 |
| 9151002 H1 / `p4o-h1-candidate-scroll-slow-seed-9151002` | 362/331 | 100500/100500/100500/225556 | 362/362/362 | 362 | 3500 | 8500/124000 | 8.178/117.340 | 1006558/1095642/1432199/1432199 | 123544/157329 | 961872/1067167/1392149 |

Both pairs were valid cross-source measurements and semantically completed with
the usual `actionMarkers`, `phase=ready`, `queue=0`, and zero invariant violations.
The H1 candidate reduced task P99 on both seeds (5→2ms, 4→3.5ms), but did not
reduce frame P99 (all app P99 remained 100.5ms) or raster tail; candidate raster
P99 was 125ms and 124ms versus baseline 117ms and 118.5ms. Conversion and
first-readable values were not improved consistently. Decision: **revert H1**;
no H1 production change remains. The candidate artifacts are retained for audit.

### H2–H5 — finite disposition

These hypotheses were evaluated in queue order after H1 and were not run as
production candidates because the required causal measurement or safe boundary
was absent. They are explicitly not passes, and no navigation/entry baseline is
fabricated.

| hypothesis | baseline / one-variable requirement | disposition and evidence |
|---|---|---|
| H2 first-chapter prelayout | Needs valid `entry_cold_open_book` or `entry_hot_open_book` category-scoped app/driver baseline (frames >=300 plus first-readable/fully-stable), then exactly one open scheduling change | **Not executed.** Current hybrid cold open enters `_positionHybridViewport → _restoreCore`, whose target chapter and guaranteed window are synchronously required for the anchor/visible invariant; P4G has no valid cold/hot entry artifact. Existing non-hybrid `openBook` `scheduleOpen` is not the active hybrid path. Moving it or adding speculative UI-isolate work without an entry baseline would be unsafe and unmeasurable. |
| H3 target-chapter prelayout | Needs valid `navigation_*` baseline and conversion markers, then only target prelayout ordering may change | **Not executed.** Current hybrid `jumpToChapter/jumpToLocation` already loads the target and gives its anchor task priority through `_restoreCore`; P4G navigation identities were invalid or missing. There is no valid target conversion baseline against which a candidate can be judged, and speculative concurrent target layout would alter restore ownership/epoch timing. |
| H4 conversion-frame reduction | Needs actual per-frame conversion attribution showing which frames are removable while preserving state updates, plus valid interaction/navigation conversion baseline | **Not executed.** Existing telemetry has aggregate category frame timing and conversion duration markers, but no per-frame operation/state attribution that identifies necessary versus removable frames. Valid menu data still shows raster P99 118.125ms and no per-frame cause breakdown; page/TTS/navigation are invalid or missing. Deleting frames or state updates would risk visual/semantic regressions, especially given P4V's independent TTS blank evidence. |
| H5 restore/layout off critical path | Needs valid navigation/entry restore timing and a correctness-safe idle boundary, with no UI-thread pump during dragging | **Not executed.** `_restoreCore` owns anchor readiness, index reset, pinning, pump state and `completeReady`; P4G has no valid navigation/entry category. Deferring this sequence without a measured idle window can violate P3 I1–I8 and dragging pump prohibition. No safe one-variable candidate exists under the available evidence. |

### P4O conclusion and coverage boundary

The trigger is met and P4O was executed with one measured H1 candidate. H1 is
reverted because it did not improve the category frame/raster evidence. The valid
controls establish residual category failures rather than a performance pass:
`scroll_slow`, `scroll_fast`, `scroll_long_distance`, and
`interaction_menu_open_close` all have P99 100.5ms and raster P99 110.653–121.709ms
in the current emulator/profile environment. The remaining bottleneck is therefore
supported as raster/overall frame-tail attribution, with build/layout as a
secondary signal; the existing driver export still cannot identify per-layer
overdraw, implicit saveLayer counts, or per-frame conversion causes.

Navigation (`navigation_next_chapter`, previous, directory, directory-then-read,
bookmark) and entry (hot/cold) remain unverified because P4G supplied no valid
category-scoped baseline. Page and TTS remain invalid/missing under the known
harness/device limitations. No real 120Hz device was available; these are
emulator-only observations. Cache capacity remains 512, dragging-time pump
prohibition remains intact, and P3 I1–I8 correctness paths were not changed.

## P5 知識沉澱與 runner guardrail 覆核（追加；2026-09-14）

本段只追加 P5 的 durable knowledge、L3 覆核與實務檢查，不修改 P1–P4、P4G、
P4V、P4O 的既有列、歷史或 completion record。P5 package 仍留在
`docs/changes/planning/`，completion record 由 Relay 獨立驗收與歸檔。

### Durable / batch-local 分界

下列內容可跨批次保留，已分別落在 `DEVELOPMENT.md`（可執行工具與環境規則）
及 `docs/night_reader/reader.md`（Reader 結構事實）：

- 有效 Reader profile 效能窗口必須是 vsync-paced、active mode 120Hz、有效窗口
  （指定操作時為 category-filtered window）至少 300 frames、有 action marker、
  `completedActions > 0`、app/driver cross-source 相符，且 hook 關閉；任一前提
  不成立只能 `invalid`，不得產生 pass/fail。
- debug continuous 是功能、race 與逐幀 invariant 觀察；profile + driver +
  hook=false 才是效能判定路徑。P99 不可由不足樣本、其他操作或整個 session 補足。
- PowerShell 7 `pwsh -NoProfile` 是 runner 的必要 supervisor 環境；Windows
  PowerShell 5.1 的 `ProcessStartInfo.ArgumentList` 為 `null`，會在 adding
  arguments 階段失敗。有限 iterations/duration/timeout、fixture watcher 與
  no-progress watchdog 仍是必要安全邊界。
- L-05 `setIsComplexHint` 已否證；L-07 AVD `config.ini` 的 GPU flag 不是 runtime
  GPU 證據；L-08 `gfxinfo Total frames rendered` 不是 Flutter timing；一次效能
  迭代只改一個變因。
- Reader 的 debug-only I1–I8 hook 預設關閉，啟用時才建立 compact frame record
  與 bounded violation history；P3 的 progress publication、ballistic restore/
  pump starvation 與共用 drawer transition race 修復及其 settled/ownership
  守衛仍是目前結構事實。
- P4V rollback 後 `RenderCachedBlock.isRepaintBoundary` 的安全 production 值是
  `true`。P4O H1 已回退，H2–H5 沒有在缺少 valid navigation/entry baseline 或
  因果安全邊界時執行。8ms gate 仍 failed；目前已支持的剩餘方向是
  emulator/profile 條件下的 raster/overall frame tail，並非 performance pass 或
  真機結論。

以下只屬本批次 local records，不搬入長期操作文件或 Reader map：seed、單次
artifact 路徑、逐類別 P50/P95/P99/worst 表、P4V raw pixel diff、P4O H1 的數字、
以及當時的 runner/logcat 痕跡。它們保留在本 ledger 的歷史區段、P4V evidence
與已歸檔 completion reports，後續 agent 不應把它們重跑成新的假設；若需要新的
結論，仍須依同一有效性規則取得新證據。

### L1 / L2 落點

- L1 已在 `DEVELOPMENT.md` 增補可直接執行的 `pwsh -NoProfile` continuous
  command、120Hz/profile/driver 前提、debug/hook 與 profile/performance 的互斥
  用途、logcat 的診斷邊界、fail-closed invalid 條件、有限 workload/watchdog，
  以及 L-05/L-07/L-08、P99 樣本數與 single-variable do-not 清單。
- L2 已在 `docs/night_reader/reader.md` 增補 debug hook seam/enablement、P3
  progress/ballistic/restore/harness 修復、`isRepaintBoundary=true` 的 rollback
  狀態與 P4/P4O residual attribution。實驗矩陣與 raw table 沒有搬入 map；操作
  前提只透過文件交叉引用，避免與 L1 重複。

### L3 runner guardrail 覆核

沿用既有 `performance.invalidReasons` shape；P5 只補了可自動化且已有明確來源
的缺口，沒有改 gate 或另造 validity mechanism：

| 項目 | 自動化狀態 | 覆核結果 |
|---|---|---|
| 120Hz | 已自動化 | runner 檢查 `SurfaceFlinger activeMode.*vsyncRate=120.00 Hz`。 |
| frame lower bound | 已自動化 | app 與 driver source 各自至少 300；指定 scroll/interaction/navigation/entry action 時，另檢查 app operation attribution 的 exclusive category window 至少 300。 |
| marker / category validity | 已自動化 | runner 核對可解析的 `READER_CONTINUOUS_ACTION`、requested seed/action；有 category attribution 的指定操作必須匹配 category、`exclusiveAction=true` 與固定 frame scope。 |
| hook / performance separation | 已自動化 | app 回報的 hook state 必須與 runner 旗標一致；hook-on 是 observed；debug continuous 永遠是 observed，不能成為 performance pass；profile performance 才評估 strict P99。 |
| cross-source | 已自動化 | driver JSON、TimelineSummary、app telemetry 必須存在；build/raster 使用既有 20% 或 1ms tolerance，frame count 使用 20% tolerance；不符即 invalid。 |
| finite execution | 已自動化 | continuous iterations、duration、effective timeout 有上限；fixture replacement watcher 與 120 秒 no-progress watchdog 保留，watcher 失敗時 supervisor 也會終止 child process。 |
| gfxinfo / AVD GPU / P99 方法 | 文件化 | 這些訊號的錯誤語意不能由 runner 從單一輸出可靠推斷；`gfxinfo` 僅 ancillary，GPU 改查 SurfaceFlinger `GLES:`，P99 樣本與 interpretation 留在 DEVELOPMENT。 |
| one-variable-per-iteration | 文件化 | 這是實驗設計與 review 規則，不是 workload validity；留在 DEVELOPMENT，不讓 runner 替實驗做因果判定。 |

因此 L3 沒有放寬 P2 validity，也沒有把 debug continuous、hook-on、不足樣本、
非 120Hz 或 cross-source mismatch 轉成效能 pass。runner 的實際程式變更只在
`tool/run_android_reader_workload.ps1`：補 action/seed/category window 核對、修正
hook state 變數遮蔽、debug mode observed 路徑與 strict P99 disable define，並在
watcher 例外時清理 driver child process。

### Fresh-reader practical check

把 `DEVELOPMENT.md` 交給沒有本批次對話歷史的 agent，要求它做一次正確的
120Hz Reader validation，答案是：**對 routine continuous validation 已足夠**。
它能從 `adb devices -l` 取得當次 serial，使用 `pwsh -NoProfile` runner，選
`profile` + `continuous` + 有限 iterations/timeout，知道 initial restore 不算窗口，
知道 300 frames、vsync-paced、120Hz、marker、cross-source、hook=false 是共同
前提，並知道 invalid 要看 `metadata.json` 的 `performance.invalidReasons`；也能
用 debug + hook 做語意驗證而不把它當 performance pass。

仍需明確保留的非 routine 依賴：真正的實機 120Hz 結果、缺失的 navigation/entry
category baseline、TTS 真實 platform callback/highlight-following，以及
cache/overdraw/layer-specific attribution 尚未由現有工具觀察；這些不是文件可
憑空補出的結論。未來若要宣稱改善，仍需 Relay/人員依同一操作 identity、單變因
與有效窗口重新取得證據。其餘 runner 命令、環境坑與目前 Reader 安全狀態已不需
依賴本批次口頭記憶。

### P5 狀態

P5 的 durable 文件與 L3 覆核已寫入 shared worktree；本段是 planning ledger 的
append-only worker evidence。P5 completion record 刻意留空，交由 Relay 驗收後填寫
並歸檔。

## P6 monkey final gate（追加；2026-09-14，worker evidence）

本段是 P6 worker 的 append-only evidence。P1–P5、P4G、P4V、P4O 的 archived
package/report/ledger history 未重開或改寫；P6 package 仍留在
`docs/changes/planning/`，completion record 留給 Relay acceptance。所有 Android
結果均為 `NightReader_120Hz` Android 17/API 37 emulator、120Hz
`SurfaceFlinger activeMode`（非 real-device evidence）。

### P6 implementation and action inventory

P6 保留原有 17 actions，加入 11 個由現有 test-only seam 支援的安全路徑；每個
action 執行後都回到 `phase=ready`、`initialRestoreCompleted=true`、無 scrolling/
dragging、`pumpQueueDepth=0`、visible keys contiguous、無 missing paragraph 或
pending jump 的 settled checkpoint。第一個 seeded permutation 保證 28/28 breadth；
每個 gate run 使用 finite `Iterations=28`、`TimeoutSeconds=900`，runner 仍具
fixture watcher、120 秒 no-progress watchdog 與 30 秒 bounded ADB command。

| action | 主要風險 |
|---|---|
| `small_scroll_up`, `small_scroll_down` | incremental admission、前後 anchor restore |
| `large_scroll_up`, `large_scroll_down` | 大範圍前後向 admission |
| `fling_up`, `fling_down` | ballistic layout supply、settling |
| `reverse_direction` | ballistic reversal、I8 |
| `next_chapter`, `previous_chapter` | 相對章節邊界、progress commit |
| `random_chapter` | drawer jump operation token、restore |
| `far_forward_jump`, `far_backward_jump` | 書尾／書首 distant admission |
| `pause` | async operation 間 settling |
| `background`, `foreground` | lifecycle pause/resume、progress flush |
| `reopen_reader` | cold route exit、reopen restore |
| `tts_toggle_while_scrolling` | TTS ensure/follow 與 scrolling 競合 |
| `style_typography` | font size、line height、letter spacing、indent cache key |
| `style_theme_text_color` | textColor freshness、ParagraphCache invalidation |
| `style_padding` | viewport padding、LayoutSpec rebuild |
| `style_chinese_conversion` | displayText length、charOffset clamp |
| `scroll_during_transition` | ballistic scroll 與 presentation invalidation |
| `long_chapter_cache_pressure` | distant chapters、ParagraphCache 512 capacity |
| `short_chapter_chain` | short chapter transitions、boundary anchors |
| `book_boundaries` | book start/end clamp |
| `rapid_drawer_jump_competition` | drawer route、concurrent jump tokens |
| `ballistic_chapter_switch` | chapter switch while ballistic active |
| `reload_content` | content reload/source pipeline、segmentation freshness |

Existing seam inventory and skips:

| 未執行 route | 原因 |
|---|---|
| `font_family_change` | current fixture/test support 沒有既有 font-family seam；不新增產品 runtime knob |
| `rotation_pair` | 沒有安全的 in-process orientation/device rotation seam；viewport padding 已覆蓋可達的 viewport 變因 |
| `different_source_switch` | workload 只有單一本地 fixture，沒有安全的第二 source path；source switch 不憑空造 fixture |

`setTypographyForTesting` 使用既有 test helper 並補上既有 `debugSettings.setTextIndent(2)`；
scroll、fling、lifecycle、reload、jump 與 TTS 路徑均使用既有 runtime/test seam。原本
會在同一 pointer drag 期間更改設定的 artificial transition 被改為可達的 ballistic
transition；這是 harness correctness，不是產品功能改動。

### Two complete seeded monkey outputs

Both runs used `debug` + `NIGHT_READER_MONKEY_ENABLE_INVARIANTS=true`, full 28-action
coverage, finite timeout, and the post-bootstrap P3 hook. Raw compact records below are
from `workload-logcat.txt`; the full action markers and JSON are retained beside them.

```text
READER_MONKEY_RESULT_SUMMARY status=passed semanticStatus=passed seed=9260108 requestedIterations=28 effectiveIterations=28 completed=28 fullActionSetCovered=true suspectedAnomalies=0 finalPhase=ready finalQueueDepth=0 productionInvariantViolationCount=0 productionInvariantCounts=I1:0,I2:0,I3:0,I4:0,I5:0,I6:0,I7:0,I8:0 harnessInvariantCounts=I1:0,I2:0,I3:0,I4:0,I5:0,I6:0,I7:0,I8:0 actionCounts=small_scroll_down:1,tts_toggle_while_scrolling:1,style_theme_text_color:1,previous_chapter:1,large_scroll_up:1,fling_up:1,foreground:1,style_padding:1,reload_content:1,fling_down:1,next_chapter:1,scroll_during_transition:1,large_scroll_down:1,style_chinese_conversion:1,pause:1,style_typography:1,long_chapter_cache_pressure:1,reverse_direction:1,rapid_drawer_jump_competition:1,far_backward_jump:1,random_chapter:1,small_scroll_up:1,book_boundaries:1,ballistic_chapter_switch:1,far_forward_jump:1,background:1,reopen_reader:1,short_chapter_chain:1 skippedActions=font_family_change: no existing test seam or fixture route,rotation_pair: no safe in-process orientation/device rotation seam; padding is covered,different_source_switch: one local-book fixture and no safe second-source seam
READER_MONKEY_RESULT_SUMMARY status=passed semanticStatus=passed seed=9260109 requestedIterations=28 effectiveIterations=28 completed=28 fullActionSetCovered=true suspectedAnomalies=0 finalPhase=ready finalQueueDepth=0 productionInvariantViolationCount=0 productionInvariantCounts=I1:0,I2:0,I3:0,I4:0,I5:0,I6:0,I7:0,I8:0 harnessInvariantCounts=I1:0,I2:0,I3:0,I4:0,I5:0,I6:0,I7:1,I8:0 actionCounts=fling_up:1,foreground:1,background:1,small_scroll_up:1,style_typography:1,large_scroll_up:1,far_backward_jump:1,ballistic_chapter_switch:1,fling_down:1,scroll_during_transition:1,far_forward_jump:1,reload_content:1,book_boundaries:1,style_chinese_conversion:1,style_padding:1,small_scroll_down:1,short_chapter_chain:1,reopen_reader:1,previous_chapter:1,random_chapter:1,style_theme_text_color:1,long_chapter_cache_pressure:1,rapid_drawer_jump_competition:1,reverse_direction:1,pause:1,tts_toggle_while_scrolling:1,large_scroll_down:1,next_chapter:1 skippedActions=font_family_change: no existing test seam or fixture route,rotation_pair: no safe in-process orientation/device rotation seam; padding is covered,different_source_switch: one local-book fixture and no safe second-source seam
```

The second run's one `harness I7` was retained and reported, not downgraded or hidden;
production I1–I8 counts stayed zero. Earlier bounded smoke artifacts are also retained:
`p6-smoke-all-seed-9260101` (artificial same-pointer transition failure),
`p6-smoke-all-seed-9260102` (late TTS ballistic tail),
`p6-smoke-all-seed-9260103` (composite cache-pressure settle),
`p6-smoke-all-seed-9260104` (real textColor I2 before fix),
`p6-smoke-all-seed-9260105` (reload-tail I8), `p6-smoke-all-seed-9260106`
(conversion-tail I7), plus invalid ADB-preparation runs `p6-smoke-all-seed-9260107`
through `...107d`. Invalid/preparation runs are not gate passes.

### P6 bug and harness evidence

The reproducible production issue was stale visible ParagraphCache freshness after a
settled `textColor` widget update: Android smoke `p6-smoke-all-seed-9260104` recorded a
production I2. The minimal fix in `HybridReaderScreen.didUpdateWidget` calls the existing
epoch rebuild and restores the captured location after textColor changes; no runtime knob
or UI was added. The regression test `textColor 變更先隔離舊 ParagraphCache 再 restore`
was run against a temporary pre-fix source and failed with `Expected: empty / Actual:
[{chapterIndex: 0, blockIndex: 0}, {chapterIndex: 0, blockIndex: 1}]`; the fixed source
then passed targeted, Reader, and full suites. A separate I8 test confirms a cross-epoch
reload restore is not compared as one physical ballistic stream.

The initial hook timing, artificial drag transition, late TTS physics, and continuous
cross-action snapshot were diagnosed as harness boundaries. The continuous probe now
clears its previous snapshot at `beginAction`, so a deliberate previous-chapter jump
cannot be judged against the preceding action's coordinate world; the existing
`suspectedAnomalies` check itself remains active. This is why the profile run below has
`suspectedAnomalies=0` without weakening the check.

### Journey and profile continuous evidence

`p6-journey-final` passed (`All tests passed!`, workload duration about 26.1 s) and
restored the normal debug APK. The final profile driver run was finite:
`BuildMode=profile`, hook=false, seed `9260403`, 35 iterations, 600-second timeout,
standard `flutter drive --profile --no-dds`; it completed 35 actions in about 209.4 s.
The runner observed a package-replacement fixture race and re-pushed the fixture; this
was recorded by the watcher. It produced a valid cross-source profile result with
`appFrames=8315`, `driverFrames=8165`, 120Hz, `semanticStatus=passed`,
`suspectedAnomalies=0`, `finalPhase=ready`, `finalQueueDepth=0`, hook=false, and no
`invalidReasons`.

| source | totalSpan/frame P99 | build P99 | raster P99 | vsync P99 | Layout task P99 |
|---|---:|---:|---:|---:|---:|
| app telemetry | 45000 µs | 5000 µs | 22000 µs | 13500 µs | 3000 µs |
| driver TimelineSummary | not exported by TimelineSummary | 4.687 ms | 21.855 ms | not exported | not exported |

The app totalSpan/frame P99 remains above the strict `<8000µs` target, so runner status
is `failed` by the existing performance gate; this is a valid measurement and a ceiling/
failure interpretation, not a performance pass. It is consistent with P4's conclusion
that raster/overall frame tail remains the bottleneck under this emulator/profile setup.
The P4 `RenderCachedBlock.isRepaintBoundary` production value remains `true`; P4O H1
remains reverted and H2–H5 remain not executed without valid baselines.

### Final verification and evidence split

Verified: `flutter analyze` passed; `flutter test test/features/reader_v2` passed with
222 tests; full `flutter test` passed with 1043 tests; two independent complete monkey
seeds passed semantic/invariant gate with zero production I1–I8 violations; journey
passed; profile continuous completed with valid 120Hz/cross-source evidence and correctly
failed the strict P99 target; normal debug APK restoration completed after each runner.
The current source check is `lib/features/reader_v2/hybrid/view/cached_block_widget.dart:199`
`isRepaintBoundary => true`.

Unverified: no real-device evidence; font-family mutation, in-process rotation, and
second-source switch were skipped for the seam reasons above; TTS platform playback and
highlight following are not real-device validated; no layer/overdraw/per-frame raster
causal attribution was added; profile TimelineSummary does not provide app vsync/task P99.

Inference: the textColor fix addresses the observed I2 cache-freshness failure, and the
continuous reverse-jump report was a harness cross-action coordinate-world false positive;
both are supported by the pre-fix regression test / Android artifact and by the bounded
post-fix runs, but do not expand the evidence into real-device or strict performance
claims. No workload process or test APK was intentionally left after the restoration
path; the AVD itself remains running for later local work.

### P6 Relay acceptance (2026-09-14)

Relay independently reran `flutter analyze` (no issues),
`flutter test test/features/reader_v2` (222 passed), and the complete
`flutter test --reporter compact` suite (1043 passed), then ran `git diff --check`.
The source remains `cached_block_widget.dart:199` with
`isRepaintBoundary => true`, so the P4V rollback is preserved. P6 is accepted as the
functional/invariant final gate: both complete seeds covered 28/28 actions and had zero
production I1–I8 violations; seed `9260109` retains its single harness-only I7.
The profile continuous result is valid but still fails the unchanged strict
`totalSpan P99 < 8000µs` gate, and is not reclassified as a pass. The package's
explicitly skipped routes and emulator-only evidence boundary remain in force.
