# 交接：文字書的插圖

網路書正文裡的 `<img>` 與 EPUB 插圖夾在文字中間顯示。目前還在和使用者談範圍，**還沒寫程式**。漫畫（另一個專給圖片的閱讀器）在 `feat/images-comics` 談，這裡不碰。

接手時照「還沒談的」順序，一次問使用者一個問題（照全域指示「列選項給使用者選」），談定一項就更新本檔的「已談定」。全部談定後再開工，開工前先改 ADR 0032 與 `DESIGN.md`／`docs/design/reader.md` 對應的地方。

## 已談定（使用者 2026-11-09）

1. **網路書與 EPUB 一起做**，一條分支（本分支）、一個 PR；commit 分層：閱讀器的圖片塊（先用測試裡的假圖驗證）→ EPUB 帶插圖 → 網路書抓圖與下載，每層驗證過才推。
2. **開關**：「閱讀偏好」裡一個全域開關「顯示插圖」，預設關，放在繁簡轉換附近；所有書一起開關，不做每本書各自的。它是內容開關（同繁簡轉換），照 ADR 0030 分級放完整設定頁，不違反設計原則第 6 條。圖片的外觀（寬度、置中、比一屏高時怎麼縮、上下間距）不做成設定，畫候選給使用者挑，Legado 的四種 `imageStyle` 不做成選項。
3. **開關只管顯示，不管存**：開或關，存的正文都留圖的位置、下載都抓圖、EPUB 都抽出插圖。
4. **圖的位置寫成 `<img src="完整網址">` 標記**（同 Legado）：網路書存正文時改用 `HtmlFormatter.formatKeepImg`；EPUB 轉出的文字在插圖處寫同樣的標記，網址指向這本書資料夾裡的圖檔。轉換（替換規則、繁簡、引號整理）要跳過標記，否則 `src="…"` 的引號會被換成彎引號、網址被繁簡改掉。開關關著時合流處把標記拿掉，畫面和現在一樣；匯出 TXT 也拿掉。
5. **圖不算字**：捲動位置、書籤、標註照字的位置記，圖不佔字數，開關切換與舊的書籤標註不錯位。
6. **圖檔存在這本書的資料夾** `book_assets/<書>/images/`，當正文的一部分：網路書下載章節時一起抓（含書架自動下載），EPUB 轉文字時抽出來；離線看得到，移出書架一起刪，不同步（同已下載的正文）。
7. **開關關著時下載也抓圖**：之後打開，已下載的書馬上有圖；代價是空間與請求變多（圖片請求和章節一樣經過書源限流）。
8. **舊資料**：
   - EPUB：App 更新後在背景從保留的原檔重轉一次帶進插圖，讀者不用重新匯入；章節範圍重算，書籤、標註、進度靠位置加前後文字對回去。
   - 網路書：已存的章不動（存的時候圖已刪掉，看不出原本有沒有圖），之後新抓的才有圖（新章節、還沒下載的章、「重新取得本章」、換源）。整本補圖靠書籍詳情清除正文、讓書架自動下載重抓（ADR 0008：正文只在使用者明確動作中換掉）。
9. **開關關著時圖完全不顯示**：畫面、捲動位置、目錄和這一版之前一樣（設計原則第 4 條）；不留「〔插圖〕」標記，也不做單張打開。
10. **一章的圖都抓到或確定抓不到，這章才算準備好**：期間紙蓋著、骨架呼吸，好了才換場，版面一次到位；寬高在背景從圖檔開頭讀。抓不到的圖當作不存在、不留空位，「重新取得本章」再試。不做「文字先出、圖後補」，也不做「載入失敗」框。

## 還沒談的（照這個順序，資料流先談完再談外觀）

1. 圖片的大小、置中，比一屏還高的圖怎麼辦（正文是連續捲動，沒有分頁，ADR 0006），和上下文字的間距：畫候選圖（淺色、深色各一組）給使用者挑。
2. 段落中間的圖（網路書的字圖，Legado 的 `TEXT` 樣式：網站用圖片代替文字防爬）要不要當成一個字排在行內。
3. 骨架怎麼畫圖（骨架照真實內容的位置與大小，ADR 0016／0024）、骨架換場時圖怎麼出現。
4. 朗讀跳過圖；選字、書籤、標註碰到圖的行為；跳章與進度計算。
5. EPUB 只有圖的頁（封面頁、插圖頁）現在整章不列進目錄（ADR 0032），帶插圖後要不要列。
6. 書源的 `imageDecode`（圖片解密）與抓圖要帶的請求標頭照 Legado。

## 查到的現況

- 網路書：`lib/core/engine/web_book/content_parser.dart:52` 用 `HtmlFormatter.format` 把 `<img>` 刪掉後存進資料庫的章節正文表 `ReaderChapterContents`（一章一列純文字）。閱讀、書架自動下載、手動下載、換源都走 `lib/core/services/chapter_content_preparation_pipeline.dart`。書源規則的 `imageStyle`、`imageDecode` 已讀進 `ContentRule`，沒用到。
- EPUB：原檔複製到 `InkpageBooks/` 保留（移出書架才刪，ADR 0032「考慮過的做法」否決了不留原檔）；匯入時轉成 `book_assets/<書>/epub-text.txt`，章節記位元組範圍；`lib/core/local_book/epub_parser.dart` 的 `_skippedTags` 略過 `img`。轉好的文字檔不見時 `LocalBookService.getContent` 會從原檔重轉（`lib/core/services/local_book_service.dart:510`）。
- 合流：`lib/features/reader_v2/chapter/reader_v2_content_transformer.dart` 在背景 worker 跑替換規則、重新分段、繁簡、引號整理（`_convertCurlyQuotesLine`）→ 按換行切段 → `hybrid/text/text_preprocessor.dart` 切成文字塊 → 背景量高度排版 → 連續捲動。位置是 `ReaderV2Location`：章、`charOffset`，加 `contentHash` 與前後文字 `anchorBefore`／`anchorAfter`，正文變了可以對回去。
- 書籍詳情的「清除封面快取」（`book_detail_provider.dart` 的 `clearBookCache`，`_coverStorage.deleteBookAssets`）刪掉整個書本資料夾；圖放進去之後要改成只刪封面。
- Legado 對照（`D:\Migrated\Desktop\Folder\product\legado`）：`ui/book/read/page/provider/TextChapterLayout.kt` 的 `setTypeImage`；`help/book/BookHelp.kt` 的 `saveImages`（下載時存圖）；`model/ReadBook.kt` 的 `upWebBook`（書源的 `imageStyle` 套到書）。

## 要改的文件

- ADR 0032：推翻「插圖略過」，寫新 ADR 或在 0032 加註（照 `domain-modeling`）。
- `GLOSSARY.md` 開頭「（只讀文字，插圖略過）」與需要的新詞（例如「插圖」「顯示插圖」），談定後提議。
- `PRIVACY.md` 若下載圖片涉及新的網路請求說明，和 App 的「隱私說明」一起改。
