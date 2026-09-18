---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: implement
EXECUTION_ROUTE: claude-p
---

## Goal

把 120Hz profile continuous workload 的 session `totalSpan P99` 壓到 **8000µs 以下**；
若做不到，必須提出**具證據的剩餘瓶頸**，證明它不屬於 Reader 的結構，而不是用 functional pass 掩蓋。

這是一個**迭代 package**：量測 → 分解歸因 → 提一個假設 → 最小改動 → 重量 → 保留或回退，
直到出口條件成立。使用者已確認：**跑到達標或撞到天花板才回報**，中途不中斷。

## Problem / Root Cause

前一輪的分解顯示 raster 是壓倒性的大頭：

| 情境 | totalSpan P99 | task P99 | build P99 | vsync P99 | raster P99 |
|---|---|---|---|---|---|
| pure slow scroll, Impeller | 92ms | 2.5ms | 4.0ms | 4ms | 88.5ms |
| pure slow scroll, Skia | 28ms | 3.0ms | 3.5ms | 9ms | 23ms |
| 含 chapter jump, Impeller | 100.5ms | 2.5ms | 14.5ms | 56ms | 66ms |

**方向可信，倍率不可信。** 這些 run 每次只有 16～19 個 frame、只跑 1 個 action，
且每幀都是閒置 65ms 後一次位移 70px 的冷幀（詳見 P2）。所以：

- **已否證**：`LayoutPump` 的 Paragraph layout task 不是瓶頸（ledger L-01，
  task 絕對值 2.5–3ms 遠低於 8ms budget，這個結論不受樣本數影響）。
- **已否證**：純 scroll 的 widget rebuild 不是瓶頸（ledger L-02，build 3.5–4ms）。
- **方向成立**：raster / composition 是大頭（ledger L-03）。
- **待重測**：所有具體倍率，以及 Impeller vs Skia 的差距（ledger L-04）。P2 會在有效窗口下重跑。

`profile-patch-v2` 的 build 14.5ms 與 vsync 56ms 出現在含 chapter jump 的情境，
與 pure scroll 的數字差距很大，值得單獨歸因，但同樣要等有效窗口。

## Background

- **本 package 的前提是 P2 已完成**。在有效量測窗口建立前，任何效能改動都無法判定，
  這正是前一輪三項改動被從 baseline 抽出的原因。
- 使用者已確認的判定方式：**gate 是 `totalSpan P99 < 8000µs`，不放寬**；
  build / raster / vsync / task 分開記錄只用於歸因，不能取代 gate。
- 使用者已確認：允許在證據支持下做**結構改良**（layout scheduling、重複 paragraph measure、
  cache、cancellation / generation 等 Reader 核心結構），不限定只能打補丁。
- 使用者已確認：**跑到達標或天花板才回報**。
- Emulator 走 host GPU（GL translator 接 GTX 1660 SUPER），**不是** CPU 軟體光柵（ledger L-07）。
  不要再花時間在「emulator 沒有 GPU」這條假設上。
- 顯示是 1280×2856、480dpi。emulator 的 raster 成本不等於真機；
  gate 在 emulator 上判定這件事本身就是已知限制，出口條件已為此保留了第二條路。

## Recommended Solution

### S1 — 迭代規則

每個迭代：

1. 跑一次有效量測（必須通過 P2 的全部有效性檢查，否則該次不計）。
2. 分解歸因：totalSpan / build / raster / vsync / task，以及發生 jank 時的 Reader 狀態
   （pump queue depth、admission lead、visible block 數、當時是 drag / ballistic / jump 哪一種）。
3. **查 ledger**，確認這個假設沒被試過。
4. 提出**一個**假設，做**最小**改動。一次只動一個變因。
5. 重量。
6. 有效則保留，無效或惡化則**回退**，兩種結果都寫進 ledger 的 P4 迭代表。

**絕對不要**在一個迭代裡同時改多個東西 —— 前一輪的教訓就是 renderer 與 render 結構
的改動混在一起，最後沒有任何一項有乾淨數據。

### S2 — 假設佇列（起始順序，可依證據調整）

1. **`RenderCachedBlock.isRepaintBoundary = false`**（ledger L-06）。
   前一輪已寫好但零數據，P1 已還原。這是第一個要在有效窗口下判定的假設。
   注意：若採用，`lib/features/reader_v2/hybrid/view/hybrid_scroll_view.dart` 中
   描述 block 為 repaint boundary 的註解必須同步更新。
