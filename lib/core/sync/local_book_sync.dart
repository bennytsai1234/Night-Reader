import 'dart:io';
import 'dart:typed_data';

import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/local_book/local_book_fingerprint.dart';
import 'package:night_reader/core/local_book/local_book_formats.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/book_storage_service.dart';
import 'package:night_reader/core/services/local_book_service.dart';

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
  });

  final LocalBookAction action;
  final String fingerprint;
  final String name;
  final String author;

  /// 原檔的副檔名（不含點）：`txt` 或 `epub`。
  final String extension;

  /// 原檔的大小（位元組）。
  final int size;

  /// 上傳：這台原檔的路徑。
  final String? path;

  /// 移出書架：這台指著這個原檔的書。
  final List<String> bookUrls;

  /// 下載：雲端那筆紀錄的時間，記進上次同步的紀錄。
  final int remoteTime;
}

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

  /// 上次同步時兩邊都有的書，上次同步的紀錄裡記的內容（只看有沒有）。
  static const String _present = 'present';

  /// 算出要做的事，還不動手。這一版以前匯入、還沒有指紋的本地書先在背景
  /// isolate 補算。
  Future<LocalBookSyncPlan> plan() async {
    await fillLocalBookFingerprints(_bookDao, run: _run);
    final local = await _shelf();
    final file = await _store.read(fileName);
    final remote = file == null
        ? const <String, SyncRecord>{}
        : SyncDocument.decode(file.content).records;
    return planLocalBookSync(
      local: local,
      remote: remote,
      base: await _bases.read(kind),
    );
  }

  /// 書架上每個原檔指紋的本地書。原檔大小這時才量；原檔不見了算 0，上傳時
  /// 再報失敗。
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
      final file = File(path);
      shelf[print] = LocalShelfBook(
        name: book.name,
        author: book.author,
        extension: localBookExtensionFromPath(path),
        size: await file.exists() ? await file.length() : 0,
        addedTime: book.syncTime,
        path: path,
        bookUrls: [book.bookUrl],
      );
    }
    return shelf;
  }

  /// 照 [plan] 做，一次一本。[cancelled] 在兩本之間看，傳回 true 就停下；
  /// 已經做完的留著。整個同步空間用不了（連不上、授權失效）時剩下的不再
  /// 試，其他失敗記下原因、接著做下一本。
  Future<LocalBookSyncResult> run(
    LocalBookSyncPlan plan, {
    void Function(LocalBookSyncProgress progress)? onProgress,
    bool Function()? cancelled,
  }) async {
    final base = {...await _bases.read(kind), ...plan.settled};
    await _bases.write(kind, base);
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
            base[task.fingerprint] = _entry(await _upload(task));
          case LocalBookAction.download:
            await _download(task);
            shelfChanged = true;
            base[task.fingerprint] = _entry(task.remoteTime);
          case LocalBookAction.removeHere:
            await _removeHere(task);
            shelfChanged = true;
            base.remove(task.fingerprint);
          case LocalBookAction.deleteRemote:
            await _deleteRemote(task);
            base.remove(task.fingerprint);
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

  static SyncBaseEntry _entry(int time) =>
      SyncBaseEntry(local: _present, remote: _present, time: time);

  /// 上傳原檔與小紀錄，傳回小紀錄的時間。
  Future<int> _upload(LocalBookTask task) async {
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
    final bytes = await _store.readBytes(
      originalName(task.fingerprint, task.extension),
    );
    if (bytes == null) {
      throw const LocalBookSyncException('雲端找不到這本的原檔，請在另一台再按一次「同步本地書」');
    }
    final path = await LocalBookService.freeLibraryPath(
      task.name,
      '.${task.extension}',
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
    await _store.delete(originalName(task.fingerprint, task.extension));
    await _putRecord(
      task.fingerprint,
      SyncRecord(
        time: _clock().millisecondsSinceEpoch,
        data: const {},
        deleted: true,
      ),
    );
  }

  /// 改雲端小紀錄裡的一筆：讀、改、寫回；被別台搶先就重讀再改。試到最後
  /// 一次仍被搶先就不比版本直接寫，同其他種類的同步。
  Future<void> _putRecord(String fingerprint, SyncRecord record) async {
    for (var attempt = 1; ; attempt++) {
      final file = await _store.read(fileName);
      final records = file == null
          ? <String, SyncRecord>{}
          : Map.of(SyncDocument.decode(file.content).records);
      records[fingerprint] = record;
      final lastTry = attempt >= _maxAttempts;
      try {
        await _store.write(
          fileName,
          SyncDocument(records).encode(),
          ifVersion: lastTry ? null : file?.version,
          ifAbsent: !lastTry && file == null,
        );
        return;
      } on SyncConflict {
        continue;
      }
    }
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
  });

  final String name;
  final String author;
  final String extension;
  final int size;

  /// 加進書架的時間；和雲端的刪除紀錄比新舊用。
  final int addedTime;
  final String path;
  final List<String> bookUrls;

  LocalShelfBook withBook(String bookUrl) => LocalShelfBook(
    name: name,
    author: author,
    extension: extension,
    size: size,
    addedTime: addedTime,
    path: path,
    bookUrls: [...bookUrls, bookUrl],
  );
}

