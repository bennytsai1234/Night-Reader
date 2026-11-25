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
| 資料 3 啟動、背景工作與 Android | `lib/main.dart`、`lib/app_providers.dart`、`lib/core/` 的 `startup/`（1）、`di/`（1）、`config/`（1）、`constant/`（5）、`exception/`（2）、`fonts/`（2）、`base/`（1）、`background_work/`（4）、`diagnostics/`（4）、`platform/`（2）、`app_lock/`（1）；`android/app/src/main/` 的 Kotlin（7 檔）與 `AndroidManifest.xml`；`lib/core/utils/` 的 `encoder_utils`、`lru_map`；`lib/core/storage/resource_service.dart` | 0 |
| 資料 4 同步 | `lib/core/sync/`（21 檔）；另走了呼叫端 `lib/features/settings/local_book_sync_dialog.dart`、`lib/features/book_detail/change_cover_sheet.dart`、`lib/shared/widgets/book/book_cover_widget.dart`、`BookStorageService.discardBook` | 3（修 4-2 時另外發現 1 筆，4-4） |

## 問題

### 資料 0 資料庫與模型

沒有找到。

### 資料 1 下載與儲存

#### 1-1. 書源改了網址、或重複書源被合併之後，那些書已下載的漫畫與有聲書全變成「沒下載」，插圖也不見；舊檔案留在手機裡再也不會被刪（已修，#563）

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

#### 1-2. 在下載佇列刪掉一個剛開始、還在抓目錄的任務，重開 App 後它以「已暫停」又出現（已修，#551）

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

#### 2-1. 重裝夜讀或換新手機還原備份後，書架上的書幾乎都畫成預設封面，要一本本點進書籍詳情才會換回真的封面（已修，#550）

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

**修法方向**：修在最初出錯的地方：本機檔案路徑是這台手機的東西，不該跟著書出去。備份與書架匯出寫書時拿掉 `coverLocalPath`、`customCoverLocalPath`；還原與匯入時也把讀進來的這兩欄清掉（舊備份已經帶著），下次顯示就用網址、詳情頁再照常存一份。從相簿選的自訂封面連 `customCoverUrl` 本身都是這台的檔案路徑（`file://…`），拿掉本機路徑後仍畫成預設封面，和 4-1 一起修。書架同步沒有這個問題：加書只帶 `_addFields`，不含兩個本機路徑（`lib/core/sync/bookshelf_sync.dart:67-84`）。

**輕重**：畫面錯

#### 2-2. 匯入書架檔時，書架上已經有的同一本書，閱讀進度、分組、自訂封面被檔案裡的舊資料蓋掉，已下載好的章節還可能被換成「抓取失敗」（已修，#564）

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

### 資料 3 啟動、背景工作與 Android

沒有找到。

### 資料 4 同步

#### 4-1. 從相簿選的自訂封面，全面同步到另一台後畫成預設封面，再也換不回來（已修，#550）

**會發生什麼**：讀者在書籍詳情「換封面」從相簿選一張圖。按「立即全面同步」後，另一台書架上的同一本書（或同步新加進去的這本）改畫預設封面，原本書源的封面也不見了；在那台打開書籍詳情也補不回來，要在那台重新換一次封面。

**為什麼**：
1. 從相簿選的封面記成這台 App 暫存資料夾裡的檔案路徑，當成封面網址存：`lib/features/book_detail/change_cover_sheet.dart:81-83`
   ```dart
   final image = await _picker.pickImage(source: ImageSource.gallery);
   if (image == null || !mounted) return;
   await applyCoverFromSheet(context, 'file://${image.path}');
   ```
   → `BookDetailProvider.updateCover` 寫進 `customCoverUrl`，再複製一份到書本資料夾記在 `customCoverLocalPath`（`lib/features/book_detail/book_detail_provider.dart:937-944`）。這台顯示的是那份複本。
