# 交接：書源分類與保留

2026-11-09。分支 `feat/source-kinds`。決定與理由在 ADR 0051（書源分類）與 ADR 0053（同名不同類是不同的書），AI 復判的計畫在 `beta` 的 `PLAN.md`。本分支屬第二批合併（和 `feat/images-comics`、`feat/audiobook-player`、`feat/source-ai-repair` 一起），收尾到「可以合併」就停。

## 剩下的

- 程式都做完、已推上。問使用者要不要收尾（`docs/agents/finish.md`），收尾時刪掉本檔。

## 給其他分支的介面（漫畫、有聲書分支併 `origin/feat/source-kinds` 後用）

- **書源是哪一類**：`source.sourceKind`（`BookSourceKind.novel／comic／audio／unsupported`），不看類型數字或名稱。
- **書是哪一類**：`book.bookKind`（`SearchBook` 也有）。`isAudio`／`isImage`／`isText` 已拿掉；有聲書分支的 `isAudio`（`book_open_route`、下載跳過有聲書等）改成 `book.bookKind == BookSourceKind.audio`，合併時以這裡為準。寫類別用 `kind.bookType`（小說 0、有聲 1、漫畫 2）。`BookType.audio`（0x20）兩邊都加了，同一行。
- **認書的鍵**：同步用 `ProgressSync.nameKeyOf(book)`（漫畫 `comic:書名\t作者`、有聲 `audio:…`，小說照舊）；閱讀統計、書籤、標註記 `book.recordName`（漫畫、有聲帶前綴），拆回來用 `BookSourceKind.splitRecordName`，找書用 `BookDao.getByRecordName`。漫畫閱讀器記閱讀時間時 `bookName` 傳 `book.recordName`。
- **換源**：`source.isSearchableFor(book.bookKind)`。漫畫、有聲搜尋放行時改 `isSearchEnabledByRuntime`（文字搜尋）或另寫一支，換源不用動。
- **書跟著書源類型**：`BookSourceDao.upsert／upsertAll` 存完會呼叫 `BookDao.followSourceKinds`，不用另外處理。
- **畫面**：搜尋卡的類別記號是 `BookKindMark`（`lib/shared/widgets/book_kind_mark.dart`）；書架書卡不加，漫畫分支的 `DefaultBookCover(kind:)` 在書架與書籍詳情傳 `book.bookKind`。
- 本分支的書架遇到漫畫、有聲書先跳「漫畫與有聲書還不能打開。」（`bookshelf_page.dart` 的 `_openBook`），漫畫與有聲書分支接手開書時拿掉。

## 合併時注意

- 本分支把 schema 升到 15；漫畫或有聲書分支若也升版會撞號，照先進 `beta` 的往後接。ADR 0050 有兩份、多條分支改同一段程式，合併時一次處理。
- 校驗加的 `keepImages`（`ContentParser`）和 `feat/text-illustrations`（正文一律留圖）碰同一段；兩條都進 `beta` 後這個選項多餘，由後合併的那條拿掉。

## 使用者可以改的預設

- 「刪除非小說源」預設只勾影視、文件源，漫畫、有聲不勾。
- 不支援那一類的名稱是「影視、文件源」（原本的長名稱在刪除框擠成兩行）。
- 新勾選沒有副標（介面不放解釋文字）。
