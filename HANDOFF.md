# 交接：中英混排的英文單字之間空格消失

使用者在《漫威裡的賽亞人》第三章〈雷耶斯集團〉看到英文單字之間的空格不見了，例如 `Lifeitseems`、`willfadeaway`、`Driftingfurthereveryday`、`FadeToBlack`。另一個公開網站的同一章有空格（`Life it seems`、`Fade To Black`），但那個網站擋自動抓取（403），沒對照到。

同一張截圖裡的另一個問題（中文字距被拉開）已經修好，見 PR #319（`fix/reader-kinsoku-latin-spread`），和這件無關。

## 已經查過、排除的

讀程式確認以下幾步都**不會**刪掉兩個英文字母之間的半形空格：

- `HtmlFormatter.format()`（`lib/core/utils/html_formatter.dart`）：`&nbsp;`、`&ensp;`、`&emsp;`、U+00A0 都轉成半形空格。
- `normalizeTypography()`（`lib/features/reader_v2/chapter/reader_v2_content_transformer.dart`）：tab、U+00A0、U+3000 轉成半形空格，連續空格合成一個；`_removeCjkSpaces` 只刪一側是漢字或全形標點的空格。
- 換行與繪製（`VisualLineLayoutEngine`、`ReaderParagraphLayout`）：用截圖工具畫過 `Fade To Black`，空格都在。

## 還沒查的（照順序）

1. 問使用者用的是哪個書源。書源原文的取法見 `docs/agents/phone.md`「書源原文」。
2. 用 `test/live/` 連真網站抓那一章，看書源解析出的正文有沒有空格。
   - 沒有空格：問題在網站或書源規則（例如規則裡的 `##\s` 替換），不在夜讀。
   - 有空格：接著查使用者的替換規則（`_applyRules` 會套用），再查不到就在 `ReaderV2ContentTransformer` 每一步印出這段文字，找出哪一步刪掉的。
3. 查完刪掉本檔。