2. 書架同步把 `customCoverUrl` 當成「使用者自己改的」送給別台：`lib/core/sync/bookshelf_sync.dart:87-93`（`_userFields`）、`98-108`（`recordOf`）。
3. 另一台套用：書架上已有這本書時 `_writeUserFields`（同檔 `357-369`）→ `BookDao.updateUserFields` 寫入這串路徑，並因為封面網址換了清掉那台的 `customCoverLocalPath`（`lib/core/database/dao/book_dao.dart:204-225`）；沒有這本書時照雲端那筆整本加入（`bookshelf_sync.dart:263-269`），同樣帶著這串路徑。
4. 顯示時自訂封面網址排在書源封面前面（`lib/core/models/book/book_extensions.dart:47-58`），`file://` 指著另一台手機的檔，讀不到就畫預設封面：`lib/shared/widgets/book/book_cover_widget.dart:436-451` 的 `errorBuilder` → `_buildFailedCover`（同檔 `521-532`）。
5. 那台打開書籍詳情時 `_storeDisplayCover` → `ensureCustomCoverStored`（`lib/core/storage/book_cover_storage_service.dart:52-66`）→ `_storeCoverSource`（同檔 `148-167`）讀這串路徑失敗、傳回 null，`customCoverLocalPath` 一直是空的。

同一個原因：備份與書架匯出也用 `Book.toJson` 帶著 `customCoverUrl`（`lib/core/models/book/book_serialization.dart:41`），還原或匯入到新手機一樣畫成預設封面（見 2-1）。

**怎麼確認**：`test/core/sync/` 的兩台手機書架測試加一項：A 書架上一本書的 `customCoverUrl` 是 `file://` 開頭、指著 A 的暫存資料夾裡的檔；A、B 依序全面同步；斷言 B 那本書的 `getDisplayCover()` 不是指著 B 上不存在檔案的路徑（應該是 B 自己的封面）。

**修法方向**：修在最初出錯的地方：從相簿選的圖不是網址，是這台的檔案，不該當成「使用者改的封面網址」離開這台。書架同步、備份、書架匯出送出書時，`file://` 開頭的 `customCoverUrl` 不送（別台保留自己的封面）；收到舊版送來的 `file://` 自訂封面時也不套用。要讓別台也看到這張圖，得另外把圖檔本身帶過去，那是新功能，不在這次。

**輕重**：畫面錯

#### 4-2. 兩台互相補齊同一本本地漫畫後，在這台移出書架，下次按「同步本地書」整本又被下載回來（已修，#539）

**會發生什麼**：同一本本地漫畫兩台各有對方沒有的話（例如一台之後補了前面幾話），按「同步本地書」會同時上傳這台多的、下載雲端多的。之後在這台把這本移出書架，再按一次「同步本地書」，確認框列的是「下載」而不是刪掉雲端的：開始同步後整本重新下載、加回書架，雲端那本也沒刪，另一台不會跟著移出。

**為什麼**：
1. 兩邊都有、各有對方沒有的話時排兩件事：`lib/core/sync/local_book_sync.dart:688-706`
   ```dart
   if (uploads) tasks.add(_localTask(LocalBookAction.upload, print, mine));
   if (downloads) {
     tasks.add(_remoteTask(LocalBookAction.download, print, theirs));
   }
   ```
   下載那件帶著比對當時雲端紀錄的時間（`_remoteTask` 的 `remoteTime`，同檔 `832-849`）。同一種排序照動作，上傳先做（同檔 `759-762`）。
2. 上傳把雲端紀錄寫成新的時間，上次同步的紀錄也記這個新時間：同檔 `298-306` → `_uploadComic` 寫紀錄（`507-523`，`time: _clock()...`）。
3. 接著下載把上次同步的紀錄改回比對當時的舊時間：同檔 `307-310`
   ```dart
   case LocalBookAction.download:
     await _download(task);
     shelfChanged = true;
     base[task.fingerprint] = _entry(task.remoteTime, task.extension);
   ```
   按鈕跑完不再比對一次（`lib/features/settings/local_book_sync_dialog.dart:59-63`、`92-100`），舊時間就留著。
