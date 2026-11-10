import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/local_book/local_book_fingerprint.dart';
import 'package:night_reader/core/models/book.dart';

import 'sync_kind.dart';
import 'sync_records.dart';

/// 閱讀進度的同步：書架上一本書一筆，用書名加作者對上另一台的同一本書，
/// 兩台用不同書源也對得上；本地書用原檔指紋對上，檔名不同也對得上。記第幾
/// 章第幾個字，螢幕大小不同也落在同一個字（ADR 0039）。書不在書架上就留在
/// 雲端；閱讀器開著的書由閱讀器自己跳。
class ProgressSync extends SyncKind {
  ProgressSync({
    required this.bookDao,
    required this.chapterDao,
    bool Function(String key)? isOpen,
    this._run = runLocalBookWorkInBackground,
  }) : _isOpen = isOpen ?? _never;

  static const String kind = 'progress';

  final BookDao bookDao;
  final ChapterDao chapterDao;
  final bool Function(String key) _isOpen;

  /// 補算本地書指紋交給誰跑（[fillLocalBookFingerprints]）。
  final LocalBookWorkRunner _run;

  static bool _never(String key) => false;

  @override
  String get name => kind;

  @override
  bool get hasOwnTime => true;

  /// 書從書架移除由書架的同步負責，進度留在雲端。
  @override
  bool get syncsDeletion => false;

  /// 兩台共通的身分：本地書是原檔指紋，其他是書名加作者。還沒算出指紋的
  /// 本地書（原檔不見了）照書名加作者。
  static String keyOf(Book book) => switch (book.fileFingerprint) {
    final print? when book.isLocal => 'local:$print',
    _ => nameKeyOf(book),
  };

  /// 書名加作者；書架同步、書籤與標註都照它認書。
  /// 漫畫、有聲的書名帶類別前綴（`recordName`），和同名的小說是不同的書
  /// （ADR 0053）；小說的鍵照舊。
  static String nameKeyOf(Book book) => '${book.recordName}\t${book.author}';

  @override
  Future<Map<String, SyncRecord>> local() async => {
    for (final entry in (await shelfBooks()).entries)
      entry.key: recordOf(
        entry.value,
        chapterId: chapterIdOf(
          entry.value,
          await _chapterIdsOf(entry.value) ?? const [],
        ),
      ),
  };

  /// 本地漫畫每一話的章指紋（目錄的網址，ADR 0052）；其他書是 null。
  Future<List<String>?> _chapterIdsOf(Book book) async =>
      book.isLocal && book.bookKind == BookSourceKind.comic
      ? [for (final c in await chapterDao.getByBook(book.bookUrl)) c.url]
      : null;

  /// 本地漫畫讀到的那一話的章指紋：兩台的章名、排序可以不同，同一話的
  /// 指紋一樣（ADR 0052）。[ids] 是這本的 [_chapterIdsOf]；其他書是 null。
  static String? chapterIdOf(Book book, List<String> ids) {
    if (!book.isLocal || book.bookKind != BookSourceKind.comic) return null;
    if (ids.isEmpty) return null;
    return ids[book.chapterIndex.clamp(0, ids.length - 1)];
  }

  /// 上次同步的紀錄還是不是這台現在這一本的：書不在書架上、或位置移動的
  /// 時間比上次同步時記的早，就不是。
  ///
  /// 同一本書同步過之後，位置移動的時間不會比紀錄早：上傳時紀錄記的就是
  /// 它，套用雲端時它改成雲端那筆的時間，之後翻頁只會更晚。比紀錄早，是
  /// 這個鍵底下換了一本：移出書架又加回來的新一本（從沒移動過，時間 0），
  /// 或同一本書有兩個書源、最近讀的那本移出了，換成另一本。沿用舊紀錄的話，
  /// 比對會把換上來的這本當成這台改過、雲端沒變，蓋掉雲端留著的進度；
  /// 不沿用就照從沒同步過比時間，雲端的較新就接上。雲端那筆照舊留著，
  /// 給之後加回來的時候用。
  static bool baseHolds(SyncRecord? local, SyncBaseEntry base) =>
      local != null && local.time >= base.time;

  @override
  Future<Map<String, SyncRecord>> reconcile(
    Map<String, SyncRecord> local,
    Map<String, SyncRecord> remote,
    Map<String, SyncBaseEntry> base,
  ) async {
    base.removeWhere((key, entry) => !baseHolds(local[key], entry));
    return local;
  }

  @override
  SyncFingerprint get fingerprint => fingerprintOf;

  @override
  bool canApply(String key, SyncRecord? local) =>
      local != null && !_isOpen(key);

  @override
  Future<Map<String, SyncRecord>> apply(Map<String, SyncRecord> remote) async {
    final books = await shelfBooks();
    final applied = <String, SyncRecord>{};
    for (final MapEntry(:key, value: record) in remote.entries) {
      // 查書架的這段時間剛被打開的，留給閱讀器。閱讀器拿著的本地書可能是
      // 補算指紋之前讀的，用書名加作者登記開著，兩個鍵都看。
      if (record.deleted || _isOpen(key)) continue;
      if (books[key] case final book? when !_isOpen(nameKeyOf(book))) {
        applied[key] = await applyTo(book, record);
      }
    }
    // 書卡的進度線與書架的順序跟著換。
    if (applied.isNotEmpty) AppEventBus().fire(AppEventBus.upBookshelf);
    return applied;
  }

