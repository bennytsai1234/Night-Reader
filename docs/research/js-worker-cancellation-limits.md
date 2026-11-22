# 書源規則 JS 停止與校驗 isolate 數量上限研究

日期：2026-11-17  
基準分支：`beta`  
研究分支：`research/js-worker-cancellation-limits`  
範圍：讀取現行程式、#358 的證據及 QuickJS 橋接原始碼；不修改 App 功能，不開 PR。

## 結論

目前「同時校驗 8 個書源」限制的是尚未回報結果的校驗任務，**不是仍在執行的校驗 isolate**。逾時會立刻將任務回報為完成，即使對應 isolate 的規則 JS 尚未離開同步原生執行，排程仍會再開下一個。多個 `while (true) {}` 可以累積超過 8 條未退出的校驗 isolate。

`Isolate.immediate` 已在 #358 確認可能與 QuickJS 回呼 Dart 造成 SIGSEGV；不可直接改回。應分開解決「讓 JS 安全離開」和「未退出前不再建立無上限的 isolate」：

- **根本中斷**：對 Android 的 QuickJS runtime 做原生中斷處理（限時及取消旗標），讓純 JS 無窮迴圈也能退回 Dart 的 `evaluate`，再由現有 `beforeNextEvent` 完成退出。
- **資源防線**：針對臨時校驗 isolate 建立跨批次的實際存活額度，額度從建立時取得、只在 `Isolate.spawn(onExit: ...)` 真正回報退出後歸還；達上限時停止派發新的校驗，而不是無限制再開。
- 單靠「JS 回呼 Dart 時檢查停止旗標」只能覆蓋有回呼的規則，不能解決 `while(true){}`，且 JS 可能自行捕捉並吞掉回呼拋出的錯誤，不應作為唯一中斷手段。

**研究狀態**：以上是程式控制流程分析及上游原始碼審閱；尚未在 Android 16 手機的實際原生函式庫上跑壓力測試，沒有捏造 CPU、記憶體或中斷延遲的數值。

## 現況與可重現路徑

1. `lib/core/source_check/check_source_service.dart`：`CheckSourceService._sourceCheckConcurrency = 8`；`_SourceCheckExecutionPool.run` 的八個非同步迴圈，在 `await checkSource(...)` 返回後立即從佇列領下一個書源。
2. `lib/core/source_check/source_check_isolate.dart`：`spawnSourceCheck` 每個書源開新的 `SourceWorker`；到 `Timer(timeout)` 時 `finish(null)` 呼叫 `worker.kill`，隨即 `completer.complete(null)`。此時仍未證明 isolate 真的退出。
3. `lib/core/engine/source_isolate/source_isolate.dart`：`SourceWorker.kill` 先關信箱、釋放限流紀錄、拒絕未完成結果，再呼叫 `_isolate.kill(priority: Isolate.beforeNextEvent)`。若同步原生 `evaluate` 永不返回，這條 isolate 不會進入下一事件。
4. 同檔 `SourceWorker._spawn` 確實有 `Isolate.spawn(onExit: exit.sendPort)` 與 `exit.listen`，但目前 `SourceWorker._onExit` 是在 `kill()` 中直接執行（只用來清 `SourceIo._worker`），**不能當成真的退出確認**。目前 `_live` 也在 `kill()` 立刻移除，不代表實際存活數。
5. `SourceIsolate.workerCount = 4` 是平常搜尋、閱讀、下載使用的常駐書源 isolate；這次超額風險主要來自一個書源一條的臨時校驗 isolate。AI 網站檢查、試抓、規則修復和登入也有額外 `SourceWorker.spawn` 呼叫點，若擴充全域資源上限，須一起界定範圍。

形式化地說，某一瞬間的實際校驗 isolate 數量是「仍在排程中的工作」加上「已停止但尚未真正退出」。前者最多 8，後者在現行流程沒有獨立額度。若一批有 N 個永不退出的書源，可能留下最多 N 個累積的校驗 isolate，而非恆定 8 個；跨批次仍可能持續累積。

## QuickJS 現成 timeout 是否可用