4. 移出書架後再按，比對看到這台沒有、雲端那筆的時間和上次同步記的不同，判成「雲端是新的」而下載，不是「這台移出了」：`local_book_sync.dart:726-735`
   ```dart
   final removedHere = last != null && last.time == theirs.time;
   ```
   → `_downloadComic`（同檔 `528-583`）把每一話重新下載、匯入成一本書。

只有「互相補齊之後、下一次按『同步本地書』之前就移出書架」才會碰到；中間有再按過一次的話，第 2 步那個新時間會在比對時記回來（同檔 `698-700`、`211-213`）。

**怎麼確認**：`test/core/sync/local_book_sync_test.dart` 加一項：這台一本本地漫畫有 a、b 兩話，雲端那筆有 a、c；`plan()` 後 `run()`；把這本移出書架，再 `plan()`；斷言這本的任務是 `deleteRemote`，不是 `download`。

**修法方向**：修在第 3 步：下載寫上次同步的紀錄時，同一輪已經上傳過這本的，留著上傳寫的時間（或兩件都做完後照雲端紀錄現在的時間記），不拿比對當時的舊時間蓋掉。

**輕重**：功能沒反應或結果錯

#### 4-3. 同一本網路書在兩台的書名不同時，全面同步幾次後，其中一台的那本被移出書架、已下載的章節全部刪掉（已修，#538）

**會發生什麼**：同一本網路書（書的網址相同）在兩台的書名或作者不一樣，而且不是「兩台都同步過之後才改名」：例如在開始用同步之前，在一台「編輯資訊」改過書名，或那台的書源更新了書名。開同步後，兩台各按幾次「立即全面同步」，其中一台會把書名不同的那一本當成「另一台移出書架了」：那台的這本被移出書架，已下載的正文、目錄、封面都刪掉；接著可能照另一台的書名重新加入、整本重新下載（閱讀進度換成另一台的），也可能下一輪連另一台的那本一起刪掉，兩台都沒有這本書。沒網路或書源失效時，原本離線可讀的章節就讀不到了。

**為什麼**（以 A 上叫「乙」、B 上叫「甲」為例，鍵是書名加作者）：
1. B 第一次全面同步：雲端有 A 送的「乙」，B 沒有這個鍵、也沒同步過，判成要套用（`lib/core/sync/sync_records.dart:152-156`）。這不是同步裡記到的改名：A 改名時還沒同步過，沒有「甲」的刪除紀錄可對（`lib/core/sync/bookshelf_sync.dart:307-310`）。
2. 套用時用書的網址找到 B 書架上的那本「甲」，因為它在書架上，不改名，只寫使用者改的欄位，卻照樣把它回報成「乙」那一筆套用好了：`bookshelf_sync.dart:240-262`
   ```dart
   final existing = await _bookDao.getByUrl(incoming.bookUrl);
   if (existing != null) {
     if (ProgressSync.keyOf(existing) != key &&
         ProgressSync.keyOf(incoming) == key &&
         !existing.isInBookshelf) {
       ...
     }
     ...
     applied[key] = recordOf(existing);
   ```
   同步服務照它記下「『乙』在 B 同步過」（`lib/core/sync/sync_service.dart:804-813`）。
