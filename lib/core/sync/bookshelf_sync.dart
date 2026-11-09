import 'dart:async';
import 'dart:convert';

import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/book_storage_service.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'progress_sync.dart';
import 'sync_kind.dart';
import 'sync_records.dart';

/// 書架的同步：書架上一本書一筆，用書名加作者對上（同閱讀進度，ADR 0039）。
/// 另一台加進書架的書，這台照它的書源加進來並整本下載（ADR 0008）；另一台
/// 移出書架的，這台也移出。兩台各自用哪個書源讀不同步，各讀各的；同步的
/// 是使用者自己改的封面、簡介、分類、要不要檢查更新與這本書的閱讀設定。
///
/// 改書名或作者就換了鍵，從這台看是「舊的那筆刪了、新的那筆加了」。同一個
/// 書的網址在兩次同步之間換了鍵就是改名（不論是「編輯資訊」還是書源更新
/// 了書名），記在 [BookRenames]，跟著新那筆送上去（`renamedFrom`）；另一台
/// 收到「舊鍵刪除＋新鍵帶著 `renamedFrom`」就把舊鍵的書原地改名，下載好的
/// 正文、目錄、封面留著，不是移出書架再重新加回來。
///
/// 本地書不在這裡同步：進度照原檔指紋走閱讀進度，書本身由使用者按「同步
/// 本地書」才上傳下載（`LocalBookSync`，ADR 0039）。
class BookshelfSync extends SyncKind {
  BookshelfSync({
    BookDao? bookDao,
    this._storage,
    bool Function(String key)? isOpen,
    void Function(String bookUrl)? download,
    BookRenames? renames,
    ReadRecordDao? readRecords,
  }) : _bookDao = bookDao ?? getIt<BookDao>(),
       _renamesStore = renames,
       _readRecords =
           readRecords ??
           (getIt.isRegistered<ReadRecordDao>()
               ? getIt<ReadRecordDao>()
               : null),
       _isOpen = isOpen ?? _never,
       _download = download ?? _keepDownloaded;

  final BookDao _bookDao;
  final BookStorageService? _storage;
  final BookRenames? _renamesStore;

  /// 閱讀統計照書名記，改名時一起搬（同書籍詳情的「編輯資訊」）。
  final ReadRecordDao? _readRecords;
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

  static SyncRecord recordOf(Book book, {List<String>? renamedFrom}) {
    final json = book.toJson();
    return SyncRecord(
      time: 0,
      data: {
        for (final field in [..._addFields, ..._userFields]) field: json[field],
        if (renamedFrom != null && renamedFrom.isNotEmpty)
          'renamedFrom': renamedFrom,
      },
    );
  }

  Future<BookRenames> _renames() async =>
      _renamesStore ?? BookRenames(await SharedPreferences.getInstance());

  /// 內容算使用者改的欄位與這台用的書源（網址）。書源算進去，雲端那筆才會
  /// 跟著最近換源、或書源改了網址的那台，之後新加入的手機照它加書拿到
  /// 用得了的書源；套用時仍只寫使用者改的欄位，不動這台的書源。
  @override
  SyncFingerprint get fingerprint => _fingerprintOf;

  static String _fingerprintOf(SyncRecord record) {
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
    final localBooks = <String, List<Book>>{};
    for (final book in await _bookDao.getInBookshelf()) {
      if (book.isLocal) {
        (localBooks[ProgressSync.nameKeyOf(book)] ??= []).add(book);
        continue;
      }
      (shelf[ProgressSync.keyOf(book)] ??= []).add(book);
    }
    _localBooks = localBooks;
    return shelf;
  }

  /// 這台書架上的本地書，照書名加作者（[_shelf] 最近一次讀到的）。
  Map<String, List<Book>> _localBooks = const {};

  static Book _latest(List<Book> books) =>
      books.reduce((a, b) => b.durChapterTime > a.durChapterTime ? b : a);

  @override
  Future<Map<String, SyncRecord>> local() async {
    final shelf = await _shelf();
    final names = await _renames();
    await names.observe({
      for (final entry in shelf.entries)
        for (final book in entry.value) book.bookUrl: entry.key,
    });
    final renames = names.read();
    return {
      for (final entry in shelf.entries)
        entry.key: recordOf(
          _latest(entry.value),
          renamedFrom: renames[entry.key],
        ),
    };
  }

