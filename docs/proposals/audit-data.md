# 全面檢查：資料

把 `docs/agents/auto-audit.md`「舊程式」表上的資料 0–4 五段（資料庫與模型、下載與儲存、備份還原與本地書與更新、啟動與背景工作與 Android 那一半、同步）讀完，列出讀者會碰到的錯。只讀程式推理，沒有執行；每一筆都從觸發點走到出錯的那一行，並用 `gh issue list --state all --search` 查過以前沒報過。

- 讀的是 `origin/beta` 的 `fff55f9c`，下面的「檔案:行號」都是這個 SHA 的。
- 標準照 `docs/agents/auto-audit.md`「各方面看什麼」「算問題的」「不報的」；`PLAN.md` 第二階段已列的「背景工作互搶」不列。

## 進度

| 段 | 讀了哪些檔 | 找到 |
|---|---|---|
| 資料 0 資料庫與模型 | `lib/core/database/`（19 檔，不含 `*.g.dart`；另把 `app_tables.dart` 和初版 `5a4c55ee` 逐欄比過，後加的欄位都有升級步驟）、`lib/core/models/`（34 檔）、`lib/core/storage/` 的 `app_cache`、`app_storage_paths`、`reader_layout_cache`、`storage_metrics`（4 檔） | 0 |
| 資料 1 下載與儲存 | `lib/core/download/` 的 `book_update_service`、`download_base`、`download_executor`、`download_failure`、`download_scheduler`、`download_service`（6 檔，`audio_chapter_download` 在閱讀器 4）、`lib/features/downloads/download_manager_page.dart`（1 檔）、`lib/core/utils/cache_manager.dart`、`lib/core/storage/` 的 `book_storage_service`、`book_chapter_files`、`reader_chapter_content_store`、`reader_chapter_content_storage`、`book_illustration_storage`、`book_cover_storage_service`、`bookshelf_state_tracker`、`books_in_use`（8 檔） | 2 |
| 資料 2 備份還原、本地書與更新 | `lib/core/local_book/`（5 檔）、`lib/core/backup/` 的 `backup_service`、`restore_service`、`bookshelf_exchange_service`、`export_book_service`、`highlight_export`（5 檔，`login_data_backup` 在書源 4）、`lib/core/app_update/`（4 檔）、`lib/core/playback/tts_service.dart`（1 檔） | 2 |

## 問題

### 資料 0 資料庫與模型

沒有找到。

### 資料 1 下載與儲存

#### 1-1. 書源改了網址、或重複書源被合併之後，那些書已下載的漫畫與有聲書全變成「沒下載」，插圖也不見；舊檔案留在手機裡再也不會被刪

**會發生什麼**：讀者在書源編輯頁改了網址，或匯入書源、打開書源管理時夜讀自動合併了重複書源（ADR 0062），用那個書源的漫畫整本重新下載一遍、有聲書已下載的集數要重新手動下載、網路書正文裡的插圖重新抓；原本那份檔案留在舊的資料夾，移出書架、清除下載都刪不到，一直佔空間。另一台照同步的書源搬家紀錄跟著搬時也一樣。

**為什麼**：
1. 一本書的封面、插圖、漫畫的 CBZ 與有聲書的音訊都放在同一個書本資料夾，資料夾名稱由「書源網址＋書的網址」算出來：`lib/core/storage/book_cover_storage_service.dart:143-146`
   ```dart
   static String bookStorageKey(Book book) {
     final material = '${book.origin}\n${book.bookUrl}';
     return sha1.convert(utf8.encode(material)).toString();
   }
   ```
   章節檔照它找資料夾（`lib/core/storage/book_chapter_files.dart:32-37`），插圖也是（`lib/core/storage/book_illustration_storage.dart:60-65`）。
