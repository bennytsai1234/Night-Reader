# B2 末行補償 off-by-one — 近滿末行末字回捲修正

層級：T0/T1（單點數學修正，探針已實證，回歸測試已加）

## Before

`layout_pump.dart` 末行補償的安全上限以 `headroom ÷ 間隙數（字數−1）`
計算，但 letterSpacing 加在範圍內每個字元之後（字數份），總增量
= spacing × 字數，最多超出 headroom 一個 spacing。末行接近滿行時，
末字被擠到下一行成孤行（探針：9/9/9 三行段落變四行）。
觸發條件：「末行字距補償」開啟（預設關）＋末行近滿。

## After

分母改為末行字元數（`lastLineBoxes.length`），總增量必 ≤ headroom，
斷行不再改變。新增回歸測試（hybrid_pump_test：27 字 9/9/9、headroom
1px，斷言行數維持 3 且末行寬 ≤ 內容寬）。

驗證：`flutter analyze` 無問題；`flutter test` 734 全過。
隨 v0.2.137 發布。