  /// 這一輪讀到的整份雲端紀錄。舊鍵的刪除紀錄正開著的書不套用（[canApply]），
  /// 不會出現在 [apply] 拿到的那批裡，改名要看整份才知道舊鍵是不是被刪了。
  Map<String, SyncRecord> _cloud = const {};

  @override
  Future<Map<String, SyncRecord>> reconcile(
    Map<String, SyncRecord> local,
    Map<String, SyncRecord> remote,
    Map<String, SyncBaseEntry> base,
  ) async {
    _cloud = remote;
    // 舊版把本地書也送進了書架同步，上次同步的紀錄還記著它。這台不再送
    // 本地書，照常比的話會被當成移出書架、送出刪除紀錄，刪掉另一台同名同
    // 作者的網路書。這種紀錄作廢，照這台從沒同步過這一筆合併：雲端那筆是
    // 本地書的舊紀錄，或上次同步時這台送的就是書架上那本本地書。
    for (final key in [...base.keys]) {
      if (local.containsKey(key)) continue;
      final cloud = remote[key];
      final sentLocalBook = (_localBooks[key] ?? const <Book>[]).any(
        (book) => _fingerprintOf(recordOf(book)) == base[key]!.local,
      );
      if (sentLocalBook || (cloud != null && _isLocalRecord(cloud))) {
        base.remove(key);
      }
    }
    return local;
  }

  /// 舊版把本地書（帶著那台手機上的路徑）也送進了書架同步，另一台加進來是
  /// 打不開的書。本地書由「同步本地書」處理，書架同步不加、也不刪它們。
  static bool _isLocalRecord(SyncRecord record) =>
      !record.deleted && Book(origin: '${record.data['origin'] ?? ''}').isLocal;

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
    // 先處理改名，下面才不會把舊鍵的書當成「移出書架」刪掉。
    final deferred = await _applyRenames(remote, shelf);
    for (final MapEntry(:key, value: record) in remote.entries) {
      if (_isOpen(key) || deferred.contains(key) || _isLocalRecord(record)) {
        continue;
      }
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
        // 另一台把這本書改過名：跟著用新名字，鍵才和雲端這筆對得上。
        if (ProgressSync.keyOf(existing) != key &&
            ProgressSync.keyOf(incoming) == key &&
            !existing.isInBookshelf) {
          await _bookDao.renameBook(
            existing.bookUrl,
            name: incoming.name,
            author: incoming.author,
            type: incoming.type,
          );
          existing
            ..name = incoming.name
            ..author = incoming.author
            ..type = incoming.type;
        }
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
    // 沒有套用任何一本就不通知：書架與開著的頁面不必為了沒變的資料重讀。
    if (applied.isNotEmpty) AppEventBus().fire(AppEventBus.upBookshelf);
    added.forEach(_download);
    return applied;
  }