- `lib/core/engine/js/js_engine.dart` 使用 `getJavascriptRuntime()` 建立 JS 引擎；`third_party/flutter_js/lib/flutter_js.dart` 在 Android 建立 `QuickJsRuntime2()`，**沒有指定 timeout**。
- `third_party/flutter_js/lib/quickjs/quickjs_runtime2.dart` 已有 `timeout` 與 `memoryLimit` 參數；`_ensureEngine` 把 `timeout ?? 0` 傳進原生 `jsNewRuntime`。
- 專案 Android 依賴 `com.github.fast-development.android-js-runtimes:fastdev-jsruntimes-quickjs:0.3.6`。檢查該專案目前公開的 `quickjs/src/main/c/quickjs_runtime.cpp`（master）：它透過 `JS_SetInterruptHandler` 安裝中斷函式，但只有 `timeout && start && (clock()-start)>...` 時才中斷；`start` 在 `jsNewRuntime` 初始化為 0，在檢查到的原始碼中找不到設為非零的地方。換句話說，**單純傳 timeout 很可能無法生效**。
- 此段檢查針對上游 master，**未驗證實際打包的 0.3.6 Android .so 是否同版實作**；要在該函式庫上執行有限時的純 JS 無窮迴圈，才能確定。原生 `clock()` 還是 CPU 時間，與使用者期待的實際經過時間不完全相同。
- 桌面 QuickJS 測試使用 `test/fixtures/quickjs` 內的另一份橋接函式庫。桌面測試通過，不可直接推論 Android 0.3.6 已經能中斷。
- iOS 走 JavaScriptCore，不共用 Android QuickJS 中斷機制；若要全平台保證需另外研究 iOS 執行時間限制。

上游檔案：https://github.com/fast-development/android-js-runtimes/blob/master/quickjs/src/main/c/quickjs_runtime.cpp  
QuickJS 中斷 API：`JS_SetInterruptHandler(runtime, handler, opaque)`（回傳非零要求終止目前 JS 執行）。

## 候選做法與工程取捨

| 做法 | 純 JS 無限迴圈 | 持續回呼 Dart 的 JS | 真正限制存活 isolate 數量 | 代價與限制 |
| --- | --- | --- | --- | --- |
| A. 每次 JS 回呼 Dart 檢查停止旗標 | 無效 | 可在回呼時拋錯 | 否 | 需跨 isolate 共用可見的原子停止狀態；不能靠普通 Dart bool。回呼不發生就無法停止；JS 捕捉錯誤時可能繼續跑。 |
| B. QuickJS 原生中斷處理 | 可在 QuickJS 安全點中斷 | 可在 QuickJS 安全點中斷 | 不能單獨保證，仍需處理尚未退出的時間窗 | 要驗證／修改原生橋接與 Android 發布函式庫；中斷不保證打斷卡在 Dart/網路等宿主回呼內的等待，須保留現有信箱及網路取消。 |
| C. 真正的 onExit 實體額度，例如 8 條臨時校驗 isolate | 不會終止 | 不會終止 | 是，限制新建立的臨時校驗 isolate | 所有額度若都被死迴圈佔住，後續校驗必須停止派發或等候；使用者應看到「資源被未退出的校驗占滿」，而不是進度顯示還在完成。 |
| B + C | 可 | 可 | 是 | 修改範圍最大，較完整地解決停止及資源問題；需壓力測試確認 #358 的 SIGSEGV 不再發生。 |

建議驗證順序：先確認當前 `timeout` 在實際 Android 函式庫有無作用；接著在隔離原型中實驗 B，並用 C 作為失效保護。A 可以加速特殊的回呼型規則停止，但不適合單獨採用。是否把 C 擴及 AI 修復與登入、實體額度是「8 條校驗」還是「全 App 臨時 isolate 共用額度」，需先確認跨功能工作量後由維護者決定。

## 同條件原型驗證方案（尚未執行）

在可執行 Android arm64 App 的環境、相同機型／同一組規則／相同編譯模式下，保留 #358 的 `beforeNextEvent`，比較「現行」、「A」、「B」、「C」、「B+C」五組：

