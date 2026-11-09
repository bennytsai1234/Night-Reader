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
11. **EPUB 只有圖的章照舊不列進目錄，圖併到下一章開頭**（章名之後、正文之前）；書最後面的圖頁併到最後一章結尾。章節清單不隨開關改變，否則章節序號一變，進度與書籤會對到錯的章。封面頁那張圖（已是書架封面）不放進正文。轉檔時一章超過 5 萬字再切（`TxtParser.maxChapterChars`）的字數不算圖的標記。
12. **不做行內字圖**：所有圖都當插圖、跟著開關走，書源寫了 `imageStyle: TEXT` 也一樣；段落中間的圖把段落切開，圖獨立一塊。查不到真的「一個字換成一張圖」的網站（Legado 說明文件也沒寫 `TEXT` 的用途），等看到實例再照 Legado 加。
13. **整章都是圖的書源在書源那層排除**（例如飛盧 VIP 章由伺服器把正文畫成圖）：使用者說刻意擋的不處理。書源校驗抓一章看「讀得到字」（`source_check_isolate.dart` 的 `_looksReadable`）時要先拿掉圖的標記，只有圖的章照舊判成正文壞掉。
14. **點圖和點字一樣**照點擊區域翻頁或叫選單；**長按圖打開全螢幕大圖**，可縮放，往下拖或按返回關掉。不做 Legado 的「點擊預覽圖片」設定（ADR 0030 第 3 條）。
15. **其他閱讀行為**：朗讀跳過圖；選字選不到圖，跨過圖的標註只畫前後的字；書籤落在字上；本章進度照字算（`hybrid_progress.dart`），捲過圖時進度不動。停在圖中間離開，再打開回到這張圖的頂端（位置的像素偏移只記 ±120，`ReaderV2Location.maxVisualOffsetPx`）；其他情況照舊回到原處。
16. **圖片大小照原尺寸，太大才縮**（Legado 的 DEFAULT）：原尺寸是圖檔像素 ÷ 手機的像素密度；比正文欄寬就縮到欄寬，比一屏（正文區高度）高就等比縮到一屏內；置中，不放大小圖。上下各留半行（示範頁用的值），不加圓角與陰影。使用者從三組候選（另兩組：一律撐滿欄寬、撐滿欄寬不限高）裡選的；開工時寫進 `docs/design/reader.md`。
17. 書源的 `imageDecode`（圖片解密）與抓圖要帶的請求標頭照 Legado，不另外問。
18. **深色不調暗圖**，照原色：嫌亮用閱讀器本來的亮度條（使用者說的）。
19. **骨架照現有規格**，不另畫候選：圖在紙上的骨架是和圖同大小的方塊（`docs/design/loading.md`「封面、按鈕是方塊」、`reader.md`「照一頁真正的每一行畫」），和字的長條一起長出、呼吸，換場時由左而右換成圖；「照上次那一頁長出骨架」記住的那一頁也要記得圖的方塊。掀紙前圖要解碼好、畫得出來（同第 10 項），換場時不先出現空框。

## 進度（2026-11-09 下班時）

分支 `feat/text-illustrations`，都已推上，工作目錄乾淨。ADR 0050、`docs/design/reader.md` 的插圖規格、`GLOSSARY.md` 的「插圖」只在本分支上（不在 `beta`）；`feat/audiobook-player` 也用了 0050 這個號碼，合併時再改號。

## 跨分支調整（2026-11-09 開工前檢查，和上面不一致時以這裡為準）

- 本分支屬第一批（和 PR #319、`fix/tts-now-playing` 一起），可以單獨合併。第二批 `feat/source-kinds`、`feat/images-comics`、`feat/audiobook-player`、`feat/source-ai-repair` 一起合。
- 合併衝突（兩份 ADR 0050、資料庫 schema 號、幾條分支改同一段程式）留到合併時一次處理。
- **備份**：插圖、漫畫圖、有聲書音訊、本地書原檔都不進備份。還原後插圖與漫畫照書架自動下載重抓（本分支已做：還原留 `.unfetched` 記號、下載排程補抓、確定抓不到記 `.missing`，規則在 ADR 0050）。
- **同步**：插圖不同步；另一台的書架自動下載抓正文時一起抓圖（`bookshelf_sync.dart` 加書時呼叫 `keepShelfBookDownloaded`）。
- **抓圖介面給漫畫分支沿用**：`IllustrationFetcher.fetch(source, book, content, dir, {retryMissing, cancelToken})` 在書源 isolate 裡把 `content` 中 `<img src>` 還沒存的圖抓進 `dir`（檔名 `BookIllustrationStorage.pathFor`），回傳連不上、還要再試的張數；主 isolate 經 `BookSourceService.fetchIllustrations` 呼叫。
- **合併注意**：`feat/source-kinds` 為了校驗在 `ContentParser` 加了 `keepImages`；本分支讓正文一律留圖。兩條後合併的那條要拿掉 `keepImages` 選項。

已提交：
1. `df0639a9` 閱讀器認得插圖：標記換成記號、插圖各自一塊、照原尺寸畫、長按看大圖、骨架畫方塊、「閱讀偏好 → 顯示插圖」開關（預設關）。
2. EPUB：轉文字時留標記、圖抽到 `book_assets/<書>/images/`、只有圖的章併到下一章開頭、封面不進正文；旁邊寫 `epub-chapters.json`（章節範圍＋轉法版本），閱讀器開本地書時版本不對就重轉、換章節範圍、清存著的正文。
3. 網路書：正文改用 `HtmlFormatter.formatKeepImg`；抓到的正文有圖就在書源 isolate 抓圖（標頭、Cookie、限流、`imageDecode` 同 Legado），抓完或確定抓不到才算這章好；換源驗證那章、匯出補抓的章也抓。書源校驗、換源判斷、匯出拿掉標記。順手修「清除封面快取」只刪抓來的封面；網路書插圖算正文快取。
4. `imageDecode` 測試（桌面 QuickJS 真的跑）。