  /// 時間用「位置最後移動的時間」，不用最近閱讀時間：開書沒翻頁也會更新
  /// 後者，拿它比新舊，沒動過的這台會蓋掉別台真的讀過的進度。
  /// [chapterId] 是本地漫畫那一話的章指紋（[chapterIdOf]）。
  static SyncRecord recordOf(Book book, {String? chapterId}) => SyncRecord(
    time: book.progressTime,
    data: {
      'chapterIndex': book.chapterIndex,
      'charOffset': book.charOffset,
      'chapterTitle': book.durChapterTitle ?? '',
      'chapterId': ?chapterId,
    },
  );

  /// 進度的內容是「哪一章（章名）的第幾個字」。章節序號只是這台目錄裡的
  /// 座標：書源在前面插一章、序號跟著變，讀到的地方沒變，不算改過；沒有
  /// 章名時才看序號。
  static String fingerprintOf(SyncRecord record) {
    if (record.deleted) return record.fingerprint;
    // 本地漫畫照章指紋：兩台的章名可以不同。
    final id = record.data['chapterId'];
    if (id is String && id.isNotEmpty) {
      return SyncRecord.fingerprintOf({
        'chapterId': id,
        'charOffset': record.data['charOffset'],
      });
    }
    final title = record.data['chapterTitle'];
    final hasTitle = title is String && title.trim().isNotEmpty;
    return SyncRecord.fingerprintOf({
      if (hasTitle) 'chapterTitle': title.trim(),
      if (!hasTitle) 'chapterIndex': record.data['chapterIndex'],
      'charOffset': record.data['charOffset'],
    });
  }

  /// 書架上每個身分（[keyOf]）最近讀的那一本。同一本書從兩個書源都加進書架
  /// 時，同步只跟著最近讀的那本。還沒有指紋的本地書（這一版以前匯入的）先
  /// 在背景 isolate 補算，進度才照指紋對上。
  Future<Map<String, Book>> shelfBooks() async {
    var shelf = await bookDao.getInBookshelf();
    if (shelf.any((book) => book.isLocal && book.fileFingerprint == null) &&
        await fillLocalBookFingerprints(bookDao, run: _run) > 0) {
      // 補到的書換成有指紋的那份。
      shelf = await bookDao.getInBookshelf();
    }
    final books = <String, Book>{};
    for (final book in shelf) {
      final key = keyOf(book);
      final existing = books[key];
      if (existing == null || book.durChapterTime > existing.durChapterTime) {
        books[key] = book;
      }
    }
    return books;
  }

  /// 把 [remote] 套用到 [book]，傳回套用後這台的紀錄（章節序號照這台的
  /// 目錄對過）。
  Future<SyncRecord> applyTo(Book book, SyncRecord remote) async {
    final position = SyncedProgress.fromRecord(remote);
    final titles = await chapterDao.titlesByBook(book.bookUrl);
    final ids = await _chapterIdsOf(book);
    final index = position.chapterIndexIn(titles, ids: ids);
    final title = titles.isEmpty ? position.chapterTitle : titles[index];
    await bookDao.applySyncedProgress(
      book.bookUrl,
      chapterIndex: index,
      chapterTitle: title,
      charOffset: position.charOffset,
      time: remote.time,
    );
    return SyncRecord(
      time: remote.time,
      data: {
        'chapterIndex': index,
        'charOffset': position.charOffset,
        'chapterTitle': title,
        if (ids != null && ids.isNotEmpty) 'chapterId': ids[index],
      },
    );
  }
}

/// 另一台同步來的一本書的進度。
class SyncedProgress {
  const SyncedProgress({
    required this.chapterIndex,
    required this.charOffset,
    required this.chapterTitle,
    required this.time,
    this.chapterId = '',
  });

  factory SyncedProgress.fromRecord(SyncRecord record) {
    int asInt(Object? value) => value is int && value >= 0 ? value : 0;
    final title = record.data['chapterTitle'];
    final id = record.data['chapterId'];
    return SyncedProgress(
      chapterIndex: asInt(record.data['chapterIndex']),
      charOffset: asInt(record.data['charOffset']),
      chapterTitle: title is String ? title : '',
      chapterId: id is String ? id : '',
      time: record.time,
    );
  }

  /// 本地漫畫那一話的章指紋；其他書是空的。
  final String chapterId;

  final int chapterIndex;
  final int charOffset;
  final String chapterTitle;
  final int time;

  /// 這台目錄（[titles]）裡對應的章節序號。兩台的書源或目錄版本不同時，
  /// 同一個序號可能是不同章：先找同名的章（離原序號最近的那個），找不到才
  /// 照序號，超出目錄就停在最後一章。
  ///
  /// 本地漫畫給了這台每一話的章指紋（[ids]）時先照章指紋找。
  int chapterIndexIn(List<String> titles, {List<String>? ids}) {
    if (chapterId.isNotEmpty && ids != null) {
      final byId = ids.indexOf(chapterId);
      if (byId >= 0) return byId;
    }
    if (titles.isEmpty) return chapterIndex;
    final wanted = chapterTitle.trim();
    if (wanted.isNotEmpty) {
      if (chapterIndex < titles.length &&
          titles[chapterIndex].trim() == wanted) {
        return chapterIndex;
      }
      int? best;
      for (var i = 0; i < titles.length; i++) {
        if (titles[i].trim() != wanted) continue;
        if (best == null ||
            (i - chapterIndex).abs() < (best - chapterIndex).abs()) {
          best = i;
        }
      }
      if (best != null) return best;
    }
    return chapterIndex.clamp(0, titles.length - 1);
  }
}
