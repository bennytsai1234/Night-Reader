# Reader V2 儀器成本與 sliver fallback 稽核（2026-09-15）

分類：`audit`。本文件用來把兩個一直靠「設計氣味」爭論的主張，換成可覆核的
程式碼與實驗證據。兩者都**不**支持原本提出的大重構。

## 主張一：「correctness/oracle instrumentation 是 120Hz 幀延遲最大來源之一」

**不成立（release build）。**

`hybrid_reader_screen.dart` 4,476 行中有 2,184 行（48.8%）屬於 instrumentation，
但其中 **2,133 行（97.7%）在 release 編譯期消除**。原因是每個讀取點都把
`kDebugMode` 放在 `&&` 的第一個運算元（或把 `!kDebugMode` 放在 `||` 前面），
而 `kDebugMode` 是 `const bool`（`flutter/foundation/constants.dart:64`），
release 下常數摺疊為 `false`，連 static field 的讀取都不會留下。

release 下確認為零的項目：frame invariant 全鏈、`HybridFrameInvariantRecord`
建構、`HybridTemporalOracle`、`ReaderVisualOracle`、`RepaintBoundary.toImage()`
全畫面像素回讀、telemetry heartbeat timer、build() 內的 visual injection。
**visual oracle 的 `RepaintBoundary` 在 release 從不建立**。

`debugFrameInvariantsEnabled` / `debugVisualOracleEnabled` 雖是可變 `static bool`，
但 `lib/` 內沒有任何寫入者，也不是 `bool.fromEnvironment`；所有讀取點都被
const-false 的 `kDebugMode` 短路。

release 確實存在的成本全部來自 **telemetry（不是 oracle）**：
`hybrid_reader_screen.dart:1473` 的 `addTimingsCallback(_handleFrameTimings)`
未 gate，每幀做 4 次 240 長度 Queue 的 push/pop 與 4 次直方圖 bucket 遞增；
滾動期間每幀一次 `updateRuntimeStats`；每個 layout task 一次 `recordLayoutTask`。
量級是常數級整數運算，與「最大來源之一」的主張不相稱。

**結論**：把 oracle 搬出 `lib/` 的收益是可維護性，不是 runtime。用「釋放
CPU／記憶體」當作重構理由不成立。

未量測項目：telemetry 每幀成本的絕對值；`onReportTimings` 回呼是否推遲下一幀；
`_visualOracle?.finish()`（未 gate 的 dispose 呼叫）是否讓 oracle 留在 AOT
snapshot 內（只影響體積）。

## 主張二：「`_fallbackItemExtent = 1.0` 破壞該幀滾動幾何、造成抖動」

**不成立。**

決定性實驗：把 `_fallbackItemExtent` 由 `1.0` 改為 `999999.0` 後重跑觸發案例，
`pixels`、`maxScrollExtent` 與 child 數量 **byte-identical**。原因是所有幾何輸入
（`scrollExtent`、`maxPaintExtent`、各 child 的 `layoutOffset`、
`firstIndex`/`targetLastIndex`）都由 `hybrid_block_sliver.dart:90-133` 的
Fenwick 覆寫算出，那些路徑不呼叫 `itemExtentBuilder`。這個值只會成為某個
下一幀就被回收的殘留 child 的 `BoxConstraints`，而該 sliver 的 geometry
當時已是零。

這些過渡幀上**確實**有可見位移，但成因不同：索引合法地變空，
`sliverScrollExtent` → 0，`ScrollPosition` 跟著 clamp。那是 I3 漸進重建的
設計行為，不是 fallback 的後果。atomic snapshot swap 對這個缺陷沒有幫助，
而且不能取代 fallback——fallback 擋的是崩潰。

**fallback 擋的崩潰是真的。** 還原修正前的程式碼可重現：

```
_TypeError: Null check operator used on a null value
  sliver_fixed_extent_list.dart:268  _getChildConstraints
  sliver_fixed_extent_list.dart:403  performLayout
```

本 repo 用 Fenwick 覆寫了框架所有容忍 null 的掃描，因此 `itemExtentBuilder`
僅存的呼叫者就是兩個強制解包點——這正是「回傳 null」在此不可行、在原生
Flutter 卻可行的原因。

可達性：`extent == null || !isFinite || <= 0` 那一支**結構上不可達**
（`_metrics` 與兩側清單在每個可觀察點一致，`BlockMetrics` 保證 `height > 0`
且兩個生產者都有 guard）。實際會走的只有 `key == null`，且僅在索引某一側
**變空**而其 sliver 仍掛載的 reset/invalidate 過渡幀。根因是
`document_index.dart:196` 的 `if (scrollOffset <= 0.0) return 0;` 在空側也
無條件回傳 `0`。

觸發頻率：`test/features/reader_v2` 全部 380 個測試（style change、rotation、
簡繁轉換、換源、state transition loops、跳章、drag/fling、restore loops）
**零觸發**；steady-state 滾動、部分收縮、漸進重填也都零觸發。只有刻意構造
「單側清空且 sliver 仍掛載」才會觸發一次。

**本次處理**：加上計數器（`debugSnapshot()['fallbackItemExtentHits']`），
把「真機頻率未知」變成可量測。沒有動 `document_index.dart:196`——那是
真正的源頭修法，但它會改變空側 offset 0 的回傳值，而
`document_index_fuzz_test.dart` 斷言此函式與框架
`_getChildIndexForScrollOffset` 逐點等價；在計數器顯示這條路徑真的會發生
之前改它，是沒有證據的投機修改。

未量測項目：真機頻率；是否存在「空側」以外能產生越界 index 的路徑
（構造不出來，380 測試也沒出現，但無法證明不存在）。
