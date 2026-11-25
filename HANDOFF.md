# 交接：#650 審查第 2 輪修正（feat/reader-toc）

- 目標：照 #650 審查（GPT-6 Luna）修兩項，推上 #650、CI 過後傳回主對話 e44f785c-c0c8-4096-959c-e7f09cd508aa（第 1 項會再審，不要自己合併）。
- 第 2 項已做完、測試過：`SourceSwitchService.rebase` 遇到開關變了，照最新開關翻準備好的目錄再對章；`_migratedReverseToc` 讓 `_align` 也照 `migrateTo` 實際存的開關判斷。
- 第 1 項定案（advisor 同意）：書籤、標註加一欄可為 null 的 `tocReversed`（記下時目錄有沒有翻；null 當成和這本書現在一樣），翻轉目錄不再改章序，只把 null 的記成翻之前的方向（同一批只記一次）；用的時候方向不同才從另一頭數（本機目錄章數 −1−序號），再照章名找。進度同步的紀錄帶 `tocReversed`，`applyTo` 方向不同先翻序號。
- 已寫好、還沒實作的測試草稿在 `.wip/*.dart.txt`（推送前檢查不收編譯不過的測試，先另存）：接著做時覆蓋回 `test/core/storage/book_toc_reverser_test.dart`、`test/features/reader/reader_bookmarks_test.dart`，刪掉 `.wip/`；`chapterIndexIn` 要多 `reversed:` 參數。
- 下一步：①模型與資料表加 `tocReversed`、schema 22 遷移、跑 build_runner；②`chapterIndexByTitle` 加 `countedReversed`／`reversed`，改各呼叫處（reader_page、coordinator、bookmarks_page 的 tocs 要帶開關、匯出、DAO `moveToSource` 記新書的方向）；③新增書籤、標註時記下方向；④拿掉兩個 DAO 的 `reverseChapters`、改成記方向；⑤同步指紋在 `tocReversed` 不是 null 時納入，進度指紋只在 true 時納入；⑥sync_service_test 的 _Phone 加 BookmarkSync、HighlightSync，補兩台測試（目錄 ['番外','第一章','第二章','第三章','番外']：開關到之前與之後、日常進度先到）；⑦改 ADR 0085 第 12 行與後果（同名書源原生順序不同時是估的）；⑧推上、等 CI、傳回主對話；合併前刪 TODO.md 與本檔。
