import 'dart:io';
import 'dart:typed_data';

import 'package:night_reader/core/comic/local_comic_library.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/local_book/local_book_fingerprint.dart';
import 'package:night_reader/core/local_book/local_book_formats.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/book_storage_service.dart';
import 'package:night_reader/core/services/local_book_service.dart';
import 'package:night_reader/core/services/local_comic_service.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:path/path.dart' as p;

import 'progress_sync.dart';
import 'sync_base_storage.dart';
import 'sync_records.dart';
import 'sync_store.dart';

/// 「同步本地書」要對一本書做的事。
enum LocalBookAction {
  /// 這台有、雲端沒有：上傳原檔與小紀錄。
  upload,

  /// 雲端有、這台沒有：下載原檔、加進書架。
  download,

  /// 另一台移出書架了：這台也移出。
  removeHere,

  /// 這台移出書架了：刪掉雲端的原檔，小紀錄記成刪除。
  deleteRemote,
}

/// 一本本地書要做的事。
class LocalBookTask {
  const LocalBookTask({
    required this.action,
    required this.fingerprint,
    required this.name,
    required this.author,
    required this.extension,
    required this.size,
    this.path,
    this.bookUrls = const [],
    this.remoteTime = 0,
    this.chapters = const [],
  });

  final LocalBookAction action;
  final String fingerprint;
  final String name;
  final String author;

  /// 原檔的副檔名（不含點）：`txt`、`epub`，本地漫畫是
  /// [LocalBookSync.comicExtension]。
  final String extension;

  /// 原檔的大小（位元組）。
  final int size;

  /// 上傳：這台原檔的路徑。
  final String? path;

  /// 移出書架：這台指著這個原檔的書。
  final List<String> bookUrls;

  /// 下載：雲端那筆紀錄的時間，記進上次同步的紀錄。
  final int remoteTime;

  /// 本地漫畫的每一話（章指紋、章名）：上傳是這台的，下載與刪除是雲端的。
  final List<ComicSyncChapter> chapters;
}

/// 本地漫畫的一話：章指紋與章名（ADR 0052）。
typedef ComicSyncChapter = ({String fingerprint, String title});

/// 按下「同步本地書」先算好的事，給確認框顯示（[LocalBookSync.plan]）。
class LocalBookSyncPlan {
  const LocalBookSyncPlan({required this.tasks, required this.settled});

  final List<LocalBookTask> tasks;

  /// 兩邊都有、不用做事的書：上次同步的紀錄記成同步過。
  final Map<String, SyncBaseEntry> settled;

  bool get isEmpty => tasks.isEmpty;

  List<LocalBookTask> of(LocalBookAction action) => [
    for (final task in tasks)
      if (task.action == action) task,
  ];

  int bytesOf(LocalBookAction action) =>
      of(action).fold(0, (sum, task) => sum + task.size);
}

/// 同步本地書做到哪：第幾件（從 1 起算）、共幾件、正在做的那本。
typedef LocalBookSyncProgress = ({int step, int total, LocalBookTask task});

/// 一本沒做成的書與原因（給使用者看的）。
typedef LocalBookFailure = ({LocalBookTask task, String reason});

/// 同步本地書的結果。
class LocalBookSyncResult {
  const LocalBookSyncResult({
    required this.done,
    required this.failures,
    required this.cancelled,
  });

  final int done;
  final List<LocalBookFailure> failures;
  final bool cancelled;
}

/// 給使用者看的失敗原因。
class LocalBookSyncException implements Exception {
  const LocalBookSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 「同步本地書」（ADR 0039）：使用者在「備份與同步」按了才做，和全面同步
/// 分開。書架上的本地書（TXT、EPUB）照原檔指紋對上：這台有、雲端沒有的上傳
/// 原檔（TXT 先壓縮，用指紋命名，每個檔只傳一次），雲端有、這台沒有的下載
/// 後照一般匯入加進書架；同步過的書在某台移出書架，那台按的時候刪掉雲端的
/// 原檔，另一台按的時候跟著移出。誰改了、誰刪了照上次同步的紀錄判斷，同
/// 「刪除也跟著同步」。
///
/// 每本書做完就寫雲端的小紀錄與上次同步的紀錄：取消或中途失敗時，做完的
/// 留著，沒做完的下次按的時候重做。
class LocalBookSync {
  LocalBookSync({
    required this._store,
    required this._bases,
    required this._bookDao,
    required this._chapterDao,
    this._storage,
    LocalBookService? books,
    this._run = runLocalBookWorkInBackground,
    DateTime Function()? clock,
    bool Function(String key)? isOpen,
  }) : _books = books ?? LocalBookService(),
       _clock = clock ?? DateTime.now,
       _isOpen = isOpen ?? _never;

