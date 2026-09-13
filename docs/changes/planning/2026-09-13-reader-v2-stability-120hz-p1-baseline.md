---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: implement
EXECUTION_ROUTE: claude-p
---

## Goal

把目前未提交的 Reader V2 診斷／harness 工作整理成**一個乾淨、全綠、可歸因的 baseline commit**：
保留所有有證據的診斷能力與已驗證修復，抽出三項建立在無效量測上的 production 行為改動，
並讓後續每個 package 的 diff 都能獨立審查。

## Problem / Root Cause

working tree 目前累積了約 16 個 tracked 修改 + 1 個未追蹤測試檔，全部未 commit。其中混雜了兩類性質完全不同的東西：

1. **有證據的診斷能力與已驗證修復** —— telemetry 擴充、`debugSnapshot()`、continuous workload、runner 擴充、
   test seam、以及一個已定位並修復的 production bug（切章後底部進度標籤沿用上一章）。
2. **三項改動了 production 行為、但依據是無效量測的東西**。

第 2 類的根因是：前一輪的每次 profile run **只執行 1 個 action、只產生 16～19 個 frame**
（見 `artifacts/android-reader/continuous-validation-120hz-profile-slow-scroll-*/metadata.json` 的
`"frames": 16/17/19`、`"completedActions": 1`）。16 個樣本的 P99 等同次大值；而且
`tester.pump(Duration(milliseconds: 65))` 兩次之間完全沒有幀，每一幀都是閒置後一次位移 70px 的冷幀。
**這不是 120Hz 連續滾動的量測。** 因此以下三項改動沒有有效依據：

- `android/app/src/main/AndroidManifest.xml`：把 `EnableImpeller=false` 從 `<activity>` 移到 `<application>`，
  讓全域 renderer opt-out 真正生效。這會改變**所有真實使用者**的 renderer，而依據只有 16 vs 17 個樣本
  （Impeller P99 92ms vs Skia 28ms）。Flutter 也已把 Impeller opt-out 標為 deprecated。
- `lib/features/reader_v2/hybrid/view/cached_block_widget.dart`：`RenderCachedBlock.isRepaintBoundary`
  由 `true` 改為 `false`。**零實機數據** —— 唯一一次驗證 run 在 Gradle build 階段被中止。
- 與上一項耦合的註解／測試不一致（前一輪回報 `hybrid_scroll_view.dart` 的註解仍描述 block 為 repaint boundary）。

把這三項固化進 baseline，等於把無效量測的結論寫進歷史與正式版，且會讓後續 package 無法區分
「效能差異是誰造成的」。

## Background

- 專案處於 feature freeze（`AGENTS.md`），只做維護、修復、效能與相稱重構。
- `artifacts/` 已在 `.gitignore` 第 58 行；`/build/` 是 root-anchored，因此 `android/build/` **沒有**被忽略，
  目前以未追蹤狀態出現在 `git status`。
- 本批次的交付政策是：**只有這個 package 建立 commit**，P2～P6 都不 commit。
- 本 package 開始前，前一輪執行者已停止，沒有 process 在跑，沒有 rollback，working tree 保持原狀。
- 前一輪回報的最後一次完整 `flutter test` 是在較早的修改狀態下通過 1026 tests；
  **目前這個精確的 working tree 尚未重跑過 full suite**。這是本 package 必須補上的證據。

## Recommended Solution

分三步：先確定實際狀態，再抽出，最後驗證並提交。

**抽出的定義**：把這三項還原成 `HEAD` 的內容，而不是「改成另一個你覺得更好的值」。
`AndroidManifest.xml` 還原後會回到「`EnableImpeller=false` 存在但位置無效、實際跑 Impeller」的狀態
—— 這正是目前正式版的行為，baseline 就應該是它。
meta-data 位置本身確實可疑，但「要不要修位置」與「值該是什麼」是 P4 在有效量測下的決定，不在這裡處理。
把這個觀察記進 ledger，不要在本 package 順手修。

抽出的內容不要丟掉：ledger 的 L-04 / L-06 已經登記了這兩個假設，P4 會據此重做 A/B。
不需要另外保存 patch 檔。

## Implementation Steps

1. 以 `git status --short` 與 `git diff --stat` 取得**當下真實**的修改清單。
   不要沿用任何既有描述的檔案數 —— 前一輪與本輪 planner 的快照都可能已過期。
2. 逐一檢視 diff，把每個修改檔分類為「保留」或「抽出」。抽出集合為：
   - `android/app/src/main/AndroidManifest.xml`
   - `lib/features/reader_v2/hybrid/view/cached_block_widget.dart`
   - 任何**只因上述兩項而存在**的耦合修改（例如 `hybrid_scroll_view.dart` 的註解、
     `test/features/reader_v2/hybrid/cached_block_repaint_test.dart` 中為配合
     `isRepaintBoundary=false` 而調整的斷言）。
   判定方式：把該修改與這兩項一起還原後，`flutter analyze` 與相關測試仍應全綠。
   如果某個修改在還原後造成失敗，代表它其實不屬於抽出集合，把它留下並在完成報告說明。