3. B 下一次全面同步：書架上還是只有「甲」，上次同步的紀錄有「乙」、現在沒有，補成這台刪掉了（`lib/core/sync/sync_merge.dart:171-175`；`BookshelfSync.reconcile` 只作廢本地書的舊紀錄，`bookshelf_sync.dart:182-191`）；雲端那筆沒變、這台變了，送出「乙」的刪除紀錄（`sync_records.dart:163-167`）。
4. A 下一次全面同步：雲端的「乙」被刪、A 沒改過，套用刪除（`sync_records.dart:169`）→ `bookshelf_sync.dart:218-224` 對 A 的「乙」呼叫 `discardBook`，刪掉下載任務、正文、目錄、書本身與書本資料夾（`lib/core/storage/book_storage_service.dart:49-55`）。B 第一次同步送上去的「甲」在同一輪套用：先處理到「甲」的話，A 的那本也走第 2 步、被記成「甲」同步過，接著被刪，下一輪 A 再送出「甲」的刪除、刪掉 B 的；先處理到「乙」的刪除的話，「甲」被當成新書加入、整本下載（`bookshelf_sync.dart:263-271`）。

在停用同步或換同步空間期間改名也可能走到這裡（看兩台同步的先後，另一種順序會由 `_applyRenames` 原地改名）：上次同步的紀錄清掉了，舊名字沒有刪除紀錄，第 1 步一樣認不出是改名。已經同步過再改名的情形是 #206，已修好，走的是 `_applyRenames`；用 `gh issue list --state all` 搜過「改名 同步 移出書架」「書名 不同 同步」「discardBook」等，沒有報過書名在同步前就不同的情形。

**怎麼確認**：`test/core/sync/sync_service_test.dart` 的兩台手機書架測試加一項：A、B 書架上同一個 `bookUrl` 的書，A 叫「乙」、B 叫「甲」，B 有已下載的正文；兩台都沒同步過。A、B、B、A 依序全面同步；斷言 A、B 都還有這本書（`discardBook` 沒被呼叫），B 的正文還在。

**修法方向**：修在第 2 步：這台書架上的那本書鍵不同時，不要回報成套用了這個鍵（這台沒有這個鍵的書，就不該記成同步過）；要嘛照雲端那筆原地改名、兩台統一成同一個書名，要嘛這一筆留在雲端不動。同一個原因要一起看 `existing` 不在書架上時改名的那條（同檔 `245-258`），兩條對同一個網址的處理要一致。

**輕重**：資料遺失或寫壞

#### 4-4. 本地漫畫上傳到一半失敗後移出書架，已經傳上去的那幾話一直留在同步空間（已修，#566）

修 4-2（#539）時審查發現，以前就有。

**會發生什麼**：按「同步本地書」上傳本地漫畫，傳了幾話之後失敗（後面某一話傳不上去、連線斷了，或雲端紀錄寫不進去），讀者在下一次成功同步之前把這本移出書架。之後再按「同步本地書」，傳上去的那幾話不會被刪，一直佔著同步空間；漫畫一話常有好幾 MB。

**為什麼**：
1. 上傳本地漫畫是一話一話寫，全部寫完才寫雲端紀錄（記著有哪幾話）：`lib/core/sync/local_book_sync.dart:495-509` → `517-532`（`_putRecord`）。中途丟出錯誤的話，已經寫上去的那幾話沒有任何紀錄指著。
2. 移出書架後刪雲端，只刪雲端紀錄列出的那幾話：同檔 `450-468`（`_deleteRemote` 照 `task.chapters`，來自雲端紀錄）。沒寫進紀錄的那幾話不在裡面。
3. 從沒傳成過的漫畫（雲端沒有紀錄）移出書架後，「刪掉沒人記著的原檔」那條只認 TXT、EPUB，本地漫畫直接略過：同檔 `747-751`
   ```dart
   // 本地漫畫不知道傳了哪幾話，沒人記著的章檔留在雲端。
   if (theirs == null &&
       last != null &&
       isSupportedLocalBookExtension(last.local)) {
   ```

**怎麼確認**：`test/core/sync/local_book_sync_test.dart` 加一項：一本本地漫畫有三話，第三話的上傳設成失敗（`failingBlobs`）；按一次（失敗）；移出書架；再按一次並執行；斷言同步空間裡沒有 `comic_` 開頭的檔。另一項是已同步過、補了兩話、第二話失敗，同樣斷言補上去的第一話被清掉。