2. 改書源網址：`BookSourceService.saveEditedSource`（`lib/core/source/book_source_service.dart:247-275`）→ `BookSourceDao.saveEdited`（`lib/core/database/dao/book_source_dao.dart:103-120`）只改資料庫：書的書源網址（`BookDao.moveOrigin`，`lib/core/database/dao/book_dao.dart:70-74`）、搜尋結果、已存正文的鍵（`ReaderChapterContentDao.moveOrigin` 有重算鍵）。書本資料夾沒有搬。
3. 合併重複書源：`mergeDuplicateSources`（`lib/core/source/source_dedupe.dart:61-93`，書源管理 `lib/features/source_manager/source_manager_provider.dart:190`、`401` 讀清單時呼叫）→ `BookSourceService.mergeSources`（`book_source_service.dart:280-300`）→ `BookSourceDao.mergeInto`（`book_source_dao.dart:127-162`），同樣只搬資料庫。另一台同步時走 `SourceSync._saveEdited`（`lib/core/sync/source_sync.dart:41-42`）與同一個 `mergeSources`。
4. 書的書源網址換了，`bookStorageKey` 就指到一個新的空資料夾：
   - 漫畫：書架自動下載比對已下載的話（`lib/core/download/download_service.dart:85-93` → `downloadedComicChapterUrls`，`lib/core/download/download_executor.dart:379-392`）一話都對不到，整本排進下載；漫畫閱讀器也讀不到已下載的 CBZ。
   - 有聲書：`BookChapterFiles.downloaded` 讀新資料夾，已下載的集數都不見（`book_chapter_files.dart:50-61`）。
   - 插圖：`BookIllustrationStorage.dirFor` 指到新資料夾，已存正文裡的圖都找不到檔。
5. 舊資料夾從此沒人管：移出書架時 `_discardFiles` → `deleteBookAssets` 只刪新鍵的資料夾（`lib/core/storage/book_storage_service.dart:100-104`、`book_cover_storage_service.dart:134-141`）。

對照：本地書換檔名時有把整個書本資料夾複製過去、改指新路徑（`lib/core/local_book/local_book_service.dart:190-200`）；換源有 `handoffSourceSwitchAssets`（`book_cover_storage_service.dart:76-132`）。書源改網址與合併兩條路沒有。

**怎麼確認**：`test/core/database/` 或 `test/core/source/` 加一項：建一本漫畫書（書源 A），用 `BookChapterFiles.save` 存一話 CBZ；呼叫 `BookSourceService.mergeSources([A], B)`（或 `saveEditedSource` 改網址），重讀這本書，斷言 `BookChapterFiles.downloaded(book)` 仍有那一話、舊的 `bookAssetDir(bookStorageKey(舊書))` 不在了。

**修法方向**：修在書源網址換掉的地方：`BookSourceDao.moveOrigin` 這一層（`saveEdited` 與 `mergeInto` 共用）搬資料庫時，同時把每本書的書本資料夾從舊鍵搬到新鍵，並把 `coverLocalPath`、`customCoverLocalPath` 改指新路徑（同本地書的 `_repointAssets`）；新鍵已有資料夾時（合併時兩個書源有同一本書）以留下的為準、舊的刪掉。同一個原因：所有「書的 `origin` 被改掉」的地方都要一起搬，含同步套用書源搬家。

**輕重**：資料遺失或寫壞

#### 1-2. 在下載佇列刪掉一個剛開始、還在抓目錄的任務，重開 App 後它以「已暫停」又出現

**會發生什麼**：還沒有目錄的書（例如還原備份後）排進下載時，開跑先向書源抓目錄；讀者這時在「背景下載佇列」把它滑掉刪除，畫面上不見了，但下次開 App 這個任務以「已暫停」回到佇列。書架自動下載不會動被暫停的任務（`decideShelfDownload`），要讀者再刪一次。

**為什麼**：
1. 刪除只從記憶體與資料庫拿掉，不讓進行中的那一輪停下：`lib/core/download/download_service.dart:304-311`
   ```dart
   void removeTask(String bookUrl) {
     for (final task in tasks.where((t) => t.bookUrl == bookUrl)) {
       task.status = DownloadTask.statusPaused;
     }
     tasks.removeWhere((t) => t.bookUrl == bookUrl);
     downloadDao.deleteByUrl(bookUrl);
   ```
   沒有像 `retireBook`（同檔 `375-390`）那樣標退役、取消這一輪。