2. **renderer 決定**（ledger L-04）。P2 已在有效窗口下重跑 Impeller vs Skia A/B。
   本 package 依那份數據決定要不要動 `AndroidManifest.xml`。
   **這是全域、影響所有真實使用者的決定**，若要改，完成報告必須明確說明：
   有效窗口下的實測差距、Impeller opt-out 已被 Flutter 標為 deprecated 的風險、
   以及這個決定只在 emulator 上驗證過、未在真機驗證。
3. **paint 路徑本身**。`RenderCachedBlock.paint()` 對每個 block 做 clip 後 `drawParagraph`。
   一個 continuation group 內多個 block 可能共用同一個 `ui.Paragraph` 卻被分成多個
   block window 分別繪製 —— 同一段文字被 clip 繪製多次。
   若證據支持，這是結構改良的正當範圍。
4. **含 chapter jump 情境的 build 14.5ms / vsync 56ms**。與 pure scroll 差距很大，
   單獨歸因；可能與 admission 大量放行、DocumentIndex reset 或 setState 範圍有關。

**已否證、不要重試**：`setIsComplexHint()`（ledger L-05，raster 從 88.5ms 惡化到 116ms）。

### S3 — 出口條件（二擇一）

**A. 達標** —— 有效量測下 session `totalSpan P99 < 8000µs`，
且該結果可用不同 seed 重現至少一次。

**B. 具證據的天花板** —— 同時滿足：

- Reader 可歸因的成分（`build` 與 `layout task`）在有效窗口下都明確低於 8ms budget；
- raster 是唯一的超標成分；
- **對照實驗**證明同一台 emulator 上，一個結構明顯更簡單的等面積捲動畫面
  （例如純 `ListView` 加等量 `Text`，相同 viewport 與字級）也無法達到 raster P99 < 8ms。
  這是把「emulator 光柵天花板」與「Reader paint 結構問題」分離的決定性證據；
  沒有這個對照，就不能宣稱是天花板。
- 完成報告明確標示：此結論只在 emulator 上成立，**未在真機驗證**。

出口為 B 時，**不得**把 `performance.status` 寫成 `passed`。維持 `failed` 或
新增一個明確的 `blocked-by-environment` 狀態，並在 metadata 記錄對照實驗的數字。

## Implementation Steps

1. 確認 P2 的有效性檢查全部可用，取得 baseline 有效量測（ledger P4 迭代表第 0 列）。
2. 依 S2 的佇列逐一推進，每個迭代遵守 S1 的規則。
3. 每個迭代結束立即更新 ledger 的 P4 迭代表 —— 包含回退掉的假設。
4. 若證據指向需要結構改良，先在 ledger 寫清楚「哪一份數據支持這個結構有問題」，
   再動手。結構改良同樣要遵守「一次一個變因」。
5. 每次改動後都要確認 `flutter test test/features/reader_v2` 仍然全綠；
   結構改良後要額外跑 `flutter test` 全套與 debug continuous run，
   確認沒有破壞 P3 建立的正確性成果。
6. 達到 S3 的 A 或 B，收尾。

## Expected Change Surface

- `lib/features/reader_v2/hybrid/view/`（`cached_block_widget.dart`、`hybrid_scroll_view.dart`）
- `lib/features/reader_v2/hybrid/pump/`、`measure/`（若結構改良觸及排程 / 度量 / 快取）
- `android/app/src/main/AndroidManifest.xml`（僅在 renderer 決定要改時）
- `test/features/reader_v2/hybrid/`（結構改良對應的測試）
- `docs/changes/planning/2026-09-13-reader-v2-stability-120hz-ledger.md`

## Acceptance

- ledger 的 P4 迭代表完整記錄每個迭代：假設、改動、frames、
  totalSpan / build / raster / vsync / task 的 P99、判定、保留或回退。
  **包含所有被回退的假設**。
- 每一列的量測都通過 P2 的有效性檢查（frames ≥ 300、雙來源相符、vsyncRate 120、hook 關閉）。
- 出口為 A：貼出達標的實際數字，以及不同 seed 的重現結果。
- 出口為 B：貼出 build / task 低於 budget 的數字、raster 為唯一超標成分的分解、
  以及對照實驗的完整數字與實作方式。
- `flutter analyze` 通過；`flutter test` 全綠（貼實際數字）。
- P3 建立的逐幀 invariant 在最終狀態下仍然零 `production` 違反
  （跑一次 debug continuous run 確認結構改良沒有引入新的排版錯誤）。