**修法方向**：上傳每一話之前，先在這台上次同步的紀錄旁記下「傳上去、還沒寫進雲端紀錄的話」，寫進雲端紀錄後清掉；下一次失敗或下一次按「同步本地書」時，這本已經不在書架上（或那幾話不在雲端紀錄裡、也沒有別筆紀錄記著），就把這些話刪掉。

**輕重**：功能沒反應或結果錯

## #526 核對結果

GPT 那份讀資料的報告（#526）逐條走到 `origin/beta`（`7c89cc63`）核實。

| 條 | 一句話 | 結論 |
|---|---|---|
| 1 | 暫停全部時刪掉正在下載的任務，同一本加不回佇列；抓目錄時刪掉的任務又出現 | 已修：後半 #551（同 1-2），前半 #590（暫停中的那一輪聽得到刪除；刪掉後舊的那一輪還在收尾時再加入，等它收完再排） |
| 2 | 開 App 清理暫存途中剛打開的書被清掉 | 不修：清理拿到「開著的書」之後只多等一次資料庫查詢，這段空檔打開的書和晚一點打開的一樣（暫存本來就照設計清掉、重新向書源抓），而且詳情頁讀資料庫會排在清理的交易之後，不會讀到一半；讀者碰不到和設計不同的結果 |
| 3 | 還原備份時正在下載的同一本書，舊下載把還原的「已暫停」蓋成完成 | 已修（#612） |
| 4 | 補回缺失原檔時，誤刪另一本還在用的同名原檔 | 已修（#592） |
| 5 | 匯入書架檔帶回的正文有插圖，沒排插圖補抓 | 已修（#606，連同換源、匯出全書補抓時暫時連不上的插圖） |
| 6 | 本地書缺原檔時匯出全書把「檔案不存在」寫成正文 | 已修（#620） |
| 7 | iPhone 的崩潰日誌載入失敗、存不下 | 早就修好（#570，`f53ee569`） |
| 8 | 匯入本地漫畫時，名稱只差符號的兩個章資料夾併成一話 | 已修（#621；repo 沒有 Android 原生單元測試，沒有自動測試） |
| 9 | 接連還原兩台的備份後，閱讀時數重複算 | 已修（#619，連同還原後改書名、還原沒用過同步的備份） |
| 10 | 同一本地書有兩筆時，較新重新加入的被列為移除、完好的原檔傳不上去 | 已修（#603）；同一本本地漫畫兩筆各有不同話時只看其中一筆，改前就是如此、情境極少，沒有一起改 |

## 拿不準

- **這台從沒同步過（剛開始用、重裝、停用後再打開、換了同步空間）時，雲端有刪除紀錄的那一筆，這台手上的會被刪掉**：例如另一台幾個月前把某本書移出書架、刪了某個書源，這台後來自己加了同名同作者的書、匯入了同一個書源，第一次全面同步就被移出書架或刪掉。路徑：沒同步過、雲端也有這個鍵的那筆時間算 0（`lib/core/sync/sync_merge.dart:164-165`），和刪除紀錄比時間雲端贏（`lib/core/sync/sync_records.dart:160-161`），套用刪除（書架 `lib/core/sync/bookshelf_sync.dart:218-224`、書源 `lib/core/sync/source_sync.dart:155`）。拿不準的是這算不算刻意的：ADR 0039「修改時間照上次同步推算」寫了「從沒同步過的這台和雲端內容不同時雲端的贏」，又寫「這台才有的照樣送上去」，雲端只剩刪除紀錄時算哪一種沒寫。同步本地書在同一個情形有比「加進書架的時間」和刪除時間（`lib/core/sync/local_book_sync.dart:716-723`），書架與書源沒有。要使用者定：從沒同步過的這台遇到雲端的刪除紀錄，是照雲端刪掉，還是當成這台才有的送上去。