  /// 上次同步的紀錄的名稱，也是雲端小紀錄的檔名（`local_books.json`）。
  static const String kind = 'local_books';
  static const String fileName = '$kind.json';

  final SyncStore _store;
  final SyncBaseStorage _bases;
  final BookDao _bookDao;
  final ChapterDao _chapterDao;
  final BookStorageService? _storage;
  final LocalBookService _books;
  final LocalBookWorkRunner _run;
  final DateTime Function() _clock;
  final bool Function(String key) _isOpen;

  static bool _never(String key) => false;

  /// 同一份小紀錄被別台同時寫入時，重讀再寫的次數。
  static const int _maxAttempts = 3;

  /// 雲端原檔的檔名：`book_<指紋>.txt.gz`、`book_<指紋>.epub`。EPUB 本身就
  /// 是壓縮檔，不再壓。
  static String originalName(String fingerprint, String extension) =>
      'book_$fingerprint.$extension${extension == 'txt' ? '.gz' : ''}';

  /// 本地漫畫的副檔名欄位：它不是一個原檔，是一個資料夾、一話一個 CBZ
  /// （ADR 0052）。雲端每話一個 `comic_<章指紋>.cbz`，每話只傳一次；紀錄
  /// 裡記著有哪幾話。書的鍵起初是匯入時第一話的章指紋，兩台的同一本
  /// （有共同的一話）記在不同的鍵時，同步時統一成較小的那個
  /// （[adoptComicKeys]）。
  static const String comicExtension = 'comic';

  static String comicChapterName(String fingerprint) =>
      'comic_$fingerprint.cbz';

  /// 算出要做的事，還不動手。這一版以前匯入、還沒有指紋的本地書先在背景
  /// isolate 補算；解析雲端的小紀錄與比對也在背景 isolate（ADR 0046）。
  ///
  /// 兩邊都有的書這時就記成同步過（[LocalBookSyncPlan.settled]）：不用做事
  /// 也要記，之後這台移出書架才分得出是這台移出的。
  Future<LocalBookSyncPlan> plan() async {
    await fillLocalBookFingerprints(_bookDao, run: _run);
    var local = await _shelf();
    final file = await _store.read(fileName);
    final adopted = await _adoptionsOn(_run, file?.content, local);
    if (adopted.isNotEmpty) {
      for (final MapEntry(key: from, value: to) in adopted.entries) {
        for (final url in local[from]!.bookUrls) {
          await _bookDao.updateFileFingerprint(url, to);
        }
      }
      AppEventBus().fire(AppEventBus.upBookshelf);
      local = await _shelf();
    }
    final base = await _bases.read(kind);
    final plan = await _planOn(_run, file?.content, local, base);
    if (plan.settled.isNotEmpty) {
      await _bases.write(kind, {...await _bases.read(kind), ...plan.settled});
    }
    return plan;
  }

  /// 書架上每個原檔指紋的本地書。原檔大小這時才量；原檔不見了的記下來，
  /// 雲端有就下載補回。
  Future<Map<String, LocalShelfBook>> _shelf() async {
    final shelf = <String, LocalShelfBook>{};
    for (final book in await _bookDao.getInBookshelf()) {
      final print = book.fileFingerprint;
      if (!book.isLocal || print == null) continue;
      if (shelf[print] case final same?) {
        shelf[print] = same.withBook(book.bookUrl);
        continue;
      }
      final path = LocalBookService.filePathOf(book);
      if (book.bookKind == BookSourceKind.comic) {
        shelf[print] = await _comicShelfBook(book, path);
        continue;
      }
      final file = File(path);
      final hasFile = await file.exists();
      shelf[print] = LocalShelfBook(
        name: book.name,
        author: book.author,
        extension: localBookExtensionFromPath(path),
        size: hasFile ? await file.length() : 0,
        hasFile: hasFile,
        addedTime: book.syncTime,
        path: path,
        bookUrls: [book.bookUrl],
      );
    }
    return shelf;
  }