- `journey` scenario 仍可通過。
- **不得改變**：`strict120HzFrameP99TargetMicros = 8000` 不得放寬；
  不得把 `failed` 或天花板結論寫成 `passed`；
  不得為了數字好看而縮短 workload、減少 action 或移除高成本情境。

## Constraints

- 一次只動一個變因。
- 不得重試 ledger 中已否證的假設。
- 不 commit。
- renderer 這種全域影響的決定，若要改，必須在完成報告單獨列出風險與未驗證範圍。
- 不得在效能 run 中開啟 P3 的逐幀 invariant hook。

## Starting Points

- `docs/changes/planning/2026-09-13-reader-v2-stability-120hz-ledger.md`（**先讀這個**）
- `lib/features/reader_v2/hybrid/view/cached_block_widget.dart`：`RenderCachedBlock.paint()`、
  `isRepaintBoundary`
- `lib/features/reader_v2/hybrid/view/hybrid_scroll_view.dart`：sliver 的 paint 與 layer 結構
- `lib/features/reader_v2/hybrid/core/hybrid_types.dart`：`LayoutTask`、
  `groupBlocks`、`combinedText`（continuation group 的定義）
- `lib/features/reader_v2/hybrid/telemetry/hybrid_telemetry.dart`：分解欄位
- `docs/night_reader/reader.md` 的「連續段落 group 與動態 segmentation」風險段
- `tool/run_android_reader_workload.ps1`：P2 建立的 driver 路徑與有效性檢查

## Completion record

### Status: ACCEPTED

- **Accepted by:** Relay
- **Executor:** GPT coding worker（`claude-p` 只保留為既有 package route metadata；本環境未使用 Claude CLI）
- **Commit / push:** 無；符合本 package 的 no-commit constraint
- **Acceptance date:** 2026-09-13

### 結論

P4 沒有達成 strict `totalSpan P99 < 8000µs`。依本 package 的第二條出口，已
建立受限於目前 emulator/control 條件的 raster ceiling attribution；因此不得
把 `performance.status=failed` 改寫成 `passed`，也沒有放寬
`strict120HzFrameP99TargetMicros = 8000`。

有效 Reader run 顯示 `RenderCachedBlock.isRepaintBoundary = false` 比 P2
baseline 有實際改善，但不同有效 run 仍有 emulator/workload noise，且
`totalSpan` 仍遠高於 8ms。renderer A/B 與 paint-path clip-elision 沒有證明
改善，均已回退。等 viewport、同一份 fixture 與相同 action 規模的 lazy
chunked `ListView` control，其 build/task 已低於 budget 而 raster 仍遠高於
budget，支持「目前 emulator/control 的 raster ceiling」這個有限結論；這不
是 Reader strict pass，也不宣稱所有真機都有相同物理上限。

### Delivered

- 依 P2 有效性條件執行 P4 迭代：120Hz SurfaceFlinger、至少 300 app/driver
  frames、35 actions、app/driver cross-source validation、hook 關閉。
- 保留 `RenderCachedBlock.isRepaintBoundary => false`，並同步修正 sliver 的
  layer composition 註解。
- 暫時嘗試 renderer A/B；沒有證明 Skia 改善 raster，已還原
  `AndroidManifest.xml` 到 P1 baseline。
- 暫時嘗試對單一 block 省略冗餘 `clipRect`；結果惡化，已回退 paint-path 改動。
- 新增只供量測的 lazy chunked equal-area `SimpleScrollControl`，沒有把 control
  route 帶入 production Reader。
- 保留 package replacement watcher、每 2 秒 action progress 觀測與 120 秒
  no-progress watchdog；continuous runner 維持有限 iterations、duration 與
  timeout，不允許無上限長跑。
- 將 PowerShell 5.1 / PowerShell 7 的 runner 相容性根因記入 shared ledger，並
  同步補進 Android 操作 skill 與 `DEVELOPMENT.md`。

### Iteration evidence

所有下列有效列均為 profile、120Hz、hook=false、35 actions、semantic passed、
cross-source valid；`performance.status=failed` 僅表示 strict P99 gate 未達，
不是量測窗口無效。