  /// 另一台改了書名或作者：雲端這批裡，舊鍵被刪、新鍵帶著 `renamedFrom` 指向
  /// 舊鍵，而這台的舊鍵底下有書，就把那些書原地改成新名字（[shelf] 跟著
  /// 換）。兩個條件都要，只有 `renamedFrom` 可能是很久以前的紀錄，那時的舊
  /// 名字現在是這台使用者另外加的書。
  ///
  /// 傳回這次不能動的鍵：舊鍵或新鍵的書正開在閱讀器裡時，舊鍵的刪除與
  /// 新鍵那筆都留到下次，不然其中一筆先被套用，舊名字的書就被刪掉了。
  Future<Set<String>> _applyRenames(
    Map<String, SyncRecord> remote,
    Map<String, List<Book>> shelf,
  ) async {
    final deferred = <String>{};
    // 新鍵的書正開著時，新鍵那筆不在 [remote] 裡（[canApply]），只看
    // [remote] 就認不出舊鍵的刪除其實是改名：開著的那幾筆從整份雲端紀錄補。
    final candidates = {
      for (final MapEntry(:key, :value) in _cloud.entries)
        if (_isOpen(key)) key: value,
      ...remote,
    };
    for (final MapEntry(:key, value: record) in candidates.entries) {
      if (record.deleted) continue;
      final incoming = Book.fromJson(Map<String, dynamic>.of(record.data));
      if (ProgressSync.keyOf(incoming) != key) continue;
      final previous = [
        for (final old in record.data['renamedFrom'] as List? ?? const [])
          if (old is String && old != key) old,
      ];
      // 最近一次改名的舊鍵在前面找。
      for (final old in previous.reversed) {
        if ((remote[old] ?? _cloud[old])?.deleted != true) continue;
        final books = shelf[old];
        if (books == null || books.isEmpty) continue;
        if (_isOpen(old) || _isOpen(key)) {
          // 舊鍵的刪除也一起留著：只有新鍵開著時，舊鍵那筆照樣會被套用，
          // 舊名字的書就被當成移出書架刪掉了。
          deferred.addAll([key, old]);
          break;
        }
        // 另一台的書源改了類型，書跟著換類別也是換鍵（ADR 0053）：類別
        // 一起寫，統計留在原本那一類，不搬。
        final fromKind = books.first.bookKind;
        final fromName = books.first.recordName;
        for (final book in books) {
          await _bookDao.renameBook(
            book.bookUrl,
            name: incoming.name,
            author: incoming.author,
            type: incoming.type,
          );
          book
            ..name = incoming.name
            ..author = incoming.author
            ..type = incoming.type;
        }
        (shelf[key] ??= []).addAll(books);
        shelf.remove(old);
        if (fromKind == incoming.bookKind && fromName != incoming.recordName) {
          try {
            await _readRecords?.renameBook(
              from: fromName,
              to: incoming.recordName,
            );
          } catch (error, stackTrace) {
            AppLog.e('同步改書名時搬閱讀統計失敗', error: error, stackTrace: stackTrace);
          }
        }
        // 照另一台記的換成同一份，兩台送上去的內容才一樣；這台的書換了鍵也
        // 記下，下次同步不會當成這台自己又改了名。
        final names = await _renames();
        await names.set(key, previous);
        await names.adopt({for (final book in books) book.bookUrl: key});
        break;
      }
    }
    return deferred;
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

/// 書改過名的紀錄：現在的鍵（書名加作者）→ 以前用過的鍵（舊的在前）。
/// 同步時跟著新鍵那筆送給別台。
///
/// 改名從書架上每本書的鍵看出來：[observe] 記著上次同步時每個書網址對應的
/// 鍵，同一個網址的鍵變了就是改名。
class BookRenames {
  /// [namespace] 是存在偏好設定裡的名字前綴；一個 App 只有一份，測試裡用
  /// 來模擬兩台手機。
  BookRenames(this._prefs, {String namespace = 'sync'})
    : _key = '$namespace.book_renames',
      _shelfKey = '$namespace.shelf_keys';

  final String _key;
  final String _shelfKey;

  final SharedPreferences _prefs;

  Map<String, List<String>> read() {
    final json = _json(_key);
    return {
      for (final MapEntry(:key, :value) in json.entries)
        if (value is List) key: [for (final old in value) '$old'],
    };
  }

  Map<String, Object?> _json(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return {};
    try {
      final json = jsonDecode(raw);
      return json is Map
          ? {for (final e in json.entries) '${e.key}': e.value}
          : {};
    } on FormatException {
      return {};
    }
  }

  /// 書架上現在每個書網址對應的鍵 [keys]：和上次記的比，網址一樣、鍵不同
  /// 的就是改了名，把「舊鍵 → 新鍵」記下來。
  Future<void> observe(Map<String, String> keys) async {
    final last = _json(_shelfKey);
    final renames = read();
    var renamed = false;
    for (final MapEntry(:key, value: now) in keys.entries) {
      final before = last[key];
      if (before is! String || before == now) continue;
      _record(renames, from: before, to: now);
      renamed = true;
    }
    if (renamed) await _write(_key, renames);
    if (last.length != keys.length ||
        keys.entries.any((entry) => last[entry.key] != entry.value)) {
      await _write(_shelfKey, keys);
    }
  }

  /// 這幾本書（網址 → 鍵）已經是這個鍵了，不用再當成改名。
  Future<void> adopt(Map<String, String> keys) =>
      _write(_shelfKey, {..._json(_shelfKey), ...keys});

  /// 照另一台記的換成同一份，兩台送上去的內容才一樣。
  Future<void> set(String key, List<String> renamedFrom) =>
      _write(_key, read()..[key] = renamedFrom);

  /// [from] 改成 [to]：[from] 以前的鍵也一起記到 [to] 底下。
  static void _record(
    Map<String, List<String>> renames, {
    required String from,
    required String to,
  }) {
    final history = [...?renames.remove(from), from]..remove(to);
    renames[to] = history.toSet().toList();
  }

  Future<void> _write(String key, Map<String, Object?> value) =>
      _prefs.setString(key, jsonEncode(value));
}
