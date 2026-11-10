import 'package:drift/drift.dart';

import '../../models/base_source.dart';
import '../../models/book_source.dart';
import '../../services/app_log_service.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';
import 'book_dao.dart';
import 'reader_chapter_content_dao.dart';
import 'search_book_dao.dart';

part 'book_source_dao.g.dart';

@DriftAccessor(tables: [BookSources])
class BookSourceDao extends DatabaseAccessor<AppDatabase>
    with _$BookSourceDaoMixin {
  BookSourceDao(super.db);

  Future<List<BookSource>> getAll() => select(bookSources).get();

  Stream<List<BookSource>> watchAll() => select(bookSources).watch();

  Future<List<BookSource>> getAllPart() {
    return _partQuery().map(_readPartSource).get();
  }

  Stream<List<BookSource>> watchAllPart() {
    return _partQuery().map(_readPartSource).watch();
  }

  Future<List<BookSource>> getDiscoveryPart() {
    return _partQuery(discoveryOnly: true).map(_readPartSource).get();
  }

  Stream<List<BookSource>> watchDiscoveryPart() {
    return _partQuery(discoveryOnly: true).map(_readPartSource).watch();
  }

  /// 有沒有任何書源；只查一列，不把整份書源讀出來。書架與發現頁的空狀態
  /// 據此決定要帶去搜尋還是匯入書源。
  Stream<bool> watchHasAny() {
    final query = selectOnly(bookSources)
      ..addColumns([bookSources.bookSourceUrl])
      ..limit(1);
    return query.watch().map((rows) => rows.isNotEmpty);
  }

  Future<List<BookSource>> getEnabled() {
    return (select(bookSources)..where((t) => t.enabled.equals(true))).get();
  }

  Future<BookSource?> getByUrl(String url) {
    return (select(
      bookSources,
    )..where((t) => t.bookSourceUrl.equals(url))).getSingleOrNull();
  }

  /// 存書源。校驗、手動、同步、匯入都經過這裡（和 [upsertAll]），類型改了
  /// 用它的書就跟著換類別（[_followKinds]）。
  Future<void> upsert(BookSource source) => transaction(() async {
    await into(bookSources)
        .insertOnConflictUpdate(BookSourceToInsertable(source).toInsertable());
    await _followKinds([source]);
  });

  Future<void> upsertAll(List<BookSource> sources) => transaction(() async {
    await batch(
      (b) => b.insertAllOnConflictUpdate(
        bookSources,
        sources.map((e) => BookSourceToInsertable(e).toInsertable()).toList(),
      ),
    );
    await _followKinds(sources);
  });

  /// 每本書跟著它的書源現在的類型：還原備份時書與書源分開寫進來，寫的
  /// 先後照 ZIP 裡的檔案順序，兩邊都寫完再對一次。
  Future<int> followAllKinds() async =>
      BookDao(attachedDatabase)
          .followSourceKinds(kindsToFollow(await getAll()));

  /// 書跟著書源的類型（使用者 2026-11-09 定，ADR 0053）：校驗只在有把握時
  /// 改類型，改了表示用它加進來的書其實是那一類，留在原本那一類也讀不了。
  Future<void> _followKinds(List<BookSource> sources) =>
      BookDao(attachedDatabase).followSourceKinds(kindsToFollow(sources));

  /// 書要跟著的書源類型（[BookDao.followSourceKinds]）。夜讀不支援的類型
  /// 不動書；聚合源的書各自是哪一類由書源的規則寫（ADR 0056），也不動。
  static Map<String, BookSourceKind> kindsToFollow(
    Iterable<BookSource> sources,
  ) => {
    for (final source in sources)
      if (source.sourceKind != BookSourceKind.unsupported &&
          !source.isAggregateSource)
        source.bookSourceUrl: source.sourceKind,
  };

  /// 儲存編輯後的書源。網址改過時是同一個書源換了身分：在同一個交易裡移除
  /// 原網址那筆，記著原網址的書、搜尋結果與已存的正文一起改記新網址，書架
  /// 上的書照樣找得到書源、已下載的章節照樣在。登入資訊與書源變數存在快取
  /// 裡，由 `BookSourceService.saveEditedSource` 搬。
  Future<void> saveEdited(BookSource source, {String? previousUrl}) {
    return transaction(() async {
      await upsert(source);
      if (previousUrl == null || previousUrl == source.bookSourceUrl) return;
      final to = source.bookSourceUrl;
      final name = source.bookSourceName;
      await BookDao(attachedDatabase).moveOrigin(previousUrl, to, toName: name);
      await SearchBookDao(attachedDatabase)
          .moveOrigin(previousUrl, to, toName: name);
      await ReaderChapterContentDao(attachedDatabase)
          .moveOrigin(previousUrl, to);
      // 原網址的書搬過來了才跟著新類型：存書源時它們還記著原網址。
      await _followKinds([source]);
      // 舊網址存的登入資訊與變數已經搬到新網址（存檔成功後才刪舊的），這裡
      // 只刪書源那一列。
      await _deleteRows([previousUrl]);
    });
  }

  /// 刪掉書源，連同以它的身分存的登入資訊、登入標頭與變數
  /// （[BaseSource.forgetCachedIdentity]）。
  Future<void> deleteByUrl(String url) => deleteByUrls([url]);

  Future<void> deleteByUrls(List<String> urls) async {
    await _deleteRows(urls);
    final remaining = await (selectOnly(
      bookSources,
    )..addColumns([bookSources.bookSourceUrl])).get();
    final otherKeys = [
      for (final row in remaining) row.read(bookSources.bookSourceUrl)!,
    ];
    for (final url in urls) {
      try {
        await BaseSource.forgetCachedIdentity(url, otherKeys: otherKeys);
      } catch (error, stackTrace) {
        AppLog.e(
          '書源刪掉了，它存的登入資訊與變數沒刪乾淨: $url',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _deleteRows(List<String> urls) async {
    await (delete(bookSources)..where((t) => t.bookSourceUrl.isIn(urls))).go();
  }

  Future<List<BookSource>> getAllFull() => getAll();

  Future<void> insertOrUpdateAll(List<BookSource> sources) =>
      upsertAll(sources);

  Future<void> updateCustomOrderByUrl(String url, int customOrder) {
    return (update(bookSources)..where((t) => t.bookSourceUrl.equals(url)))
        .write(BookSourcesCompanion(customOrder: Value(customOrder)));
  }

  Future<void> updateEnabledByUrl(String url, bool enabled) {
    return (update(bookSources)..where((t) => t.bookSourceUrl.equals(url)))
        .write(BookSourcesCompanion(enabled: Value(enabled)));
  }

  Future<void> updateEnabledExploreByUrl(String url, bool enabledExplore) {
    return (update(bookSources)..where((t) => t.bookSourceUrl.equals(url)))
        .write(BookSourcesCompanion(enabledExplore: Value(enabledExplore)));
  }

  Future<void> updateEnabledByUrls(List<String> urls, bool enabled) {
    if (urls.isEmpty) return Future.value();
    return (update(bookSources)..where((t) => t.bookSourceUrl.isIn(urls)))
        .write(BookSourcesCompanion(enabled: Value(enabled)));
  }

  Future<void> updateEnabledExploreByUrls(
    List<String> urls,
    bool enabledExplore,
  ) {
    if (urls.isEmpty) return Future.value();
    return (update(bookSources)..where((t) => t.bookSourceUrl.isIn(urls)))
        .write(BookSourcesCompanion(enabledExplore: Value(enabledExplore)));
  }

  /// 寫入搜尋量到的回應時間（毫秒），鍵是書源網址。
  Future<void> updateRespondTimes(Map<String, int> respondTimes) async {
    if (respondTimes.isEmpty) return;
    await batch((b) {
      respondTimes.forEach((url, ms) {
        b.update(
          bookSources,
          BookSourcesCompanion(respondTime: Value(ms)),
          where: (t) => t.bookSourceUrl.equals(url),
        );
      });
    });
  }

  Future<void> updateCustomOrder(List<BookSource> sources) async {
    for (var i = 0; i < sources.length; i++) {
      await (update(bookSources)
            ..where((t) => t.bookSourceUrl.equals(sources[i].bookSourceUrl)))
          .write(BookSourcesCompanion(customOrder: Value(i)));
    }
  }

  Selectable<QueryRow> _partQuery({bool discoveryOnly = false}) {
    return customSelect(
      '''
      SELECT
        bookSourceUrl,
        bookSourceName,
        bookSourceType,
        bookSourceGroup,
        bookSourceComment,
        loginUrl,
        bookUrlPattern,
        customOrder,
        weight,
        enabled,
        enabledExplore,
        enabledCookieJar,
        lastUpdateTime,
        respondTime,
        concurrentRate,
        exploreUrl,
        searchUrl
      FROM book_sources
      ${discoveryOnly ? _discoveryWhereClause : ''}
      ORDER BY customOrder ASC
      ''',
      variables: discoveryOnly ? const [Variable<String>('')] : const [],
      readsFrom: {bookSources},
    );
  }

  /// 只先篩開關與發現網址；哪幾類能進發現由
  /// [BookSourceLogic.canParticipateInDiscovery] 判斷。
  static const String _discoveryWhereClause = '''
      WHERE enabled = 1
        AND enabledExplore = 1
        AND COALESCE(TRIM(exploreUrl), '') <> ?
      ''';

  BookSource _readPartSource(QueryRow row) {
    return BookSource(
      bookSourceUrl: row.read<String>('bookSourceUrl'),
      bookSourceName: row.read<String>('bookSourceName'),
      bookSourceType: row.read<int>('bookSourceType'),
      bookSourceGroup: row.read<String?>('bookSourceGroup'),
      bookSourceComment: row.read<String?>('bookSourceComment'),
      loginUrl: row.read<String?>('loginUrl'),
      bookUrlPattern: row.read<String?>('bookUrlPattern'),
      customOrder: row.read<int>('customOrder'),
      weight: row.read<int>('weight'),
      enabled: _readBool(row, 'enabled'),
      enabledExplore: _readBool(row, 'enabledExplore'),
      enabledCookieJar: _readBool(row, 'enabledCookieJar'),
      lastUpdateTime: row.read<int>('lastUpdateTime'),
      respondTime: row.read<int>('respondTime'),
      concurrentRate: row.read<String?>('concurrentRate'),
      exploreUrl: row.read<String?>('exploreUrl'),
      searchUrl: row.read<String?>('searchUrl'),
    );
  }

  bool _readBool(QueryRow row, String column) {
    final value = row.data[column];
    return value == true || value == 1;
  }

  Future<void> renameGroup(String oldName, String newName) async {
    final all = await getAll();
    for (final s in all) {
      final groups = splitSourceGroups(s.bookSourceGroup);
      if (groups.contains(oldName)) {
        final updated = groups.map((g) => g == oldName ? newName : g).join(',');
        await (update(bookSources)
              ..where((t) => t.bookSourceUrl.equals(s.bookSourceUrl)))
            .write(BookSourcesCompanion(bookSourceGroup: Value(updated)));
      }
    }
  }

  Future<void> removeGroupLabel(String name) async {
    final all = await getAll();
    for (final s in all) {
      final groups = splitSourceGroups(s.bookSourceGroup);
      if (!groups.remove(name)) continue;
      final updated = groups.join(',');
      await (update(
        bookSources,
      )..where((t) => t.bookSourceUrl.equals(s.bookSourceUrl))).write(
        BookSourcesCompanion(
          bookSourceGroup: Value(updated.isEmpty ? null : updated),
        ),
      );
    }
  }

  Future<void> adjustSortNumbers() async {
    final stats = await customSelect(
      '''
          SELECT
            COUNT(*) AS sourceCount,
            COUNT(DISTINCT customOrder) AS distinctOrderCount,
            MIN(customOrder) AS minOrder,
            MAX(customOrder) AS maxOrder
          FROM book_sources
          ''',
      readsFrom: {bookSources},
    ).getSingle();
    final sourceCount = stats.read<int>('sourceCount');
    if (sourceCount == 0) return;

    final distinctOrderCount = stats.read<int>('distinctOrderCount');
    final minOrder = stats.read<int?>('minOrder') ?? 0;
    final maxOrder = stats.read<int?>('maxOrder') ?? 0;
    final needsAdjustment =
        distinctOrderCount != sourceCount ||
        minOrder < -99999 ||
        maxOrder > 99999;
    if (!needsAdjustment) return;

    final rows = await customSelect(
      '''
          SELECT bookSourceUrl, customOrder
          FROM book_sources
          ORDER BY customOrder ASC
          ''',
      readsFrom: {bookSources},
    ).get();
    await batch((b) {
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        if (row.read<int>('customOrder') == i) continue;
        b.update(
          bookSources,
          BookSourcesCompanion(customOrder: Value(i)),
          where: (t) =>
              t.bookSourceUrl.equals(row.read<String>('bookSourceUrl')),
        );
      }
    });
  }
}
