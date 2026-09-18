# 2026-08-26 完成摘要

## Reader continuous paragraph layout

- 修正 Hybrid Reader 將效能 `ChapterBlock` 誤當成獨立視覺段落的問題：同一來源段落的切塊現在共用一次連續 `ui.Paragraph` 排版，再映射回各 block 的度量、快取與視口座標。
- 保留真正的標題／來源段落邊界，並同步處理 Paragraph cache 參照計數、block local Y window、章節失效後的 `DocumentIndex`／admission 清理，以及同一視覺行多切點的極小高度切片。
- 驗收：`flutter analyze`、`flutter test test/features/reader_v2/hybrid`（85）、`flutter test test/features/reader_v2`（182）與全專案 `flutter test`（983）均通過。
- 完成文件：[dispatch plan](2026-08-25-reader-continuous-paragraph-layout-dispatch-plan.md)、[package](2026-08-25-reader-continuous-paragraph-layout.md)。
