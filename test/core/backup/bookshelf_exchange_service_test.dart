import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/backup/bookshelf_exchange_service.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/book/reader_chapter_content.dart';
import 'package:night_reader/core/network/network_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  const origin = 'https://shelf-file.example';
  const url = '$origin/book/1';

  setUp(() async {
    await GetIt.instance.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await NetworkService().init(ephemeral: true);
    GetIt.instance
      ..registerSingleton<BookDao>(BookDao(db))
      ..registerSingleton<ChapterDao>(ChapterDao(db))
      ..registerSingleton<BookSourceDao>(BookSourceDao(db))
      ..registerSingleton<ReaderChapterContentDao>(ReaderChapterContentDao(db))
      ..registerSingleton<NetworkService>(NetworkService());
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  String key(int chapter) => ReaderChapterContentDao.contentKey(
    origin: origin,
    bookUrl: url,
    chapterUrl: '$url/$chapter',
  );

  List<BookChapter> toc(List<String> titles) => [
    for (final (i, title) in titles.indexed)
      BookChapter(url: '$url/$i', title: title, bookUrl: url, index: i),
  ];

  test(
    'a book already on this shelf keeps its progress, group, cover, '
    'chapters and downloaded text when a bookshelf file has it too',
    () async {
      final books = BookDao(db);
      final contents = ReaderChapterContentDao(db);
      await books.upsert(
        Book(
          bookUrl: url,
          origin: origin,
          name: '夜航',
          isInBookshelf: true,
          chapterIndex: 5,
          durChapterTitle: '第五章',
          group: 4,
          customCoverUrl: 'https://img.example/mine.jpg',
        ),
      );
      await ChapterDao(db)
          .insertChapters(toc(['序', '一', '二', '三', '四', '第五章', '第六章']));
      await contents.saveContent(
        contentKey: key(3),
        origin: origin,
        bookUrl: url,
        chapterUrl: '$url/3',
        chapterIndex: 3,
        content: '已下載的第三章',
        updatedAt: 1,
      );
      // 另一台很久以前匯出的書架檔：讀到第 1 章、第 3 章是抓失敗的紀錄。
      final file = jsonEncode({
        'kind': 'night_reader.bookshelf',
        'version': 1,
        'books': [
          Book(
            bookUrl: url,
            origin: origin,
            name: '夜航',
            isInBookshelf: true,
            chapterIndex: 1,
            durChapterTitle: '一',
          ).toJson(),
        ],
        'chapters': [
          for (final c in toc(['序', '一', '二', '三'])) c.toJson(),
        ],
        'chapterContents': [
          ReaderChapterContentEntry(
            contentKey: key(3),
            origin: origin,
            bookUrl: url,
            chapterUrl: '$url/3',
            chapterIndex: 3,
            status: ReaderChapterContentStatus.failed,
            failureMessage: '抓不到',
            updatedAt: 2,
          ).toJson(),
        ],
        'sources': [],
      });

      await BookshelfExchangeService().importFromText(file);

      final book = (await books.getByUrl(url))!;
      expect(book.chapterIndex, 5);
      expect(book.group, 4);
      expect(book.customCoverUrl, 'https://img.example/mine.jpg');
      expect(await ChapterDao(db).titlesByBook(url), hasLength(7));
      expect(await contents.hasReadyContent(contentKey: key(3)), isTrue);
    },
  );

  test('a new book from the file joins the shelf with its chapters and only '
      'its downloaded text', () async {
    final file = jsonEncode({
      'kind': 'night_reader.bookshelf',
      'version': 1,
      'books': [
        Book(
          bookUrl: url,
          origin: origin,
          name: '夜航',
          chapterIndex: 1,
        ).toJson(),
      ],
      'chapters': [
        for (final c in toc(['序', '一'])) c.toJson(),
      ],
      'chapterContents': [
        for (final (i, status) in [
          ReaderChapterContentStatus.ready,
          ReaderChapterContentStatus.failed,
        ].indexed)
          ReaderChapterContentEntry(
            contentKey: key(i),
            origin: origin,
            bookUrl: url,
            chapterUrl: '$url/$i',
            chapterIndex: i,
            status: status,
            content: status == ReaderChapterContentStatus.ready ? '序文' : null,
            updatedAt: 1,
          ).toJson(),
      ],
      'sources': [],
    });

    await BookshelfExchangeService().importFromText(file);

    final book = (await BookDao(db).getByUrl(url))!;
    expect(book.isInBookshelf, isTrue);
    expect(book.chapterIndex, 1);
    expect(await ChapterDao(db).titlesByBook(url), ['序', '一']);
    final contents = ReaderChapterContentDao(db);
    expect(await contents.hasReadyContent(contentKey: key(0)), isTrue);
    expect(
      await contents.getEntriesByBookUrls([url]),
      hasLength(1),
      reason: '抓失敗的紀錄不寫進來',
    );
  });
}
