# 2026-06-26 Reader V2 review breakages

## Before

從 0.2.105 起的 Reader V2 變更留下三個會破壞既有流程的問題：

- Slide 手動拖曳翻頁完成後沒有完成 idle completer，後續排隊翻頁、TTS 跳頁或自動翻頁可能卡住。
- Slide viewport 改成單一 `CustomPaint` 後，原本的 `ReaderV2TileLayer` 與邊界 `Text` 不再存在於 widget tree，既有測試與語意契約會斷裂。
- 同一檔案留下未使用 import / method，release workflow 的 analyze 會失敗。

## After

- 手動拖曳翻頁完成時同步更新 idle completer。
- Slide viewport 恢復原本的三頁 widget 佈局與邊界文字，同時保留現有拖曳/預載/進度修正。
- 移除未使用的 painter-only 程式碼。
- 新增手動滑動後接 controller 翻頁的回歸測試。

## Verification

- `git diff --check` 通過。
- 本機找不到 `flutter` / `dart`，未能執行 Flutter analyze/test。