  /// 書架上的一本本地漫畫：書的資料夾裡每話一個 CBZ。只算檔案真的在的
  /// 話：還原或補檔中斷少了幾話時，雲端有的照常下載補回，也不會把沒有的
  /// 話記成傳上去了。
  Future<LocalShelfBook> _comicShelfBook(Book book, String path) async {
    final chapters = <BookChapter>[];
    var size = 0;
    for (final chapter in await _chapterDao.getByBook(book.bookUrl)) {
      final file = File(LocalComicService.chapterPathOf(book, chapter));
      if (!await file.exists()) continue;
      chapters.add(chapter);
      size += await file.length();
    }
    return LocalShelfBook(
      name: book.name,
      author: book.author,
      extension: comicExtension,
      size: size,
      hasFile: await Directory(path).exists(),
      addedTime: book.syncTime,
      path: path,
      bookUrls: [book.bookUrl],
      chapters: [
        for (final chapter in chapters)
          (fingerprint: chapter.url, title: chapter.title),
      ],
    );
  }

  /// 照 [plan] 做，一次一本。[cancelled] 在兩本之間看，傳回 true 就停下；
  /// 已經做完的留著。整個同步空間用不了（連不上、授權失效）時剩下的不再
  /// 試，其他失敗記下原因、接著做下一本。
  Future<LocalBookSyncResult> run(
    LocalBookSyncPlan plan, {
    void Function(LocalBookSyncProgress progress)? onProgress,
    bool Function()? cancelled,
  }) async {
    final base = await _bases.read(kind);
    final failures = <LocalBookFailure>[];
    var done = 0;
    var shelfChanged = false;
    var stopped = false;
    for (final (index, task) in plan.tasks.indexed) {
      if (cancelled?.call() ?? false) {
        stopped = true;
        break;
      }
      onProgress?.call((step: index + 1, total: plan.tasks.length, task: task));
      try {
        switch (task.action) {
          case LocalBookAction.upload:
            // 原檔傳上去、小紀錄還沒寫成時先記著：這台之後移出書架的話，
            // 下次按的時候照它刪掉雲端沒人記著的原檔。
            base[task.fingerprint] = _entry(0, task.extension);
            await _bases.write(kind, base);
            base[task.fingerprint] = _entry(
              await _upload(task),
              task.extension,
            );
          case LocalBookAction.download:
            await _download(task);
            shelfChanged = true;
            base[task.fingerprint] = _entry(task.remoteTime, task.extension);
          case LocalBookAction.removeHere:
            await _removeHere(task);
            shelfChanged = true;
            base.remove(task.fingerprint);
          case LocalBookAction.deleteRemote:
            await _deleteRemote(task);
            // 留著上次同步的紀錄：刪除紀錄被別台同時寫入蓋回去時，下次按
            // 的時候還認得出是這台移出的，再刪一次。
            base[task.fingerprint] = _entry(task.remoteTime, task.extension);
        }
        await _bases.write(kind, base);
        done++;
      } on SyncStoreException catch (error) {
        failures.add((task: task, reason: error.message));
        if (error.wholeSpace) break;
      } on LocalBookSyncException catch (error) {
        failures.add((task: task, reason: error.message));
      } catch (error, stackTrace) {
        AppLog.e('同步本地書失敗：${task.name}', error: error, stackTrace: stackTrace);
        failures.add((task: task, reason: _reasonOf(error)));
      }
    }
    if (shelfChanged) AppEventBus().fire(AppEventBus.upBookshelf);
    return LocalBookSyncResult(
      done: done,
      failures: failures,
      cancelled: stopped,
    );
  }

