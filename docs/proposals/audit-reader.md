# 全面檢查：閱讀器

這份是收穩期間全面檢查的閱讀器那一塊：照 `docs/agents/auto-audit.md` 的標準，把閱讀器 0～4 段（正文層、閱讀器的功能與書籤朗讀、畫面與視窗、章節與排版、漫畫與有聲書）的程式讀一遍，列出讀者會碰到的錯。只讀、只列，沒有修。

- 讀的是 `origin/beta` 的 `fff55f9c3ad30947f9b3d76012fb84989d98c095`；下面的「檔案:行號」都是這個提交的。
- 每一筆都從觸發點走到出錯的那一行，查過以前的 issue（含 `auto-audit`）沒報過；走不完的放最後「拿不準」。

## 進度

| 段 | 讀了哪些 | 找到幾筆 |
|---|---|---|
| 閱讀器 0：正文層 | `lib/features/reader/text_view/` 全部 41 個檔（`anchor/`、`core/`、`geometry/`、`illustration/`、`layout/`、`measure/`、`overlay/`、`paragraph/`、`pipeline/`、`progress/`、`pump/`、`text/`、`view/` 與 `reader_text_view.dart`） | 1 |

## 閱讀器 0：正文層

### 0-1. 開著「顯示插圖」時改了上下邊距或打開頁尾，很高的插圖不再縮進一屏，要重新開書才對

**會發生什麼**：插圖比正文區高時，照規格要等比縮到正文區高、一屏看得到整張。讀者在閱讀中把上下邊距調大、或打開頁尾，正文區變矮，但已經排好的插圖照舊用原本的高度，整張超出一屏；換章再回來也一樣，要改到字級這類會重新排版的設定、或關掉重開這本書才縮回去。

**為什麼**：

- 插圖塊的高度照排版當下的正文區高算：`lib/features/reader/text_view/pipeline/layout_pipeline.dart:749-756`

  ```dart
  final box = IllustrationBox.layout(
    illustration,
    contentWidth: spec.textLayoutFrame.width,
    maxHeight: spec.contentHeight,
  ```

  `IllustrationBox.layout` 比正文區高就縮到 `maxHeight`（`lib/features/reader/text_view/illustration/illustration_images.dart:33-36`）。
- 正文區高不在排版簽章裡，改了不換排版世代：`ReaderLayoutSpec` 把高度與上下邊距放在 `viewportSignature`，`layoutSignature` 只看寬度與字的樣式（`lib/features/reader/layout/reader_layout_spec.dart:246-252`、`:351-363`）。`ReaderRuntime.applyPresentation` 兩者只差在高度時只呼叫 `updateViewportSpec`、不加 `layoutGeneration`（`lib/features/reader/session/reader_runtime.dart:302-312`）。
- 同一個世代裡量好的塊不再重量：`requestWindow` 看到量測與段落都在就直接放行（`layout_pipeline.dart:314-333`），插圖塊的量測鍵 `StyleFingerprint` 也刻意不含正文區高（`lib/features/reader/text_view/core/text_view_types.dart:140-143`）。所以舊的塊高留到這份排版管線丟掉為止。
- 磁碟快取已經為了同一個原因跳過有插圖的章（`lib/features/reader/text_view/pipeline/layout_disk_cache.dart:117-123`），記憶體裡的量測沒有。

**怎麼確認**：在 `test/features/reader/text_view/` 加一個元件測試：一章正文中間夾一張比正文區高的插圖（假圖檔照 `test/features/reader/reader_illustration_open_test.dart` 的做法），開書排好後把 `ReaderLayoutStyle.paddingTop` 調大（`layoutSignature` 不變、`contentHeight` 變小），等畫面靜止，斷言插圖那一塊的高度等於新的正文區高加上下間距，而不是舊的。

**修法方向**：插圖塊的高度跟著正文區高走。做法擇一：正文區高變了時把畫面附近有插圖的章當成失效重排（`handleChapterEvent` 的 `invalidated` 那一條），或把插圖會用到的正文區高與像素密度放進插圖塊的量測身分，變了就重量。像素密度（`_devicePixelRatio`，`layout_pipeline.dart:781-784`）是同一個原因，一起處理。

**輕重**：畫面錯。

## 拿不準

（還沒有）
