import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book_source.dart';

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

  test('film sources are unsupported even when typed as text', () {
    expect(
      _source(name: '某某影视', url: 'https://film.test').sourceKind,
      BookSourceKind.unsupported,
    );
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

  test('novel and audio sources search, read and join discovery; comic '
      'sources wait for the comic reader but are not cleanup candidates', () {
    for (final type in [0, 1]) {
      final source = _source(type: type, url: 'https://$type.test')
        ..exploreUrl = 'https://$type.test/explore';
      expect(source.isOpenableSource, isTrue);
      expect(source.isSearchEnabledByRuntime, isTrue);
      expect(source.isReadingEnabledByRuntime, isTrue);
      expect(source.canParticipateInDiscovery, isTrue);
    }
    final comic = _source(type: 2, url: 'https://2.test');
    expect(comic.isOpenableSource, isFalse);
    expect(comic.isSearchEnabledByRuntime, isFalse);
    expect(comic.isReadingEnabledByRuntime, isFalse);
    expect(comic.isCleanupCandidate, isFalse);
    expect(_source(type: 3).isCleanupCandidate, isTrue);
  });
}