  static String _reasonOf(Object error) => switch (error) {
    FileSystemException() => '這台手機讀寫檔案失敗',
    FormatException() => '同步空間裡的紀錄不是夜讀寫的',
    _ => '$error',
  };

  /// 上次同步的紀錄：雲端那筆的時間，與原檔的副檔名（雲端的紀錄不見了時，
  /// 靠它找到要刪的原檔）。
  static SyncBaseEntry _entry(int time, String extension) =>
      SyncBaseEntry(local: extension, remote: extension, time: time);

  /// 上傳原檔與小紀錄，傳回小紀錄的時間。
  Future<int> _upload(LocalBookTask task) async {
    if (task.extension == comicExtension) return _uploadComic(task);
    final path = task.path;
    if (path == null || !await File(path).exists()) {
      throw const LocalBookSyncException('這台手機上的原檔不見了，重新匯入這本書再同步');
    }
    final bytes = await _packOn(_run, path, task.extension);
    await _store.writeBytes(
      originalName(task.fingerprint, task.extension),
      bytes,
    );
    final time = _clock().millisecondsSinceEpoch;
    await _putRecord(
      task.fingerprint,
      SyncRecord(
        time: time,
        data: {
          'name': task.name,
          'author': task.author,
          'ext': task.extension,
          'size': task.size,
        },
      ),
    );
    return time;
  }

  Future<void> _download(LocalBookTask task) async {
    if (task.extension == comicExtension) return _downloadComic(task);
    final bytes = await _store.readBytes(
      originalName(task.fingerprint, task.extension),
    );
    if (bytes == null) {
      throw const LocalBookSyncException('雲端找不到這本的原檔，請在另一台再按一次「同步本地書」');
    }
    final path = await LocalBookService.freeLibraryPath(
      task.name,
      '.${task.extension}',
      bookDao: _bookDao,
    );
    final ok = await _unpackOn(
      _run,
      bytes,
      task.extension,
      path,
      task.fingerprint,
    );
    if (!ok) {
      throw const LocalBookSyncException('下載的原檔不完整，下次再試');
    }
    final Book? book;
    try {
      book = await _books.addToShelf(
        path,
        bookDao: _bookDao,
        chapterDao: _chapterDao,
        fingerprint: task.fingerprint,
        name: task.name,
        author: task.author,
      );
    } catch (_) {
      await _deleteQuietly(path);
      rethrow;
    }
    if (book == null) {
      await _deleteQuietly(path);
      throw const LocalBookSyncException('這個檔讀不出書的內容');
    }
    // 書架上本來就有同一個檔（指紋相同）時，下載的這份用不到。
    if (LocalBookService.filePathOf(book) != path) await _deleteQuietly(path);
  }

  Future<void> _removeHere(LocalBookTask task) async {
    final storage = _storage ?? BookStorageService();
    for (final url in task.bookUrls) {
      final book = await _bookDao.getByUrl(url);
      if (book == null) continue;
      if (_isOpen(ProgressSync.keyOf(book)) ||
          _isOpen(ProgressSync.nameKeyOf(book))) {
        throw const LocalBookSyncException('這本書正開著，關掉後再按一次');
      }
      await storage.discardBook(book);
    }
  }

  /// 先刪原檔再把小紀錄記成刪除：小紀錄寫不進去時下次按會再刪一次（原檔
  /// 已經沒了也正常），不會留下沒人指著的原檔。
  Future<void> _deleteRemote(LocalBookTask task) async {
    if (task.extension == comicExtension) {
      // 另一筆還記著的話不刪：同一本換過鍵時，舊鍵那筆的每一話新鍵也有。
      final file = await _store.read(fileName);
      final kept = <String>{
        if (file != null)
          for (final MapEntry(:key, :value) in SyncDocument.decode(
            file.content,
          ).records.entries)
            if (key != task.fingerprint && !value.deleted)
              for (final chapter in comicChaptersOf(value.data))
                chapter.fingerprint,
      };
      for (final chapter in task.chapters) {
        if (kept.contains(chapter.fingerprint)) continue;
        await _store.delete(comicChapterName(chapter.fingerprint));
      }
    } else {
      await _store.delete(originalName(task.fingerprint, task.extension));
    }
    await _putRecord(
      task.fingerprint,
      SyncRecord(
        time: _clock().millisecondsSinceEpoch,
        data: const {},
        deleted: true,
      ),
    );
  }