1. **純計算**：`while (true) {}`，取消與逾時後量到實際 `onExit` 的時間；必須有獨立程序及外部 watchdog，不能讓無窮迴圈卡住整組測試。
2. **Dart 回呼密集**：`java.toast` 確認開始後，反覆呼叫 `java.md5Encode`；每種方案至少 20 輪，監看 SIGSEGV 與 Android `ApplicationExitInfo`，比對 #358 既有回歸案例。
3. **網路與嵌套規則**：`java.ajax`、巢狀 `java.getString`、`jsLib`、`try/catch` 吞掉錯誤等，核對取消後不再對書源產生後續副作用。
4. **資源壓力**：同批放 1、8、16、32 個會逾時的規則，再重開第二批；量邏輯校驗數、`onExit` 前實際存活數峰值、Android 執行緒數、CPU 使用率、PSS/RSS、主程式操作延遲、耗電／溫升，並確認額度滿時不再 spawn。
5. **正常書源**：同一批正常書源的搜尋、目錄、正文通過率及執行時間，驗證中斷檢查的額外成本與誤中斷；也要觀察主程式四條常駐書源 isolate 不受校驗配額阻擋。

判定條件：不出現 #358 的原生閃退；純 JS 死迴圈能按預期停止（B）；臨時校驗 isolate 的真實存活數不超過設定硬上限（C）；正常書源與閱讀流程不能因資源額度長期停住。

## 尚缺證據與限制

目前已完成程式路徑、已有回歸測試、QuickJS Dart FFI 封裝與上游原生碼審閱。沒有可用的 Flutter/Dart SDK 及可用 Android 裝置執行環境；GitHub 連線只足夠讀檔和建立研究分支，無法在此直接跑上述原型與量測。因此「timeout 在 Android 0.3.6 無效」目前是**待驗證的高優先假設**，不是實測結論。

本文不改 `TODO.md`、ADR、App 程式或測試，不開 PR。取得實測再決定是否進入修正階段。

## 實作

照「B + C」做了（分支 `fix/rule-js-interrupt`）：

- **B，中斷**：沒有用函式庫原本只看時間、`start` 不會被設的 `timeout`，改用 QuickJS 本身的 `JS_SetInterruptHandler` 裝夜讀自己的處理：一個放在原生記憶體的停止旗標（`JsInterruptFlag`，`third_party/flutter_js/PATCHES.md` 的 `nightreader.7`），處理只讀旗標。主 isolate 替每個書源 worker 建一個，`SourceWorker.kill` 舉起；worker 裡之後建的 QuickJS runtime 都裝上。isolate 真的結束（`onExit`）後才釋放。實際打包的 Android 0.3.6 `.so` 有匯出 `JS_SetInterruptHandler`（讀 `.aar` 裡 arm64 的動態符號表確認）。
- **C，上限**：臨時 worker（`SourceWorker.spawn`：校驗、AI 修書源的工具、網站檢查、登入）同時最多 12 條，算到 `onExit` 才還；常駐的四條與網路 isolate 不算。滿了就等，等的時候能取消；書源校驗的 handle 立刻交回，等名額時按停止也有作用，逾時從 worker 開好才算。被結束 60 秒還沒真的結束的（停不下來：iOS 的規則 JS、卡在 Dart 正規表示式裡的）記一筆 App 日誌、讓出名額：一直佔著的話，累積到 12 條後校驗、AI 修書源、登入全部停住、沒有提示，比改前（多耗電）更糟。研究原本寫「滿了就停止派發、讓使用者看到」，這裡選讓出名額，不另做提示。
- 測試在 `test/core/engine/source_worker_places_test.dart`（自己一個檔：別的測試結束的 worker 可能還卡著、佔著名額）：名額、取消、60 秒讓出（測試裡縮短）、校驗等名額時停止，用 Dart 的同步 `sleep` 佔住 worker，各平台都跑；`while (true) {}` 與包在 `try／catch` 裡的迴圈停下那兩項只在有 `JS_SetInterruptHandler` 的函式庫上跑，Windows 測試用的沒有，所以只在 CI 的 Linux 跑。

還沒做：iOS 的 JavaScriptCore 沒有中斷，卡住的規則照舊停不下來，60 秒後不再佔名額，isolate 照舊留著；常駐書源 isolate 裡被取消的工作不中斷它的規則 JS（同一條 isolate 上可能是別的工作的 JS 在跑），只有結束 worker 時才中斷。

