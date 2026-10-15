import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';

/// 網站先回擋爬蟲頁，之後恢復正常，或整個連不上。
class _Site extends BookSourceService {
  String? body;

  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    final text = body;
    if (text == null) {
      throw DioException(
        requestOptions: RequestOptions(path: chapter.url),
        response: Response(
          requestOptions: RequestOptions(path: chapter.url),
          statusCode: 503,
        ),
      );
    }
    return text;
  }
}

class _SourceDao extends Fake implements BookSourceDao {
  _SourceDao(this.source);

  final BookSource source;

  @override
  Future<BookSource?> getByUrl(String url) async => source;
}

void main() {
  late AppDatabase db;
  late _Site site;
  late ReaderV2ChapterRepository repository;

  final source = BookSource.fromJson({
    'bookSourceName': '測試',
    'bookSourceUrl': 'https://s.example',
  });
  final book = Book(
    bookUrl: 'https://s.example/book/1',
    origin: 'https://s.example',
    name: '書',
  );
  final chapter = BookChapter(
    url: 'https://s.example/c/1.html',
    title: '第一章',
    bookUrl: book.bookUrl,
  );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    site = _Site();
    final chapterDao = ChapterDao(db);
    await chapterDao.insertChapters([chapter]);
    repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: [chapter],
      bookDao: BookDao(db),
      chapterDao: chapterDao,
      sourceDao: _SourceDao(source),
      contentDao: ReaderChapterContentDao(db),
      service: site,
    );
  });

  tearDown(() => db.close());

  test('refetching replaces a stored anti-bot page', () async {
    site.body = '訪問過於頻繁，請稍後再試';
    final before = await repository.loadContent(0);
    expect(before.plainText, contains('訪問過於頻繁'));

    site.body = '夜色漸深，城東的街巷早已沒了人聲。';
    final after = await repository.reloadContent(0, refetch: true);

    expect(after.plainText, contains('夜色漸深'));
    expect(repository.cachedContent(0)?.plainText, contains('夜色漸深'));
  });

  test('a failed refetch keeps the text being read', () async {
    site.body = '只抓到一半的正文';
    final before = await repository.loadContent(0);

    site.body = null;
    await expectLater(
      repository.reloadContent(0, refetch: true),
      throwsA(isA<ReaderV2ContentUnavailableException>()),
    );

    expect(repository.cachedContent(0), same(before));
    // 存著的正文也沒有被失敗蓋掉，下次開書照樣讀得到。
    site.body = '不該被讀到';
    final reopened = await repository.reloadContent(0);
    expect(reopened.plainText, contains('只抓到一半的正文'));
  });
}