  /// 本地漫畫：雲端還沒有的話一話一話傳上去，紀錄記成兩邊所有的話。
  Future<int> _uploadComic(LocalBookTask task) async {
    final path = task.path;
    if (path == null || !await Directory(path).exists()) {
      throw const LocalBookSyncException('這台手機上的漫畫不見了，重新匯入再同步');
    }
    final file = await _store.read(fileName);
    final remote = file == null
        ? null
        : SyncDocument.decode(file.content).records[task.fingerprint];
    final known = remote == null || remote.deleted
        ? const <ComicSyncChapter>[]
        : comicChaptersOf(remote.data);
    final uploaded = {for (final chapter in known) chapter.fingerprint};
    var size = 0;
    for (final chapter in task.chapters) {
      final local = File(
        p.join(
          path,
          '${chapter.fingerprint}${LocalComicLibrary.chapterExtension}',
        ),
      );
      if (!await local.exists()) continue;
      size += await local.length();
      if (uploaded.contains(chapter.fingerprint)) continue;
      await _store.writeBytes(
        comicChapterName(chapter.fingerprint),
        await local.readAsBytes(),
      );
      uploaded.add(chapter.fingerprint);
    }
    final mine = {for (final chapter in task.chapters) chapter.fingerprint};
    final all = [
      ...task.chapters,
      for (final chapter in known)
        if (!mine.contains(chapter.fingerprint)) chapter,
    ];
    final time = _clock().millisecondsSinceEpoch;
    await _putRecord(
      task.fingerprint,
      SyncRecord(
        time: time,
        data: {
          'name': task.name,
          'author': task.author,
          'ext': comicExtension,
          'size': size,
          'chapters': [
            for (final chapter in all) [chapter.fingerprint, chapter.title],
          ],
        },
      ),
    );
    return time;
  }

  /// 本地漫畫：這台還沒有的話下載下來，併進同一本（有共同的話就是同一本，
  /// 同匯入）；這台沒有這本就新加一本。
  Future<void> _downloadComic(LocalBookTask task) async {
    // 這台檔案還在的話不再下載；還原備份帶回了目錄、沒帶回檔案的照樣抓。
    final have = <String>{};
    for (final book in await _bookDao.getInBookshelf()) {
      if (!book.isLocal || book.bookKind != BookSourceKind.comic) continue;
      for (final chapter in await _chapterDao.getByBook(book.bookUrl)) {
        final file = File(LocalComicService.chapterPathOf(book, chapter));
        if (await file.exists()) have.add(chapter.url);
      }
    }
    final temp = await AppStoragePaths.temporaryDir();
    final staging = Directory(
      p.join(temp.path, 'comic_sync', task.fingerprint),
    );
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    try {
      for (final (index, chapter) in task.chapters.indexed) {
        if (have.contains(chapter.fingerprint)) continue;
        final bytes = await _store.readBytes(
          comicChapterName(chapter.fingerprint),
        );
        if (bytes == null) {
          throw const LocalBookSyncException('雲端少了這本的幾話，請在另一台再按一次「同步本地書」');
        }
        // 檔名照原本的順序編號（章名可能重複），章名另外交給匯入。
        final target = File(
          p.join(staging.path, '${index.toString().padLeft(5, '0')}.cbz'),
        );
        await target.writeAsBytes(bytes, flush: true);
        if (await _comicFingerprintOn(_run, target.path) !=
            chapter.fingerprint) {
          throw const LocalBookSyncException('下載的漫畫不完整，下次再試');
        }
      }
      if (await staging.list().isEmpty) return;
      final book =
          await LocalComicService(
            bookDao: _bookDao,
            chapterDao: _chapterDao,
            run: _run,
          ).importPath(
            staging.path,
            name: task.name,
            fingerprint: task.fingerprint,
            related: {for (final chapter in task.chapters) chapter.fingerprint},
            titles: {
              for (final chapter in task.chapters)
                chapter.fingerprint: chapter.title,
            },
          );
      if (book == null) throw const LocalBookSyncException('這本漫畫讀不出圖');
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  /// 改雲端小紀錄裡的一筆：讀、改、寫回；被別台搶先就重讀再改。一直被搶先
  /// 就算這本失敗、下次再做，不比版本直接寫：那會蓋掉別台剛寫的刪除紀錄，
  /// 而刪除的那台已經不再有那本書，補不回來。
  Future<void> _putRecord(String fingerprint, SyncRecord record) async {
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      final file = await _store.read(fileName);
      final content = await _putRecordOn(
        _run,
        file?.content,
        fingerprint,
        record,
      );
      try {
        await _store.write(
          fileName,
          content,
          ifVersion: file?.version,
          ifAbsent: file == null,
        );
        return;
      } on SyncConflict {
        continue;
      }
    }
    throw const SyncStoreException.file('另一台手機同時在同步本地書，稍後再按一次');
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (error) {
      AppLog.e('刪除下載的本地書原檔失敗', error: error);
    }
  }
}

/// 書架上的一本本地書（同一個原檔加了兩次的話，兩本都在 [bookUrls]）。
class LocalShelfBook {
  const LocalShelfBook({
    required this.name,
    required this.author,
    required this.extension,
    required this.size,
    required this.addedTime,
    required this.path,
    required this.bookUrls,
    this.hasFile = true,
    this.chapters = const [],
  });

