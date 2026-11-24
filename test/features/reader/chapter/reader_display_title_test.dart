import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/features/reader/chapter/reader_chapter_repository.dart';

class _Site extends BookSourceService {
  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    return '正文。';
  }
}

class _SourceDao extends Fake implements BookSourceDao {
  _SourceDao(this.source);

  final BookSource source;

  @override
  Future<BookSource?> getByUrl(String url) async => source;
}

/// 標題規則改的章名用在頁首頁尾與選單（同 Legado 用排好的章名），目錄照
/// 原章名（Legado 目錄預設不套，T4）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ReaderChapterRepository repository;

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
    BookChapter(
      url: 'https://s.example/c/0.html',
      title: '第一章 求月票！',
      bookUrl: book.bookUrl,
      index: 0,
    ),
  ];

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final replaceDao = ReplaceRuleDao(db);
    await replaceDao.insert(
      ReplaceRule(
        name: '章名去求票',
        pattern: ' 求月票！',
        isRegex: false,
        scopeTitle: true,
        scopeContent: false,
      ),
    );
    final chapterDao = ChapterDao(db);
    await chapterDao.insertChapters(chapters);
    repository = ReaderChapterRepository(
      book: book,
      initialChapters: chapters,
      bookDao: BookDao(db),
      chapterDao: chapterDao,
      replaceDao: replaceDao,
      sourceDao: _SourceDao(source),
      contentDao: ReaderChapterContentDao(db),
      service: _Site(),
    );
  });

  tearDown(() async {
    repository.dispose();
    await db.close();
  });

  test('載好的章顯示套過標題規則的章名，目錄照原章名', () async {
    expect(repository.displayTitleFor(0), isNull, reason: '還沒載入');
    await repository.loadContent(0);
    expect(repository.displayTitleFor(0), '第一章');
    expect(repository.titleFor(0), '第一章 求月票！');
  });
}