| 迭代 | 有效 frames（app / driver） | app total / build / raster / vsync / task P99 | 判定與處理 |
|---|---:|---|---|
| 0 baseline | 2106 / 2074 | 100500 / 11500 / 118500 / 29000 / 3500µs | valid、strict failed；保留 baseline |
| 1a `isRepaintBoundary=false`, seed 9132050 | — | — | INVALID：PowerShell 5.1 runner 在 `ProcessStartInfo.ArgumentList` 加參數時失敗；後續 pwsh 重跑另有 semantic anomaly，未取數字作效能結論 |
| 1b boundary change, seed 9132026 | 9550 / 9377 | 41000 / 4000 / 21000 / 11000 / 3000µs | valid、strict failed；相對 baseline 有改善，保留 |
| 1c boundary change, seed 9132073 | — | — | INVALID：`previous-chapter-start-target-26` reverse-jump anomaly；不分類為效能 regression |
| 1d boundary final reproduction, seed 9132026 | 5898 / 5801 | 75000 / 6000 / 40500 / 19500 / 4000µs | valid、strict failed；保留已證明優於 baseline 的變更 |
| 2 renderer A/B（Skia） | 9335 / 9189 | 40000 / 3500 / 21000 / 11500 / 2500µs | valid、strict failed；raster 未改善，manifest 回退 |
| 3 paint clip-elision | 10214 / 10056 | 42000 / 4000 / 21500 / 13500 / 3000µs | valid、strict failed；相對 1b 惡化，回退 |
| 4 chapter-jump attribution | 4867 / 4683 | 45500 / 4500 / 19500 / 22000 / 2000µs | valid、strict failed；jump window build/task 已低於 budget，保留 attribution |
| 5a giant `Text` control | — | — | INVALID／主動中止：單一 53MB `Text` 每個 action 約 30 秒，不適合作為有限 control；沒有使用任何 P99 |
| 5b lazy chunked equal-area control | 1351 / 1259 | 100500 / 7000 / 56500 / 18000 / 0µs | valid control、strict failed；build/task <8ms 而 raster 遠超 budget，保留為 emulator-only ceiling evidence |

Reader 的 valid run 中，build 與 layout task 都低於 8ms；超標集中在 raster，
另外的 vsync overhead 也被單獨保留為 framework/emulator timing layer，不能
被誤寫成 Reader layout/task 問題。5b control 在相同 emulator/viewport/fixture
下以 lazy `ListView` 顯示約 2000 字 chunks、執行 35 個 simple-scroll actions，
driver TimelineSummary 為 `build P99=6.672ms`、`raster P99=56.174ms`，並以
app telemetry 交叉驗證。這支持的是 emulator/control ceiling attribution，
不是所有硬體與真機的物理定理。

### Runner shell handoff

初始 runner 是由 Windows PowerShell 5.1 的 `powershell -NoProfile` 啟動；該
版本的 `.NET ProcessStartInfo.ArgumentList` 為 `null`，所以在 adding arguments
階段出現 null-valued expression。後續所有有效 driver run 改用 PowerShell 7：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tool\run_android_reader_workload.ps1 ...
```

這是 shell/runtime compatibility pitfall，不是 production bug，也不是 P2
measurement 根因。直接 `flutter drive` 可以成功，是因為它繞過了這個 supervisor
path。watcher/no-progress harness patch 仍必要，不能因切換 `pwsh` 而移除。

### Verification

- `flutter analyze`：Relay independent run `No issues found! (ran in 22.1s)`。
- `flutter test test/features/reader_v2`：Relay independent run `212 tests passed`。
- `flutter test --reporter compact`：Relay independent run `1033 tests passed`。
- `git diff --check`：無 whitespace error；僅有既有 LF/CRLF conversion warnings。
- P3 的 post-fix debug continuous 與 `journey` 證據仍保留；P4 沒有修改 P3
  invariant 語義，效能 run 全部 hook-off。
- `AndroidManifest.xml` 的 renderer 暫時變更已回退；沒有新增 release APK、
  publish、commit 或 push。

### Verified / unverified / inference

- **Verified:** P4 每個迭代的有效性／無效性分類、boundary improvement、renderer
  與 paint-path 的 negative result、lazy control 的 cross-source ceiling
  evidence、host analyze/full tests，以及 120Hz emulator evidence。
- **Unverified:** strict Reader `totalSpan P99 <8000µs`、真機 raster 結果，以及
  control ceiling 是否可代表其他 GPU／解析度／Android 裝置。
- **Inference:** 在目前 emulator、viewport、fixture 與 control 條件下，raster／
  compositor 或 emulator timing layer 是主要剩餘限制；這不等同於已證明 Reader
  paint path 在所有真機上沒有可優化空間。