  final String name;
  final String author;
  final String extension;
  final int size;

  /// 原檔還在這台手機上（例如還原備份帶回了書，原檔沒帶回來）。
  final bool hasFile;

  /// 加進書架的時間；和雲端的刪除紀錄比新舊用。
  final int addedTime;
  final String path;
  final List<String> bookUrls;

  /// 本地漫畫的每一話；其他本地書是空的。
  final List<ComicSyncChapter> chapters;

  LocalShelfBook withBook(String bookUrl) => LocalShelfBook(
    name: name,
    author: author,
    extension: extension,
    size: size,
    addedTime: addedTime,
    path: path,
    bookUrls: [...bookUrls, bookUrl],
    hasFile: hasFile,
    chapters: chapters,
  );
}

/// 每個原檔指紋，這台（[local]）、雲端（[remote]）與上次同步時（[base]）
/// 比出要做的事。純計算，在背景 isolate 跑。
///
/// - 兩邊都有：不用做事，記成同步過；這台的原檔不見了的話下載補回。
/// - 只有這台有：雲端從沒有過就上傳；雲端記著刪除時，刪除比這台加進書架
///   晚就跟著移出，否則這台是之後才重新加的，再上傳。
/// - 只有雲端有：上次同步之後雲端那筆沒變，是這台移出了，刪掉雲端的；
///   否則下載。
/// - 兩邊都沒有、上次同步時有：原檔傳上去了、小紀錄沒寫成，這台又移出了，
///   刪掉雲端沒人記著的原檔。
LocalBookSyncPlan planLocalBookSync({
  required Map<String, LocalShelfBook> local,
  required Map<String, SyncRecord> remote,
  required Map<String, SyncBaseEntry> base,
}) {
  final tasks = <LocalBookTask>[];
  final settled = <String, SyncBaseEntry>{};
  for (final print in {...local.keys, ...remote.keys, ...base.keys}) {
    final mine = local[print];
    final theirs = remote[print];
    final last = base[print];
    final alive = theirs != null && !theirs.deleted;
    if (mine != null) {
      if (alive &&
          mine.hasFile &&
          mine.extension == LocalBookSync.comicExtension) {
        // 本地漫畫兩邊都有：這台多的話上傳、雲端多的話下載，一樣就算同步過。
        final remotePrints = {
          for (final c in comicChaptersOf(theirs.data)) c.fingerprint,
        };
        final localPrints = {for (final c in mine.chapters) c.fingerprint};
        final uploads = !remotePrints.containsAll(localPrints);
        final downloads = !localPrints.containsAll(remotePrints);
        if (!uploads && !downloads) {
          settled[print] = LocalBookSync._entry(theirs.time, mine.extension);
          continue;
        }
        if (uploads) tasks.add(_localTask(LocalBookAction.upload, print, mine));
        if (downloads) {
          tasks.add(_remoteTask(LocalBookAction.download, print, theirs));
        }
        continue;
      }
      if (alive && mine.hasFile) {
        settled[print] = LocalBookSync._entry(theirs.time, mine.extension);
        continue;
      }
      if (alive) {
        tasks.add(_remoteTask(LocalBookAction.download, print, theirs));
        continue;
      }
      final removedThere = theirs != null && theirs.time >= mine.addedTime;
      tasks.add(
        _localTask(
          removedThere ? LocalBookAction.removeHere : LocalBookAction.upload,
          print,
          mine,
        ),
      );
      continue;
    }
    if (alive) {
      final removedHere = last != null && last.time == theirs.time;
      tasks.add(
        _remoteTask(
          removedHere ? LocalBookAction.deleteRemote : LocalBookAction.download,
          print,
          theirs,
        ),
      );
      continue;
    }
    // 本地漫畫不知道傳了哪幾話，沒人記著的章檔留在雲端。
    if (theirs == null &&
        last != null &&
        isSupportedLocalBookExtension(last.local)) {
      tasks.add(
        LocalBookTask(
          action: LocalBookAction.deleteRemote,
          fingerprint: print,
          name: '沒傳完的原檔',
          author: '',
          extension: last.local,
          size: 0,
        ),
      );
    }
  }
  tasks.removeWhere(
    (task) =>
        !isSupportedLocalBookExtension(task.extension) &&
        task.extension != LocalBookSync.comicExtension,
  );
  // 先做這台書架上的事（快），再傳檔；同一種裡照書名排，進度框看得出順序。
  tasks.sort((a, b) {
    final order = a.action.index.compareTo(b.action.index);
    return order != 0 ? order : a.name.compareTo(b.name);
  });
  return LocalBookSyncPlan(tasks: tasks, settled: settled);
}

/// 本地漫畫的鍵怎麼和雲端對上（ADR 0052：有共同的一話就是同一本）。書的
/// 鍵起初是匯入時第一話的章指紋，兩台從不同話開始匯入、或一台之後補了更
/// 前面的話，同一本就會記在不同的鍵；不統一的話進度對不上，這台還會把
/// 另一台那筆當成這台移出的刪掉。
///
/// 這台每一本本地漫畫，和雲端記著、沒刪掉、有共同一話的其他紀錄，統一成
/// 其中最小的鍵（這台自己那筆也在雲端時一起比）；要改鍵的傳回「舊鍵 →
/// 新鍵」。每台都照同一個規則，最後都落在同一個鍵；舊鍵那筆由記著它的
/// 那台照「這台移出了」刪掉，共用的章檔留著（[LocalBookSync._deleteRemote]）。
Map<String, String> adoptComicKeys({
  required Map<String, LocalShelfBook> local,
  required Map<String, SyncRecord> remote,
}) {
  final adopted = <String, String>{};
  for (final MapEntry(key: print, value: mine) in local.entries) {
    if (mine.extension != LocalBookSync.comicExtension) continue;
    final prints = {for (final c in mine.chapters) c.fingerprint};
    String? best = remote[print]?.deleted == false ? print : null;
    for (final MapEntry(:key, :value) in remote.entries) {
      if (key == print || value.deleted) continue;
      if (value.data['ext'] != LocalBookSync.comicExtension) continue;
      if (!comicChaptersOf(value.data)
          .any((c) => prints.contains(c.fingerprint))) {
        continue;
      }
      if (best == null || key.compareTo(best) < 0) best = key;
    }
    if (best != null && best != print && !local.containsKey(best)) {
      adopted[print] = best;
    }
  }
  return adopted;
}

/// 照這台書架上的那本（[mine]）上傳或移出。
LocalBookTask _localTask(
  LocalBookAction action,
  String fingerprint,
  LocalShelfBook mine,
) => LocalBookTask(
  action: action,
  fingerprint: fingerprint,
  name: mine.name,
  author: mine.author,
  extension: mine.extension,
  size: mine.size,
  path: mine.path,
  bookUrls: mine.bookUrls,
  chapters: mine.chapters,
);

/// 雲端紀錄裡記著的本地漫畫的每一話（`chapters`：`[[章指紋, 章名], …]`）。
List<ComicSyncChapter> comicChaptersOf(Map<String, Object?> data) {
  final raw = data['chapters'];
  if (raw is! List) return const [];
  return [
    for (final entry in raw)
      if (entry is List &&
          entry.length >= 2 &&
          entry[0] is String &&
          entry[1] is String)
        (fingerprint: entry[0] as String, title: entry[1] as String),
  ];
}

/// 照雲端那筆紀錄（[record]）下載或刪掉雲端的一本。
LocalBookTask _remoteTask(
  LocalBookAction action,
  String fingerprint,
  SyncRecord record,
) {
  final data = record.data;
  String text(String field) =>
      data[field] is String ? data[field] as String : '';
  return LocalBookTask(
    action: action,
    fingerprint: fingerprint,
    name: text('name'),
    author: text('author'),
    extension: text('ext'),
    size: data['size'] is int ? data['size'] as int : 0,
    remoteTime: record.time,
    chapters: comicChaptersOf(data),
  );
}

// 下面幾個在背景 isolate 跑：解析與比對小紀錄、讀寫整個原檔。閉包在頂層
// 函式裡建立，只捕捉參數（CODING_STANDARDS.md）。

Future<LocalBookSyncPlan> _planOn(
  LocalBookWorkRunner run,
  String? content,
  Map<String, LocalShelfBook> local,
  Map<String, SyncBaseEntry> base,
) => run(
  () => planLocalBookSync(
    local: local,
    remote: content == null
        ? const <String, SyncRecord>{}
        : SyncDocument.decode(content).records,
    base: base,
  ),
);

Future<Map<String, String>> _adoptionsOn(
  LocalBookWorkRunner run,
  String? content,
  Map<String, LocalShelfBook> local,
) => content == null
    ? Future.value(const <String, String>{})
    : run(
        () => adoptComicKeys(
          local: local,
          remote: SyncDocument.decode(content).records,
        ),
      );

/// 雲端小紀錄（[content]，還沒有是 null）改了 [fingerprint] 那一筆之後的
/// 整份內容。
Future<String> _putRecordOn(
  LocalBookWorkRunner run,
  String? content,
  String fingerprint,
  SyncRecord record,
) => run(
  () => SyncDocument({
    if (content != null) ...SyncDocument.decode(content).records,
    fingerprint: record,
  }).encode(),
);

/// 讀原檔，TXT 先壓縮。
Future<Uint8List> _packOn(LocalBookWorkRunner run, String path, String ext) =>
    run(() => packLocalBookOriginal(path, ext));

Future<String> _comicFingerprintOn(LocalBookWorkRunner run, String path) =>
    run(() => LocalComicLibrary.fingerprintOf(path));

Future<bool> _unpackOn(
  LocalBookWorkRunner run,
  Uint8List bytes,
  String ext,
  String path,
  String fingerprint,
) => run(() => unpackLocalBookOriginal(bytes, ext, path, fingerprint));

/// 讀 [path] 的原檔準備上傳：TXT 壓縮成 gzip，EPUB 照原樣。
Future<Uint8List> packLocalBookOriginal(String path, String ext) async {
  final bytes = await File(path).readAsBytes();
  return ext == 'txt' ? Uint8List.fromList(gzip.encode(bytes)) : bytes;
}

/// 把下載的原檔寫到 [path]：TXT 先解壓，再核對指紋是 [fingerprint]；對不上
/// （傳到一半斷了、檔被改過）就不寫，傳回 false。
Future<bool> unpackLocalBookOriginal(
  Uint8List bytes,
  String ext,
  String path,
  String fingerprint,
) async {
  final List<int> content;
  try {
    content = ext == 'txt' ? gzip.decode(bytes) : bytes;
  } on FormatException {
    return false;
  }
  final temp = File('$path.part');
  await temp.writeAsBytes(content, flush: true);
  if (await fingerprintOfFile(temp.path) != fingerprint) {
    await temp.delete();
    return false;
  }
  await temp.rename(path);
  return true;
}
