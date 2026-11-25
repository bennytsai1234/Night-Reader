import 'dart:convert';
import 'dart:io';

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
import 'package:night_reader/core/download/download_executor.dart';
import 'package:night_reader/core/network/network_service.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:night_reader/core/storage/book_illustration_storage.dart';

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

      final result = await BookshelfExchangeService().importFromText(file);

      expect(result.summary, '1 本已經在書架上，照這台的留著');
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

  String fileWith(Book book, List<String> titles) => jsonEncode({
    'kind': 'night_reader.bookshelf',
    'version': 1,
    'books': [book.toJson()],
    'chapters': [for (final c in toc(titles)) c.toJson()],
    'chapterContents': [],
    'sources': [],
  });

  test('a book on this shelf without a TOC gets the file\'s', () async {
    await BookDao(db).upsert(
      Book(bookUrl: url, origin: origin, name: '夜航', isInBookshelf: true),
    );

    await BookshelfExchangeService().importFromText(
      fileWith(Book(bookUrl: url, origin: origin, name: '夜航'), ['序', '一']),
    );

    expect(await ChapterDao(db).titlesByBook(url), ['序', '一']);
  });

  test('a book only opened in its details here (not on the shelf) joins the '
      'shelf with the file\'s progress and TOC together', () async {
    await BookDao(
      db,
    ).upsert(Book(bookUrl: url, origin: origin, name: '夜航', chapterIndex: 0));
    await ChapterDao(db).insertChapters(toc(['甲', '乙']));

    await BookshelfExchangeService().importFromText(
      fileWith(
        Book(
          bookUrl: url,
          origin: origin,
          name: '夜航',
          chapterIndex: 2,
          durChapterTitle: '二',
        ),
        ['序', '一', '二'],
      ),
    );

    final book = (await BookDao(db).getByUrl(url))!;
    expect(book.isInBookshelf, isTrue);
    expect(book.chapterIndex, 2);
    expect((await ChapterDao(db).titlesByBook(url))[2], '二');
  });

  // 書架檔帶正文、不帶圖檔：有插圖的書要排插圖補抓，離線才看得到圖。
  test('text with illustrations from the file is marked for the shelf '
      'download to fetch its pictures', () async {
    final root = await Directory.systemTemp.createTemp('shelf_file_images');
    addTearDown(() => root.delete(recursive: true));
    AppStoragePaths.useRoots((
      documents: root.path,
      support: root.path,
      temporary: root.path,
    ));
    final book = Book(bookUrl: url, origin: origin, name: '有圖');
    ReaderChapterContentEntry entry(int i, String text) =>
        ReaderChapterContentEntry(
          contentKey: key(i),
          origin: origin,
          bookUrl: url,
          chapterUrl: '$url/$i',
          chapterIndex: i,
          status: ReaderChapterContentStatus.ready,
          content: text,
          updatedAt: 1,
        );
    final file = jsonEncode({
      'kind': 'night_reader.bookshelf',
      'version': 1,
      'books': [book.toJson()],
      'chapters': [
        for (final c in toc(['一', '二'])) c.toJson(),
      ],
      'chapterContents': [
        entry(0, '前文\n<img src="https://i.example/1.png">\n後文').toJson(),
        entry(1, '沒有圖').toJson(),
      ],
      'sources': [],
    });

    await BookshelfExchangeService().importFromText(file);

    expect(await BookIllustrationStorage.isUnfetched(book), isTrue);
    expect(await chaptersWithUntriedIllustrations(book), {'$url/0'});
  });
}
