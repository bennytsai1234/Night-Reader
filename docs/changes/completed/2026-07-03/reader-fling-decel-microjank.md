# Reader V2：滾動放開後減速微頓挫（fling 減速期主執行緒爆量）

層級：T2（效能迴歸區、async/stateful、跨 render/layout/chapter 三個子層）

## Before（診斷）

高速拖曳順暢、放開後減速有微頓挫。前次修復（tile 重繪、notify 節流、半幀排版切片）
解決重繪風暴後，殘餘成因有二：

1. **排版切片讓出策略不感知幀**：`ReaderV2LayoutEngine.layoutStep` 的讓出用
   `Future.delayed(Duration.zero)`，只讓出 event loop、不等 vsync。同一幀間隔內
   可連跑多片 4.2ms 切片，120Hz 幀預算（8.3ms）必然超支。fling 放開瞬間
   `updateWindowBoostForFling` 擴張前方視窗（最多 +4000px），這筆排版債正好全
   落在減速期間、以不受幀節律約束的方式償還。拖曳期間沒有 boost、且劃動間有
   空檔可追趕，所以拖曳無感——與使用者觀察相符。
2. **內容預載的主執行緒成本落在減速期**：`startFling` 觸發最多 3 章方向性內容
   預載。每章 `compute` 現場 spawn 一個新 isolate；且簡繁轉換
   （`ChineseTextConverter.convert`）因字典只存在主 isolate 靜態區，被留在主執
   行緒對整章正文執行（開啟轉換時每章可達數 ms～數十 ms），全部撞進減速段。

## After（修法與驗證）

**A. 排版切片幀感知讓出**（`reader_v2_layout_engine.dart`）
- 有排程幀（動畫中）→ `await SchedulerBinding.endOfFrame`：每幀最多一片、排在
  幀完成之後；加 32ms 保底 timer 防測試環境「幀已排程但永不 pump」卡死。
- 無排程幀（閒置背景排版）或無 binding（純 Dart 測試）→ 維持零延遲讓出，
  背景追趕速度不變。

**B. 內容轉換管線改常駐 worker isolate**（`reader_v2_content_transformer.dart`、
`chinese_utils.dart`）
- 新增常駐 worker isolate：首次使用時 spawn 一次，之後所有章節轉換（替換規則
  + 重分段 + 簡繁轉換）都送進同一 worker，免去每章 spawn。
- `ChineseUtils` 新增 `initializeFromDictionaryData`：worker 啟動時由主 isolate
  把 4 份 OpenCC 原始字典內容（rootBundle 已快取，重取免 IO）送進 worker 初始
  化一次，簡繁轉換自此完全離開主執行緒。
- worker 不可用（spawn 失敗、測試環境）→ 無縫退回既有 compute + 主執行緒轉換
  路徑，行為不變。

刻意不做：boost 擴張延後到 settle（會重新引入撞人工邊界牆的停頓；A 已把爆量
排版改為每幀一片的細水長流，達成同一目的且不犧牲跑道長度）、
`_pumpContent` 加 interactive 門（內容預載是為了減速中跨章時內容已就緒，延後
反而增加撞牆機率；其主執行緒成本已由 B 移除）。

驗證：`flutter analyze`、`flutter test`（含新增 worker 路徑/退回路徑/轉換測
試）；絲滑度需真機驗證（本機無 Android SDK）。
