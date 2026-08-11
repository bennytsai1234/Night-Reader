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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resolveSwitch 會把目前章節內位置帶到新來源', () async {
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

    final resolution = await service.resolveSwitch(
      currentBook,
      candidate,
      targetChapterIndex: 1,
      targetChapterTitle: '第2章',
    );

    expect(resolution.targetChapterIndex, 1);
    expect(resolution.migratedBook.charOffset, 123);
    expect(resolution.migratedBook.visualOffsetPx, 45.5);
  });
}
