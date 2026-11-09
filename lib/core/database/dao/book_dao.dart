import 'package:drift/drift.dart';

import '../../models/book.dart';
import '../../models/book_group.dart';
import '../../models/source/book_source_logic.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'book_dao.g.dart';

@DriftAccessor(tables: [Books])
class BookDao extends DatabaseAccessor<AppDatabase> with _$BookDaoMixin {
  BookDao(super.db);

  AppDatabase get appDatabase => attachedDatabase;

  Future<List<Book>> getAll() => select(books).get();

  Stream<List<Book>> watchInBookshelf() {
    return (select(books)
          ..where((t) => t.isInBookshelf.equals(true))
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.durChapterTime,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch();
  }

  Future<List<Book>> getInBookshelf() {
    return (select(books)
          ..where((t) => t.isInBookshelf.equals(true))
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.durChapterTime,
              mode: OrderingMode.desc,
            ),
          ]))
        .get();
  }

  /// 記錄裡的書名（閱讀統計、書籤、標註的 `bookName`，帶類別前綴，
  /// ADR 0053）對到的書：書名相同、類別也相同。點紀錄時用它找回那本書。
  Future<List<Book>> getByRecordName(String recordName) async {
    final (:kind, :name) = BookSourceKind.splitRecordName(recordName);
    final rows = await (select(books)..where((t) => t.name.equals(name))).get();
    return [
      for (final book in rows)
        if (book.bookKind == kind) book,
    ];
  }

  Future<Book?> getByUrl(String url) {
    return (select(
      books,
    )..where((t) => t.bookUrl.equals(url))).getSingleOrNull();
  }

  /// 書源是 [origin] 的書（書架上的與還沒加入的都算）。
  Future<List<String>> bookUrlsFromOrigin(String origin) {
    final query = selectOnly(books)
      ..addColumns([books.bookUrl])
      ..where(books.origin.equals(origin));
    return query.map((row) => row.read(books.bookUrl)!).get();
  }

  /// 書源換了網址（[from] → [to]）：這些書改指新網址，書源名稱一起換成
  /// [toName]。
  Future<void> moveOrigin(String from, String to, {required String toName}) {
    return (update(books)..where((t) => t.origin.equals(from))).write(
      BooksCompanion(origin: Value(to), originName: Value(toName)),
    );
  }

  Future<void> upsert(Book book) =>
      into(books).insertOnConflictUpdate(_row(book));

  Future<void> upsertAll(List<Book> bookList) async {
    await batch(
      (b) => b.insertAllOnConflictUpdate(books, bookList.map(_row).toList()),
    );
  }

  /// 整本寫回時不清掉已經算好的原檔指紋：手上的書可能是背景補算指紋之前
  /// 讀出來的（[updateFileFingerprint]）。
  static Insertable<Book> _row(Book book) {
    final row = BookToInsertable(book).toInsertable();
    return book.fileFingerprint == null ? _KeepFingerprint(row) : row;
  }

  Future<void> deleteByUrl(String url) {
    return (delete(books)..where((t) => t.bookUrl.equals(url))).go();
  }

  Future<List<Book>> getInGroup(int groupId) {
    if (groupId == BookGroup.idAll) return getInBookshelf();
    if (groupId == 0) {
      return (select(
        books,
      )..where((t) => t.isInBookshelf.equals(true) & t.group.equals(0))).get();
    }
    return (select(books)..where(
          (t) =>
              t.isInBookshelf.equals(true) &
              t.group
                  .bitwiseAnd(Variable<int>(groupId))
                  .isBiggerThan(const Constant(0)),
        ))
        .get();
  }

  /// 存閱讀器的位置；最近閱讀時間一律更新（書架照它排）。位置真的移動了
  /// （換了章名或字的位置）才更新 [Book.progressTime] 並傳回它，否則傳回
  /// null：開書沒翻頁、目錄重新編號只改了章節序號，都不算移動。
  Future<int?> updateProgress(
    String bookUrl,
    int chapterIndex,
    String chapterTitle,
    int pos, {
    double visualOffsetPx = 0.0,
    String? readerAnchorJson,
  }) {
    return transaction(() async {
      final current = await getByUrl(bookUrl);
      final now = DateTime.now().millisecondsSinceEpoch;
      final moved =
          current != null &&
          (current.charOffset != pos ||
              (current.durChapterTitle ?? '') != chapterTitle);
      await (update(books)..where((t) => t.bookUrl.equals(bookUrl))).write(
        BooksCompanion(
          chapterIndex: Value(chapterIndex),
          durChapterTitle: Value(chapterTitle),
          charOffset: Value(pos),
          visualOffsetPx: Value(_normalizeVisualOffsetPx(visualOffsetPx)),
          readerAnchorJson: Value(readerAnchorJson),
          durChapterTime: Value(now),
          progressTime: moved ? Value(now) : const Value.absent(),
        ),
      );
      return moved ? now : null;
    });
  }

  /// 套用另一台同步來的進度（ADR 0039）：位置換成那一台的，畫面上的細微
  /// 位移與錨點是那台螢幕的，清掉；位置移動的時間記成那一台的。最近閱讀
  /// 時間取兩台較晚的，書架排序不會因為同步往後掉。
  Future<void> applySyncedProgress(
    String bookUrl, {
    required int chapterIndex,
    required String chapterTitle,
    required int charOffset,
    required int time,
  }) {
    return transaction(() async {
      final current = await (select(
        books,
      )..where((t) => t.bookUrl.equals(bookUrl))).getSingleOrNull();
      if (current == null) return;
      await (update(books)..where((t) => t.bookUrl.equals(bookUrl))).write(
        BooksCompanion(
          chapterIndex: Value(chapterIndex),
          durChapterTitle: Value(chapterTitle),
          charOffset: Value(charOffset),
          visualOffsetPx: const Value(0.0),
          readerAnchorJson: const Value(null),
          durChapterTime: Value(
            time > current.durChapterTime ? time : current.durChapterTime,
          ),
          progressTime: Value(time),
        ),
      );
    });
  }

  /// 只改「是否參與書架更新」；其他欄位（閱讀進度等）不跟著被舊資料覆寫。
  /// 同步來的、使用者自己改的欄位（ADR 0039）：只寫這幾欄，同一時間寫的進度、
  /// 換源結果不會被蓋掉。封面網址換了，存在這台的封面檔一起清掉。
  Future<void> updateUserFields(
    String bookUrl, {
    required String? customTag,
    required String? customCoverUrl,
    required String? customIntro,
    required bool canUpdate,
    required ReadConfig? readConfig,
    required bool coverChanged,
  }) {
    return (update(books)..where((t) => t.bookUrl.equals(bookUrl))).write(
      BooksCompanion(
        customTag: Value(customTag),
        customCoverUrl: Value(customCoverUrl),
        customCoverLocalPath: coverChanged
            ? const Value(null)
            : const Value.absent(),
        customIntro: Value(customIntro),
        canUpdate: Value(canUpdate),
        readConfig: Value(readConfig),
      ),
    );
  }

  /// 只改書名、作者與類別（另一台改了名或換了類別，同步照著改，ADR 0039、
  /// 0053）：書的網址、目錄、正文、閱讀進度都不動。
  Future<void> renameBook(
    String bookUrl, {
    required String name,
    required String author,
    int? type,
  }) {
    return (update(books)..where((t) => t.bookUrl.equals(bookUrl))).write(
      BooksCompanion(
        name: Value(name),
        author: Value(author),
        type: type == null ? const Value.absent() : Value(type),
      ),
    );
  }

  /// 書源的類型改了（校驗、手動、同步或重新匯入），目前用它的書跟著換類別
  /// （ADR 0053）。只改類別不同的；閱讀進度、書籤與閱讀統計留在原本那一類。
  /// 傳回改了幾本。
  Future<int> followSourceKinds(Map<String, BookSourceKind> kinds) async {
    if (kinds.isEmpty) return 0;
    final query = selectOnly(books)
      ..addColumns([books.bookUrl, books.origin, books.type]);
    // 一次存幾千個書源（匯入、同步）時整張書表掃一遍，比把網址全塞進條件快。
    if (kinds.length <= 500) query.where(books.origin.isIn(kinds.keys));
    final rows = await query.get();
    final changed = <String, int>{};
    for (final row in rows) {
      final kind = kinds[row.read(books.origin)];
      final type = row.read(books.type) ?? 0;
      if (kind == null || BookSourceKind.ofBookType(type) == kind) continue;
      changed[row.read(books.bookUrl)!] = kind.bookType;
    }
    if (changed.isEmpty) return 0;
    await batch((b) {
      for (final MapEntry(key: bookUrl, value: type) in changed.entries) {
        b.update(
          books,
          BooksCompanion(type: Value(type)),
          where: (t) => t.bookUrl.equals(bookUrl),
        );
      }
    });
    return changed.length;
  }

  /// 記下本地書原檔的指紋（[Book.fileFingerprint]）。
  Future<void> updateFileFingerprint(String bookUrl, String fingerprint) {
    return (update(books)..where((t) => t.bookUrl.equals(bookUrl))).write(
      BooksCompanion(fileFingerprint: Value(fingerprint)),
    );
  }

  /// 書架上原檔指紋是 [fingerprint] 的本地書。
  Future<List<Book>> getInBookshelfByFingerprint(String fingerprint) {
    return (select(books)..where(
          (t) =>
              t.isInBookshelf.equals(true) &
              t.fileFingerprint.equals(fingerprint),
        ))
        .get();
  }

  Future<void> updateInBookshelf(String bookUrl, bool inBookshelf) {
    return (update(books)..where((t) => t.bookUrl.equals(bookUrl))).write(
      BooksCompanion(isInBookshelf: Value(inBookshelf)),
    );
  }

  Future<void> updateCanUpdate(String bookUrl, bool canUpdate) {
    return (update(books)..where((t) => t.bookUrl.equals(bookUrl))).write(
      BooksCompanion(canUpdate: Value(canUpdate)),
    );
  }

  /// 只記下檢查時間；書已不在資料庫時不會再寫回一筆。
  Future<void> updateLastCheckTime(String bookUrl, int lastCheckTime) {
    return (update(books)..where((t) => t.bookUrl.equals(bookUrl))).write(
      BooksCompanion(lastCheckTime: Value(lastCheckTime)),
    );
  }

  double _normalizeVisualOffsetPx(double value) {
    if (!value.isFinite || value.isNaN) return 0.0;
    return value.clamp(-120.0, 120.0).toDouble();
  }
}

/// 寫入時不帶原檔指紋那一欄：新的一筆留空，已有的一筆保留原值。
class _KeepFingerprint implements Insertable<Book> {
  const _KeepFingerprint(this._row);

  final Insertable<Book> _row;

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) =>
      Map.of(_row.toColumns(nullToAbsent))..remove('fileFingerprint');
}