2. 那一輪還在 `planDownloadInSourceIsolate`（`lib/core/download/download_executor.dart:418-421`）裡抓目錄；回來後章數和排進來時不同（排進來時沒有目錄，總數是 0），整筆寫回資料庫：`download_executor.dart:428-431`
   ```dart
   if (plan.total != task.totalCount) {
     task.totalCount = plan.total;
     await downloadDao.upsert(task);
   }
   ```
   `upsert` 是 `insertOnConflictUpdate`（`lib/core/database/dao/download_dao.dart:36-37`），被刪掉的那一列又插回去，狀態是第 1 步設的「已暫停」。
3. 下一次開 App，`_loadTasks` 讀回資料庫所有任務（`download_service.dart:180-196`），它就回到佇列。

排隊期間目錄變長（書架檢查更新抓到新章節）也會讓第 2 步的條件成立，只是空檔較短。

**怎麼確認**：`test/core/download/` 加一項：準備一本沒有目錄的書與一個抓目錄會等一個 `Completer` 的假書源，`queueShelfDownload` 後等任務進入下載中，呼叫 `removeTask`，再讓目錄回來；等任務收尾後斷言 `DownloadDao.getAll()` 是空的。

**修法方向**：修在第 2 步：只改總數的地方用只更新那一欄的寫法（`DownloadDao.updateProgress` 加 `totalCount`，條件更新、列不在就不寫），不用整筆 `upsert`。另外 `removeTask` 改走退役（標退役、取消這一輪），已送出的章節也不再寫進度。

**輕重**：功能沒反應或結果錯

### 資料 2 備份還原、本地書與更新

#### 2-1. 重裝夜讀或換新手機還原備份後，書架上的書幾乎都畫成預設封面，要一本本點進書籍詳情才會換回真的封面

**會發生什麼**：網路書打開過書籍詳情就會把封面存一份在手機（書本資料夾），書記著那個檔的路徑。備份帶著這個路徑、卻不帶書本資料夾；在新裝的夜讀還原後，路徑指著不存在的檔，書卡封面讀不到檔就畫預設封面，不會改用網址。匯入別台匯出的書架檔也一樣。

**為什麼**：
1. 書詳情載入完就把封面存進書本資料夾、記下路徑：`lib/features/book_detail/book_detail_provider.dart:417` → `_storeDisplayCover`（同檔 `1155-1160`）→ `ensureBookCoverStored` 寫 `book.coverLocalPath`（`lib/core/storage/book_cover_storage_service.dart:22-33`），自訂封面寫 `customCoverLocalPath`（同檔 `52-66`）。
2. 備份的書照 `Book.toJson` 寫，兩個本機路徑都在裡面：`lib/core/backup/backup_service.dart:73-77` → `lib/core/models/book/book_serialization.dart:264-267`；書本資料夾不在備份裡（`lib/core/storage/book_chapter_files.dart:23-24` 的說明、`backup_service.dart` 沒有打包它）。
3. 還原照原樣寫回：`lib/core/backup/restore_service.dart:297-303`（`Book.fromJson` → `_bookDao.upsert`），路徑原封不動。
4. 顯示封面時本機路徑優先，網址排最後：`lib/core/models/book/book_extensions.dart:47-58`
   ```dart
   if (customCoverLocalPath != null && customCoverLocalPath!.isNotEmpty) {
     return 'local://$customCoverLocalPath';
   }
   if (customCoverUrl != null && customCoverUrl!.isNotEmpty) {
     return customCoverUrl;
   }
   if (coverLocalPath != null && coverLocalPath!.isNotEmpty) {
     return 'local://$coverLocalPath';
   }
   return coverUrl;
   ```
5. 書卡讀本機檔失敗就畫預設封面：`lib/shared/widgets/book/book_cover_widget.dart:436-451` 的 `errorBuilder` → `_buildFailedCover`（同檔 `521-532`）→ `_buildDefaultCover()`。只有再打開那本書的詳情（第 1 步）才會重新下載、改寫路徑。

同一個原因：書架匯出檔也用 `toJson` 帶著這兩個路徑（`lib/core/backup/bookshelf_exchange_service.dart:68`），在另一台匯入（`bookshelf_exchange_service.dart:180-192`）同樣畫成預設封面。

