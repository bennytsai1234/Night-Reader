# Justify 縮排被折疊導致字距不一 — placeholder 縮排修正

層級：T1（單檔邏輯修正 + 快取版本升級；診斷明確、可逆）

## Before（現況與根因）

使用者截圖（2026-07-13）：多行段落整行字距被大幅撐開且失去段首縮排，
單行段落縮排與字距正常，兩者並排造成「間隔不一樣」的不適感。

已用排版探針（`docs/scratchpad/2026-07-13-justify-indent-probe/`）證實根因：

- `layout_pump.dart` 以 `'　' * indentChars`（U+3000）作段首縮排前綴，
  且正文一律 `TextAlign.justify`（`hybrid_reader_screen.dart:785`）。
- SkParagraph 的 justify 會把行首 U+3000 視為可分配空白：縮排被壓成
  0 寬，其寬度（2 字 ≈ 2em）連同殘餘空隙全數平攤進該行所有字距
  （探針實測每字 20px → 23.4px，+17%）。
- 只有 soft-wrap 行參與 justify；單行段落（hardBreak）不受影響，
  因此縮排、字距皆正常 → 與被撐開的段落並排即為截圖症狀。

## After（改法與驗證）

改法（方案 B，探針已驗證）：

1. `layout_pump.dart`：縮排前綴從 U+3000 文字改為等量的
   `addPlaceholder(width: fontSize, height: fontSize, bottom)`。
   - placeholder 非空白字元，justify 不折疊；縮排保持原位原寬。
   - 每個 placeholder 佔 1 code unit（U+FFFC），與 U+3000 相同，
     所有 charOffset / TTS / 錨點換算完全不變。
   - 探針實測：斷行位置與 start 相同、行高不變、justify 只分配
     真正殘餘空隙（+0.6px/字，不可察覺）、單行段落不受影響。
2. `metrics_disk_cache.dart`：`_version` 2 → 3。extent 理論上不變
   （U+3000 advance = 1em = placeholder 寬），升版是保險，避免特殊
   字型下 advance 差異造成 metrics 快取與實排不符。
3. `hybrid_types.dart` 註解同步（縮排前綴改為 placeholder）。

放棄的替代方案：A（關掉 justify）——一行改動即可消除症狀，但放棄
兩端對齊、避頭點行右緣參差，且不修縮排消失的問題。

驗證：`flutter analyze`、`flutter test`（含既有 reader 測試）、
探針測試保留於 docs/scratchpad 供回查。
