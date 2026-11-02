import 'dart:async';

import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/book_storage_service.dart';
import 'package:night_reader/core/services/download_service.dart';

import 'progress_sync.dart';
import 'sync_kind.dart';
import 'sync_records.dart';

/// 書架的同步：書架上一本書一筆，用書名加作者對上（同閱讀進度，ADR 0039）。
/// 另一台加進書架的書，這台照它的書源加進來並整本下載（ADR 0008）；另一台
/// 移出書架的，這台也移出。兩台各自用哪個書源讀不同步，各讀各的；同步的
/// 是使用者自己改的封面、簡介、分類、要不要檢查更新與這本書的閱讀設定。
///
/// 本地書的身分是這台手機上的檔案路徑，另一台對不上，先不同步（#193）。
class BookshelfSync extends SyncKind {
  BookshelfSync({
    BookDao? bookDao,
    this._storage,
    bool Function(String key)? isOpen,
    void Function(String bookUrl)? download,
  }) : _bookDao = bookDao ?? getIt<BookDao>(),
       _isOpen = isOpen ?? _never,
       _download = download ?? _keepDownloaded;

  final BookDao _bookDao;
  final BookStorageService? _storage;
  final bool Function(String key) _isOpen;
  final void Function(String bookUrl) _download;

  static bool _never(String key) => false;

  static void _keepDownloaded(String bookUrl) {
    if (!getIt.isRegistered<DownloadDao>()) return;
    unawaited(DownloadService().keepShelfBookDownloaded(bookUrl));
  }

  /// 這台沒有這本書時，照另一台的樣子加進來要用的。
  static const List<String> _addFields = [
    'bookUrl',
    'tocUrl',
    'origin',
    'originName',
    'name',
    'author',
    'kind',
    'coverUrl',
    'intro',
    'type',
    'latestChapterTitle',
    'latestChapterTime',
    'totalChapterNum',
    'wordCount',
    'variable',
    'syncTime',
  ];

  /// 使用者自己改的，套用時只寫這些。
  static const List<String> _userFields = [
    'customTag',
    'customCoverUrl',
    'customIntro',
    'canUpdate',
    'readConfig',
  ];

  @override
  String get name => 'bookshelf';

  static SyncRecord recordOf(Book book) {
    final json = book.toJson();
    return SyncRecord(
      time: 0,
      data: {
        for (final field in [..._addFields, ..._userFields]) field: json[field],
      },
    );
  }

  /// 內容算使用者改的欄位與這台用的書源（網址）。書源算進去，雲端那筆才會
  /// 跟著最近換源、或書源改了網址的那台，之後新加入的手機照它加書拿到
  /// 用得了的書源；套用時仍只寫使用者改的欄位，不動這台的書源。
  @override
  String fingerprint(SyncRecord record) {
    if (record.deleted) return record.fingerprint;
    return SyncRecord.fingerprintOf({
      for (final field in [..._userFields, 'bookUrl', 'origin'])
        field: record.data[field],
    });
  }

  /// 書架上每個書名加作者最近讀的那一本（同一本書從兩個書源都加進書架時，
  /// 跟著最近讀的那本），不含本地書。
  Future<Map<String, List<Book>>> _shelf() async {
    final shelf = <String, List<Book>>{};
    for (final book in await _bookDao.getInBookshelf()) {
      if (book.isLocal) continue;
      (shelf[ProgressSync.keyOf(book)] ??= []).add(book);
    }
    return shelf;
  }

  static Book _latest(List<Book> books) =>
      books.reduce((a, b) => b.durChapterTime > a.durChapterTime ? b : a);

  @override
  Future<Map<String, SyncRecord>> local() async => {
    for (final entry in (await _shelf()).entries)
      entry.key: recordOf(_latest(entry.value)),
  };

  /// 閱讀器開著的書不在背景改，下次同步再比。
  @override
  bool canApply(String key, SyncRecord? local) => !_isOpen(key);

  /// 每一本動手之前再看一次是不是開著：查書架的這段時間可能剛被打開。
  /// 傳回這次寫進去的樣子，不重讀：寫完才又改的，下次同步比得出來。
  @override
  Future<Map<String, SyncRecord>> apply(Map<String, SyncRecord> remote) async {
    final shelf = await _shelf();
    final added = <String>[];
    final applied = <String, SyncRecord>{};
    for (final MapEntry(:key, value: record) in remote.entries) {
      if (_isOpen(key)) continue;
      final books = shelf[key] ?? const <Book>[];
      if (record.deleted) {
        final storage = _storage ?? BookStorageService();
        for (final book in books) {
          await storage.discardBook(book);
        }
        applied[key] = record;
        continue;
      }
      final incoming = Book.fromJson(Map<String, dynamic>.of(record.data));
      if (books.isNotEmpty) {
        for (final book in books) {
          await _writeUserFields(from: incoming, to: book);
        }
        applied[key] = recordOf(_latest(books));
        continue;
      }
      if (incoming.bookUrl.isEmpty) continue;
      // 這台曾經看過、沒加進書架的同一本（同一個網址）：留著它的目錄與進度。
      final existing = await _bookDao.getByUrl(incoming.bookUrl);
      if (existing != null) {
        await _writeUserFields(from: incoming, to: existing);
        await _bookDao.updateInBookshelf(existing.bookUrl, true);
        existing.isInBookshelf = true;
        applied[key] = recordOf(existing);
      } else {
        if (incoming.syncTime == 0) {
          incoming.syncTime = DateTime.now().millisecondsSinceEpoch;
        }
        incoming.isInBookshelf = true;
        await _bookDao.upsert(incoming);
        applied[key] = recordOf(incoming);
      }
      added.add(incoming.bookUrl);
    }
    AppEventBus().fire(AppEventBus.upBookshelf);
    added.forEach(_download);
    return applied;
  }

  /// 只寫使用者改的欄位，[to] 也跟著改成寫進去的樣子。
  Future<void> _writeUserFields({required Book from, required Book to}) async {
    // 換了封面網址，存在這台的封面檔就不是它了（同書籍詳情換封面）。
    final coverChanged = to.customCoverUrl != from.customCoverUrl;
    await _bookDao.updateUserFields(
      to.bookUrl,
      customTag: from.customTag,
      customCoverUrl: from.customCoverUrl,
      customIntro: from.customIntro,
      canUpdate: from.canUpdate,
      readConfig: from.readConfig,
      coverChanged: coverChanged,
    );
    if (coverChanged) to.customCoverLocalPath = null;
    to
      ..customTag = from.customTag
      ..customCoverUrl = from.customCoverUrl
      ..customIntro = from.customIntro
      ..canUpdate = from.canUpdate
      ..readConfig = from.readConfig;
  }
}
