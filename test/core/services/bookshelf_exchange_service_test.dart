import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/bookshelf_exchange_service.dart';
import 'package:night_reader/core/services/network_service.dart';

class _FakeBookDao extends Fake implements BookDao {
  final List<Book> storedBooks = [];

  @override
  Future<void> upsert(Book book) async {
    storedBooks.removeWhere((e) => e.bookUrl == book.bookUrl);
    storedBooks.add(book);
  }

  @override
  Future<List<Book>> getInBookshelf() async => storedBooks;
}

class _FakeChapterDao extends Fake implements ChapterDao {
  final List<BookChapter> storedChapters = [];

  @override
  Future<void> insertChapters(List<BookChapter> chapterList) async {
    storedChapters.removeWhere(
      (existing) => chapterList.any((incoming) => incoming.url == existing.url),
    );
    storedChapters.addAll(chapterList);
  }
}

class _FakeBookSourceDao extends Fake implements BookSourceDao {
  final List<BookSource> sources = [];

  @override
  Future<void> upsert(BookSource source) async {
    sources.removeWhere((e) => e.bookSourceUrl == source.bookSourceUrl);
    sources.add(source);
  }
}

class _FakeNetworkService extends Fake implements NetworkService {
  @override
  Dio get dio => Dio();
}

void main() {
  setUp(() {
    final getIt = GetIt.instance;
    getIt.registerLazySingleton<BookDao>(() => _FakeBookDao());
    getIt.registerLazySingleton<ChapterDao>(() => _FakeChapterDao());
    getIt.registerLazySingleton<BookSourceDao>(() => _FakeBookSourceDao());
    getIt.registerLazySingleton<NetworkService>(() => _FakeNetworkService());
  });

  tearDown(() async => GetIt.instance.reset());

  test(
    'BookshelfExchangeService imports books, chapters and sources',
    () async {
      final service = BookshelfExchangeService();
      final payload = jsonEncode({
        'kind': 'night_reader.bookshelf',
        'version': 1,
        'books': [
          {
            'bookUrl': 'https://book/1',
            'name': '測試書',
            'author': '作者',
            'origin': 'https://source/1',
            'originName': '來源',
            'isInBookshelf': false,
          },
        ],
        'chapters': [
          {
            'url': 'https://book/1#0',
            'bookUrl': 'https://book/1',
            'title': '第一章',
            'index': 0,
            'content': '內容',
          },
        ],
        'sources': [
          {'bookSourceUrl': 'https://source/1', 'bookSourceName': '來源'},
        ],
      });

      final result = await service.importFromText(payload);
      final bookDao = GetIt.instance<BookDao>() as _FakeBookDao;
      final chapterDao = GetIt.instance<ChapterDao>() as _FakeChapterDao;
      final sourceDao = GetIt.instance<BookSourceDao>() as _FakeBookSourceDao;

      expect(result.books, 1);
      expect(result.chapters, 1);
      expect(result.sources, 1);
      expect(bookDao.storedBooks.single.isInBookshelf, isTrue);
      expect(chapterDao.storedChapters.single.content, isNull);
      expect(sourceDao.sources.single.bookSourceUrl, 'https://source/1');
    },
  );
}
