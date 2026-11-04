import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';

/// 每一章都是一行 30 個 a 接一個「!」，回溯規則遇到就跑不完。
class _Site extends BookSourceService {
  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async => '${chapter.title}的廣告。\n${'a' * 30}!';
}

class _SourceDao extends Fake implements BookSourceDao {
  _SourceDao(this.source);

  final BookSource source;

  @override
  Future<BookSource?> getByUrl(String url) async => source;
}

void main() {
  late AppDatabase db;
  late ReplaceRuleDao replaceDao;
  late ReaderV2ChapterRepository repository;
  late List<ReplaceRule> disabled;

  final source = BookSource.fromJson({
    'bookSourceName': '測試',
    'bookSourceUrl': 'https://s.example',
  });
  final book = Book(
    bookUrl: 'https://s.example/book/1',
    origin: 'https://s.example',
    name: '書',
  );
  final chapters = [
    for (var i = 0; i < 2; i++)
      BookChapter(
        url: 'https://s.example/c/$i.html',
        title: '第${i + 1}章',
        bookUrl: book.bookUrl,
        index: i,
      ),
  ];

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    replaceDao = ReplaceRuleDao(db);
    await replaceDao.insert(
      ReplaceRule(
        name: '回溯',
        pattern: r'(?m)^(a+)+$',
        replacement: 'x',
        timeoutMillisecond: 200,
        order: 1,
      ),
    );
    await replaceDao.insert(
      ReplaceRule(
        name: '去廣告',
        pattern: '的廣告',
        replacement: '',
        isRegex: false,
        order: 2,
      ),
    );
    final chapterDao = ChapterDao(db);
    await chapterDao.insertChapters(chapters);
    disabled = [];
    repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: chapters,
      bookDao: BookDao(db),
      chapterDao: chapterDao,
      replaceDao: replaceDao,
      sourceDao: _SourceDao(source),
      contentDao: ReaderChapterContentDao(db),
      service: _Site(),
      onReplaceRuleDisabled: disabled.add,
    );
  });

  tearDown(() => db.close());

  test('跑太久的規則被停用，這一章照其他規則套完照常顯示', () async {
    final content = await repository.loadContent(0);

    expect(content.plainText, contains('第1章。'));
    expect(content.plainText, contains('${'a' * 30}!'));
    expect(disabled.map((rule) => rule.name), ['回溯']);
    final rules = await replaceDao.getAll();
    expect(
      {for (final rule in rules) rule.name: rule.isEnabled},
      {'回溯': false, '去廣告': true},
    );
  });

  test('之後的章不再跑那一條', () async {
    await repository.loadContent(0);
    final next = await repository.loadContent(1);

    expect(next.plainText, contains('第2章。'));
    expect(disabled.map((rule) => rule.name), ['回溯']);
  });
}