**怎麼確認**：`test/core/backup/restore_service_test.dart` 加一項：書架上一本網路書有 `coverUrl`，`coverLocalPath` 指著暫存資料夾裡的一個檔；建備份 ZIP，刪掉那個檔與書（模擬新裝），還原；斷言還原後這本書的 `getDisplayCover()` 不是指向不存在檔案的 `local://`（應該是 `coverUrl`）。

**修法方向**：修在最初出錯的地方：本機檔案路徑是這台手機的東西，不該跟著書出去。備份與書架匯出寫書時拿掉 `coverLocalPath`、`customCoverLocalPath`；還原與匯入時也把讀進來的這兩欄清掉（舊備份已經帶著），下次顯示就用網址、詳情頁再照常存一份。同步也送書架（資料 4 另看）。

**輕重**：畫面錯

#### 2-2. 匯入書架檔時，書架上已經有的同一本書，閱讀進度、分組、自訂封面被檔案裡的舊資料蓋掉，已下載好的章節還可能被換成「抓取失敗」

**會發生什麼**：讀者從書架「匯入」選一個書架檔，或用其他 App 打開一個書架檔（`association_dialog_helper`），檔裡有書架上已經有的書時，這台的那本書整筆換成檔裡的：讀到的位置跳回匯出當時、分組與自訂封面回到檔裡的樣子。檔裡那本書某章是抓失敗的紀錄，而這台已經下載好那章，這台的正文會被換成失敗紀錄。

**為什麼**：
1. 入口：`lib/features/bookshelf/bookshelf_page.dart:719-726`（`importFromFile`）與 `lib/features/association/handlers/association_dialog_helper.dart:106-109`（`importFromText`）。
2. 每本書不看這台有沒有，直接整筆寫入：`lib/core/backup/bookshelf_exchange_service.dart:180-192`
   ```dart
   for (final book in books) {
     final normalized =
         book.copyWith(
           isInBookshelf: true,
           ...
     await _bookDao.upsert(normalized);
   }
   ```
   `BookDao.upsert` 是整列 `insertOnConflictUpdate`（`lib/core/database/dao/book_dao.dart:76-77`），閱讀進度（`chapterIndex`、`charOffset`、`readerAnchorJson`、`progressTime`）、`group`、`customCoverUrl` 全部換成檔裡的。
3. 目錄照檔裡的寫回（`bookshelf_exchange_service.dart:197-199`，`insertAllOnConflictUpdate`）：同網址的章節序號換成匯出當時的，這台後來新增的章節留著，兩邊的序號混在一起。
4. 正文：匯出時不分狀態全部帶上（`bookshelf_exchange_service.dart:70-74`，`getEntriesByBookUrls` 沒有篩 `isReady`；對照備份 `backup_service.dart:112-119` 只帶好的）；匯入時直接蓋（`bookshelf_exchange_service.dart:200-205` → `ReaderChapterContentDao.upsertEntry`，`lib/core/database/dao/reader_chapter_content_dao.dart:77-89`，狀態照檔裡的「失敗」）。其他地方存失敗時都先看有沒有好的正文（`ReaderChapterContentStore.saveFailure`，`lib/core/storage/reader_chapter_content_store.dart:106-136`），這裡沒有。

**怎麼確認**：`test/core/backup/` 加一項：書架上一本書讀到第 5 章、第 3 章正文已下載；匯入一個書架檔，同一本書讀到第 1 章、第 3 章是失敗紀錄；斷言匯入後書的 `chapterIndex` 還是 5、第 3 章的 `hasReadyContent` 還是 true。

**修法方向**：匯入書架檔是「加入這些書」：書架上已有的書（同 `bookUrl`）不整筆覆寫，只補這台沒有的（或照同步的「新的贏」只換閱讀進度）；目錄只在這台沒有目錄時寫；正文只寫好的、而且只在這台沒有好的正文時寫（`fillContent`）。匯出端也只帶好的正文，和備份一致。

**輕重**：資料遺失或寫壞

## 拿不準

（還沒有）
