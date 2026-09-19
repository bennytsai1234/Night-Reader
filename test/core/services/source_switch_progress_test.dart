import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/source_switch_service.dart';

class _FakeBookSourceDao extends Fake implements BookSourceDao {
  _FakeBookSourceDao(this.source);

  final BookSource source;

  @override
  Future<BookSource?> getByUrl(String url) async {
    return url == source.bookSourceUrl ? source : null;
  }
}

class _FakeBookSourceService extends BookSourceService {
  _FakeBookSourceService(this.chapters);

  final List<BookChapter> chapters;

  @override
  Future<Book> getBookInfo(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) async {
    return book;
  }

  @override
  Future<List<BookChapter>> getChapterList(
    BookSource source,
    Book book, {
    int? chapterLimit,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    return chapters;
  }

  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    return '這是一段足夠長的已驗證正文內容，用來建立可提交的換源 handoff。';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('prepareSwitch 不會把沒有內容 identity 的章內座標帶到新來源', () async {
    final source = BookSource(
      bookSourceUrl: 'https://new-source.example',
      bookSourceName: '新源',
    );
    final newBookUrl = 'https://new-source.example/book/1';
    final chapters = List<BookChapter>.generate(
      3,
      (index) => BookChapter(
        url: '$newBookUrl/chapter/$index',
        title: '第${index + 1}章',
        bookUrl: newBookUrl,
        index: index,
      ),
    );
    final service = SourceSwitchService(
      service: _FakeBookSourceService(chapters),
      sourceDao: _FakeBookSourceDao(source),
    );
    final currentBook = Book(
      bookUrl: 'https://old-source.example/book/1',
      name: '測試書',
      author: '作者',
      origin: 'https://old-source.example',
      originName: '舊源',
      chapterIndex: 1,
      durChapterTitle: '第2章',
      charOffset: 123,
      visualOffsetPx: 45.5,
      totalChapterNum: 3,
    );
    final candidate = SearchBook(
      bookUrl: newBookUrl,
      name: '測試書',
      author: '作者',
      origin: source.bookSourceUrl,
      originName: source.bookSourceName,
    );

    final resolution = await service.prepareSwitch(
      currentBook,
      candidate,
      targetChapterIndex: 1,
      targetChapterTitle: '第2章',
    );

    expect(resolution.targetChapterIndex, 1);
    expect(resolution.migratedBook.charOffset, 0);
    expect(resolution.migratedBook.visualOffsetPx, 0);
    expect(resolution.migratedBook.readerAnchorJson, isNull);
  });
}