/// 每個原檔指紋，這台（[local]）、雲端（[remote]）與上次同步時（[base]）
/// 比出要做的事。純計算。
///
/// - 兩邊都有：不用做事，記成同步過。
/// - 只有這台有：雲端從沒有過就上傳；雲端記著刪除時，上次同步過（之後
///   另一台移出了）或刪除比這台加進書架晚，這台跟著移出，否則這台是之後才
///   重新加的，再上傳。
/// - 只有雲端有：上次同步時兩邊都有、雲端那筆之後沒變，是這台移出了，刪掉
///   雲端的；否則下載。
LocalBookSyncPlan planLocalBookSync({
  required Map<String, LocalShelfBook> local,
  required Map<String, SyncRecord> remote,
  required Map<String, SyncBaseEntry> base,
}) {
  final tasks = <LocalBookTask>[];
  final settled = <String, SyncBaseEntry>{};
  for (final print in {...local.keys, ...remote.keys}) {
    final mine = local[print];
    final theirs = remote[print];
    final last = base[print];
    final alive = theirs != null && !theirs.deleted;
    if (mine != null) {
      if (alive) {
        settled[print] = LocalBookSync._entry(theirs.time);
        continue;
      }
      final removedThere =
          theirs != null && (last != null || theirs.time >= mine.addedTime);
      tasks.add(
        LocalBookTask(
          action: removedThere
              ? LocalBookAction.removeHere
              : LocalBookAction.upload,
          fingerprint: print,
          name: mine.name,
          author: mine.author,
          extension: mine.extension,
          size: mine.size,
          path: mine.path,
          bookUrls: mine.bookUrls,
        ),
      );
      continue;
    }
    if (!alive) continue;
    final data = theirs.data;
    String text(String field) =>
        data[field] is String ? data[field] as String : '';
    final extension = text('ext');
    if (!isSupportedLocalBookExtension(extension)) continue;
    final size = data['size'] is int ? data['size'] as int : 0;
    tasks.add(
      LocalBookTask(
        action: last != null && last.time == theirs.time
            ? LocalBookAction.deleteRemote
            : LocalBookAction.download,
        fingerprint: print,
        name: text('name'),
        author: text('author'),
        extension: extension,
        size: size,
        remoteTime: theirs.time,
      ),
    );
  }
  // 先做這台書架上的事（快），再傳檔；同一種裡照書名排，進度框看得出順序。
  tasks.sort((a, b) {
    final order = a.action.index.compareTo(b.action.index);
    return order != 0 ? order : a.name.compareTo(b.name);
  });
  return LocalBookSyncPlan(tasks: tasks, settled: settled);
}

// 下面兩個在背景 isolate 讀寫整個原檔。閉包在頂層函式裡建立，只捕捉參數
// （CODING_STANDARDS.md）。

/// 讀原檔，TXT 先壓縮。
Future<Uint8List> _packOn(LocalBookWorkRunner run, String path, String ext) =>
    run(() => packLocalBookOriginal(path, ext));

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
