import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/source_type.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book_source.dart';

/// 聚合源的寫法（源倉庫的大灰狼、晴天融合）：目錄規則照登入表單選的模式，
/// 逐本書設定類型。
BookSource _aggregate({
  String name = '聚合',
  String url = 'https://aggregate.test',
}) => _source(name: name, url: url)
  ..ruleToc = TocRule(
    chapterList:
        "<js>if (media == '漫画') { book.type = 64; } else { book.type = 8; }"
        ' result</js>',
  );

BookSource _source({
  String name = '某站',
  int type = 0,
  String? group,
  String url = 'https://site.test',
}) => BookSource(
  bookSourceUrl: url,
  bookSourceName: name,
  bookSourceType: type,
  bookSourceGroup: group,
);

void main() {
  test('the kind follows the source type only', () {
    expect(_source(type: 0).sourceKind, BookSourceKind.novel);
    expect(_source(type: 1).sourceKind, BookSourceKind.audio);
    expect(_source(type: 2).sourceKind, BookSourceKind.comic);
    expect(_source(type: 3).sourceKind, BookSourceKind.unsupported);
    expect(_source(type: 9).sourceKind, BookSourceKind.unsupported);
  });

  test('a text source the check found to be text stays a novel even when '
      'its name says comic', () {
    // 名稱帶漫畫字樣只在匯入時用來補判；之後只看類型。
    expect(_source(name: '漫画小说网').sourceKind, BookSourceKind.novel);
  });

  test('incoming text sources named after films are typed as video', () {
    final film = _source(name: '某某影视', url: 'https://film.test')
      ..prepareIncoming();

    expect(film.bookSourceType, SourceType.video);
    expect(film.sourceKind, BookSourceKind.unsupported);
  });

  test('the comment and the search url do not decide the kind', () {
    // 作者的備註與搜尋網址裡的程式常提到別的類別（「会同时搜索小说和视频」）。
    final noted = _source(url: 'https://a.test')
      ..bookSourceComment = '会同时搜索小说和视频，支持小说/漫画'
      ..prepareIncoming();
    final scripted = _source(url: 'https://b.test')
      ..searchUrl = "<js>var tab = {'听书': 't:', '漫画': 'm:'}</js>"
      ..prepareIncoming();

    expect(noted.bookSourceType, SourceType.book);
    expect(scripted.bookSourceType, SourceType.book);
  });

  test('an aggregate source keeps the type its author wrote', () {
    final source = _aggregate(name: '小说，漫画，听书')
      ..bookSourceComment = '短剧、视频模式仅支持苹果'
      ..prepareIncoming();

    expect(source.isAggregateSource, isTrue);
    expect(source.bookSourceType, SourceType.book);
    expect(source.sourceKind, BookSourceKind.novel);
  });

  test('a source is aggregate only when a rule assigns book.type', () {
    expect(_aggregate().isAggregateSource, isTrue);
    expect(
      (_source()..jsLib = 'function m(){ book.type = 32; }').isAggregateSource,
      isTrue,
    );
    expect(
      (_source()..ruleToc = TocRule(chapterList: 'if (book.type == 64) x'))
          .isAggregateSource,
      isFalse,
    );
    expect(_source().isAggregateSource, isFalse);
  });

  test('schema 15 sources: aggregates typed audio by their names go back '
      'to novel and are enabled again; films typed as text become video', () {
    final aggregate = _aggregate(name: '晴天融合（小说·听书·漫画）')
      ..bookSourceType = SourceType.audio;
    final disabled = _aggregate(name: '大灰狼聚合', url: 'https://d.test')
      ..bookSourceGroup = '大灰狼,$nonNovelSourceGroupTag'
      ..enabled = false
      ..enabledExplore = false;
    final misread = _source(url: 'https://m.test')
      ..bookSourceComment = '视频获取一直有问题就没写'
      ..bookSourceGroup = nonNovelSourceGroupTag
      ..enabled = false;
    final film = _source(name: '电影天堂', url: 'https://f.test');
    final checked = _source(name: '漫画小说网', url: 'https://c.test');

    for (final source in [aggregate, disabled, misread, film, checked]) {
      repairSchema15SourceKind(source);
    }

    expect(aggregate.bookSourceType, SourceType.book);
    expect(disabled.groupTags, {'大灰狼'});
    expect(disabled.enabled, isTrue);
    expect(disabled.enabledExplore, isTrue);
    expect(misread.groupTags, isEmpty);
    expect(misread.enabled, isTrue);
    expect(film.bookSourceType, SourceType.video);
    // 校驗照正文改回小說的不再照字樣改成漫畫。
    expect(checked.bookSourceType, SourceType.book);
  });

  test('manual source switching lists aggregate sources for every kind; '
      'automatic switching only uses the same kind', () {
    final aggregate = _aggregate();

    expect(
      aggregate.isSearchableFor(BookSourceKind.comic, includeAggregates: true),
      isTrue,
    );
    expect(aggregate.isSearchableFor(BookSourceKind.comic), isFalse);
    expect(
      _source().isSearchableFor(BookSourceKind.comic, includeAggregates: true),
      isFalse,
    );
  });

  test('books of an aggregate source do not follow its type', () {
    final kinds = BookSourceDao.kindsToFollow([
      _aggregate(),
      _source(type: 2, url: 'https://comic.test'),
      _source(type: 4, url: 'https://film.test'),
    ]);

    expect(kinds, {'https://comic.test': BookSourceKind.comic});
  });

  test('incoming text sources named after comics or audio get typed', () {
    final comic = _source(name: '包子漫画', url: 'https://a.test')
      ..prepareIncoming();
    final audio = _source(group: '有聲', url: 'https://b.test')
      ..prepareIncoming();
    final novel = _source(name: '番茄小说', url: 'https://c.test')
      ..prepareIncoming();
    final typed = _source(name: '有声漫画', type: 2, url: 'https://d.test')
      ..prepareIncoming();

    expect(comic.bookSourceType, 2);
    expect(audio.bookSourceType, 1);
    expect(novel.bookSourceType, 0);
    // 類型本來就不是 0 的不照字樣改。
    expect(typed.bookSourceType, 2);
  });

  test('only the legacy non-novel mark of a comic source is lifted', () {
    final comic = _source(
      name: '包子漫画',
      group: '精選,$nonNovelSourceGroupTag,$abnormalSourceGroupTag',
      url: 'https://a.test',
    )..enabled = false;
    final film = _source(
      name: '电影天堂',
      group: nonNovelSourceGroupTag,
      url: 'https://b.test',
    )..enabled = false;

    expect(upgradeLegacyNonNovelSource(comic), isTrue);
    expect(comic.groupTags, {'精選'});
    expect(comic.enabled, isTrue);
    expect(upgradeLegacyNonNovelSource(film), isFalse);
    expect(film.groupTags, {nonNovelSourceGroupTag});
    expect(film.enabled, isFalse);
  });

  test('novel, audio and comic sources search, read and join discovery; '
      'unsupported ones are cleanup candidates', () {
    for (final type in [0, 1, 2]) {
      final source = _source(type: type, url: 'https://$type.test')
        ..exploreUrl = 'https://$type.test/explore';
      expect(source.isOpenableSource, isTrue);
      expect(source.isSearchEnabledByRuntime, isTrue);
      expect(source.isReadingEnabledByRuntime, isTrue);
      expect(source.canParticipateInDiscovery, isTrue);
    }
    expect(_source(type: 2, url: 'https://2.test').isCleanupCandidate, isFalse);
    expect(_source(type: 3).isCleanupCandidate, isTrue);
  });
}