3. 用 `git checkout -- <path>` 逐檔還原抽出集合。**不要**用 `git checkout .`、
   `git reset --hard` 或任何會波及其他檔案的操作。
4. 在 `.gitignore` 加入 `android/build/`（放在既有 Android 相關忽略規則附近，附一行說明是 Gradle 產生物）。
5. 確認保留集合內容正確，特別是這兩項必須存在：
   - `HybridReaderScreen` 在 restore 完成後呼叫 `_publishProgress()`（已驗證的 production bug 修復）
   - `test/features/reader_v2/hybrid/hybrid_reader_screen_test.dart` 中對應的
     「`runtime.jumpToChapter` 後 progress 不得沿用上一章」regression test
6. 跑完整驗證（見 Acceptance）。**任何一項不綠就先修到綠再 commit**，
   不要用 skip 或放寬斷言的方式讓它通過；若失敗來自抽出動作本身，回到步驟 2 重新判定分類。
7. 建立**單一** commit。commit message 要說清楚這是診斷能力 baseline，
   並明確記載「三項未驗證的 production 行為改動已抽出，待有效量測後由 P4 重做 A/B」。
8. 更新 ledger（`docs/changes/planning/2026-09-13-reader-v2-stability-120hz-ledger.md`）：
   在 L-04 與 L-06 的「結論」欄補上「已於 P1 從 baseline 抽出，還原至 HEAD」，
   並新增一列記錄 `AndroidManifest.xml` 在 HEAD 的 `EnableImpeller` meta-data 位於 `<activity>` 內、
   實際無效這個觀察。ledger 的修改一併進這個 commit。

## Expected Change Surface

- `.gitignore`
- `android/app/src/main/AndroidManifest.xml`（還原）
- `lib/features/reader_v2/hybrid/view/cached_block_widget.dart`（還原）
- 上述兩項的耦合檔（還原）
- `docs/changes/planning/2026-09-13-reader-v2-stability-120hz-ledger.md`
- 其餘保留檔案不做內容修改，只是納入 commit

## Acceptance

- `git status --short` 在 commit 後只剩下**已忽略**或**本批次尚未產生**的內容；
  `android/build/` 不再出現在未追蹤清單。
- `git show --stat HEAD` 顯示**單一** commit，且抽出集合的三項不在其中。
- `git diff HEAD~1 HEAD -- android/app/src/main/AndroidManifest.xml` 為空。
- `git diff HEAD~1 HEAD -- lib/features/reader_v2/hybrid/view/cached_block_widget.dart` 為空。
- `flutter analyze` 通過，輸出無 error（既有 warning 維持原狀即可，不得新增）。
- `flutter test` 完整跑過並全綠。**要貼出實際的通過數字**（前一輪在較早狀態是 1026 tests，
  本次數字不必相同，但必須是實際輸出而非引述）。
- `flutter test test/features/reader_v2` 全綠，且其中包含
  「切章後 progress 不得沿用上一章」的 regression test 實際執行通過。
- ledger 的 L-04、L-06 已更新，且新增了 `EnableImpeller` meta-data 位置的觀察列。
- **不得改變**：任何保留檔案的行為；不得順手修 `EnableImpeller` 的位置或值；
  不得新增、刪除或改寫任何既有測試的斷言強度。

## Constraints

- 只建立一個 commit。不 push。
- commit message 結尾加上：`Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`
- 目前分支是 `main`，本 package **就在 main 上 commit**（這是使用者確認的 baseline 交付方式）。
- 不得使用 `git reset --hard`、`git clean`、`git stash drop` 或任何會丟失未追蹤檔案的操作。
  `integration_test/reader_continuous_test.dart` 是未追蹤的新檔案且**必須被納入 commit**。

## Starting Points

- `docs/night_reader_index.md` → `docs/night_reader/reader.md`（Reader 模組邊界與 Known Risks）
- `AGENTS.md`（feature freeze、驗證要求）
- `DEVELOPMENT.md`（120Hz AVD、continuous workload 操作方式）
- `docs/changes/planning/2026-09-13-reader-v2-stability-120hz-ledger.md`
- `artifacts/android-reader/continuous-validation-120hz-profile-slow-scroll-*/metadata.json`
  （`frames` / `completedActions` 欄位是量測無效的直接證據；此目錄已被 gitignore，只作閱讀參考）

## Completion record

_(Relay 在驗收後填寫)_