標記與讀圖檔寬高在 `lib/core/utils/illustration_markers.dart`，插圖資料夾規則在 `lib/core/services/book_illustration_storage.dart`，抓圖在 `lib/core/engine/web_book/illustration_fetcher.dart`。

本機跑過：`test/core/local_book`、`test/features/reader_v2/chapter`、`test/core/services`、`test/core/engine/web_book`、`test/core/engine/url_rule_base_url_test.dart`、`test/features/book_detail`，全過。

## 下一步

1. **幀預算要重量**：跑過一次 `tool/frame_budget_compare.sh ec9fac86 test/frame_budget/reader_jump_frame_budget_test.dart test/frame_budget/reader_interactions_frame_budget_test.dart`，當時電腦上還有別的 flutter_tester 在跑，數字兩個方向都有大跳動（目錄內甩動 60→12、跳到第 10 章 9→21），不可信。用 `FRAME_REPEAT=3` 重量；「跳到第 10 章」若真的變多，查是不是 `layout_pipeline.dart` 的插圖分支或 `page_lines.dart` 的 `blockLines` 造成（沒有插圖的章不該多做事）。表寫進 commit message。
2. **畫一張有插圖的閱讀畫面**確認整條路徑畫得出來：`test/support/app_harness.dart` 的 `seedLibrary` 把某章正文換成含 `<img src="…">`，對應圖檔放進那本書的 `images/`，開「顯示插圖」，用 `test/support/screenshot.dart` 拍淺色、深色各一張放進對話。還沒有端到端（真的排版到畫出）的測試。
3. ~~`PRIVACY.md` 與 App 的「隱私說明」~~ 已補：網路請求含正文裡的插圖、正文快取含插圖、備份不含插圖與本地書原檔。
4. ~~`README.md`~~ 只有圖卡，沒有「插圖略過」，不用改。
5. 收尾照 `docs/agents/finish.md`：派 Codex 審查、併最新 `beta`、開 PR、CI 通過就停在「可以合併」；收尾時刪掉這份 `HANDOFF.md`、`PLAN.md` 那條打勾。

已知、接受的邊界：章末的圖上面停下來，重開時不會對齊到圖頂。

## 畫候選的做法

拋棄式臨時測試放在 `test/_screens/`（git 忽略），不是真的閱讀器排版：用預設字號 18、行高 1.2、兩側留白 12，淺色牛皮紙（`AppStyle.kraft`，預設淺色風格）、深色素色純黑（預設深色風格），中文字型 `fontFamily: kReaderV2FontFamilyFallback.first`；圖用 `CustomPaint` 畫示意（彩頁 1200×1600、長條人物表 700×2400、地圖 1600×900、小插圖 360×270、分隔花紋 300×60 像素）。一條連續捲動的長卷畫成一張 PNG（先量內容高度再設畫面高），做成三支手機並排、各自捲動、可切淺深色的頁面用 `html_render` 放進對話。

## 查到的現況

- 網路書：`lib/core/engine/web_book/content_parser.dart:52` 用 `HtmlFormatter.format` 把 `<img>` 刪掉後存進資料庫的章節正文表 `ReaderChapterContents`（一章一列純文字）。閱讀、書架自動下載、手動下載、換源都走 `lib/core/services/chapter_content_preparation_pipeline.dart`。書源規則的 `imageStyle`、`imageDecode` 已讀進 `ContentRule`，沒用到。
- EPUB：原檔複製到 `InkpageBooks/` 保留（移出書架才刪，ADR 0032「考慮過的做法」否決了不留原檔）；匯入時轉成 `book_assets/<書>/epub-text.txt`，章節記位元組範圍；`lib/core/local_book/epub_parser.dart` 的 `_skippedTags` 略過 `img`。轉好的文字檔不見時 `LocalBookService.getContent` 會從原檔重轉（`lib/core/services/local_book_service.dart:510`）。
- 合流：`lib/features/reader_v2/chapter/reader_v2_content_transformer.dart` 在背景 worker 跑替換規則、重新分段、繁簡、引號整理（`_convertCurlyQuotesLine`）→ 按換行切段 → `hybrid/text/text_preprocessor.dart` 切成文字塊 → 背景量高度排版 → 連續捲動。位置是 `ReaderV2Location`：章、`charOffset`，加 `contentHash` 與前後文字 `anchorBefore`／`anchorAfter`，正文變了可以對回去。
- 書籍詳情的「清除封面快取」（`book_detail_provider.dart` 的 `clearBookCache`，`_coverStorage.deleteBookAssets`）刪掉整個書本資料夾；圖放進去之後要改成只刪封面。
- Legado 對照（`D:\Migrated\Desktop\Folder\product\legado`）：`ui/book/read/page/provider/TextChapterLayout.kt` 的 `setTypeImage`；`help/book/BookHelp.kt` 的 `saveImages`（下載時存圖）；`model/ReadBook.kt` 的 `upWebBook`（書源的 `imageStyle` 套到書）。
