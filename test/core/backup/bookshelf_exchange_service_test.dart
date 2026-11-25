import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
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
import 'package:night_reader/core/models/search/search_book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/core/download/download_executor.dart';
import 'package:night_reader/core/network/network_service.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:night_reader/core/storage/book_illustration_storage.dart';

/// 照書名、作者搜得到的書：每個書源各自有哪幾本（書名、作者）。
class _Library extends BookSourceService {
  _Library(this.books);

  final Map<String, List<(String, String)>> books;
  final searched = <String>[];

  @override
  Future<List<SearchBook>> preciseSearch(
    BookSource source,
    String name,
    String author, {
    CancelToken? cancelToken,
  }) async {
    searched.add('${source.bookSourceUrl} $name');
    return [
      for (final (bookName, bookAuthor) in books[source.bookSourceUrl] ?? [])
        if (bookName == name && bookAuthor == author)
          SearchBook(
            bookUrl: '${source.bookSourceUrl}/$name',
            name: name,
            author: author,
            origin: source.bookSourceUrl,
            originName: source.bookSourceName,
          ),
    ];
  }

  @override
  Future<Book> getBookInfo(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) async => book.copyWith(intro: '${source.bookSourceName}的簡介');
}

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
    // 書架檔是別台做的：補抓插圖只對書源同一個網站帶登入資料。
    expect(await BookIllustrationStorage.isFromSource(book), isFalse);
    expect(await chaptersWithUntriedIllustrations(book), {'$url/0'});

    // 之後別的來源再留記號，外來的記號不會被洗掉。
    await BookIllustrationStorage.markUnfetched(book);
    expect(await BookIllustrationStorage.isFromSource(book), isFalse);

    // 都試過了：兩個記號一起刪掉。
    await File(
      BookIllustrationStorage.missingPathFor(
        await BookIllustrationStorage.dirFor(book),
        'https://i.example/1.png',
      ),
    ).create(recursive: true);
    expect(await chaptersWithUntriedIllustrations(book), isEmpty);
    expect(await BookIllustrationStorage.isUnfetched(book), isFalse);
    expect(await BookIllustrationStorage.isFromSource(book), isTrue);
  });

  group('和 Legado 互通（K11）', () {
    BookSource source(String url, {int order = 0, bool enabled = true}) =>
        BookSource(
          bookSourceUrl: url,
          bookSourceName: url.split('//').last,
          enabled: enabled,
          customOrder: order,
        );

    test('匯出的書架是 Legado 讀得懂的陣列：每本有書名、作者、簡介，夜讀自己的'
        '目錄、正文與書源跟著那本書', () async {
      await BookSourceDao(db).upsert(source(origin));
      final book = Book(
        bookUrl: url,
        origin: origin,
        name: '夜航',
        author: '某人',
        intro: '一段簡介',
        isInBookshelf: true,
        chapterIndex: 1,
      );
      await BookDao(db).upsert(book);
      await ChapterDao(db).insertChapters(toc(['序', '一']));
      await ReaderChapterContentDao(db).saveContent(
        contentKey: key(0),
        origin: origin,
        bookUrl: url,
        chapterUrl: '$url/0',
        chapterIndex: 0,
        content: '序文',
        updatedAt: 1,
      );
      final root = await Directory.systemTemp.createTemp('shelf_export');
      addTearDown(() => root.delete(recursive: true));
      AppStoragePaths.useRoots((
        documents: root.path,
        support: root.path,
        temporary: root.path,
      ));

      final file = await BookshelfExchangeService().exportBookshelf();
      final exported = jsonDecode(await file.readAsString());

      // Legado `importBookshelfByJson`：一定要是陣列，每一筆讀 name、author。
      expect(exported, isA<List<Object?>>());
      final entry = (exported as List).single as Map<String, dynamic>;
      expect(entry['name'], '夜航');
      expect(entry['author'], '某人');
      expect(entry['intro'], '一段簡介');

      // 夜讀匯回來：書、目錄、正文與書源都在。
      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      GetIt.instance
        ..unregister<BookDao>()
        ..unregister<ChapterDao>()
        ..unregister<BookSourceDao>()
        ..unregister<ReaderChapterContentDao>()
        ..registerSingleton<BookDao>(BookDao(other))
        ..registerSingleton<ChapterDao>(ChapterDao(other))
        ..registerSingleton<BookSourceDao>(BookSourceDao(other))
        ..registerSingleton<ReaderChapterContentDao>(
          ReaderChapterContentDao(other),
        );
      final result = await BookshelfExchangeService().importFromText(
        await file.readAsString(),
      );

      expect(result.books, 1);
      final imported = (await BookDao(other).getByUrl(url))!;
      expect(imported.isInBookshelf, isTrue);
      expect(imported.chapterIndex, 1);
      expect(await ChapterDao(other).titlesByBook(url), ['序', '一']);
      expect(
        await ReaderChapterContentDao(other)
            .hasReadyContent(contentKey: key(0)),
        isTrue,
      );
      expect(await BookSourceDao(other).getByUrl(origin), isNotNull);
    });

    test('Legado 匯出的書架照書名、作者在啟用的書源裡找，加第一個找到的', () async {
      final sources = BookSourceDao(db);
      await sources.upsert(source('https://a.example', order: 2));
      await sources.upsert(source('https://b.example', order: 1));
      await sources.upsert(
        source('https://off.example', order: 0, enabled: false),
      );
      await BookDao(db).upsert(
        Book(
          bookUrl: 'https://mine.example/1',
          origin: 'https://mine.example',
          name: '已在書架',
          author: '甲',
          isInBookshelf: true,
        ),
      );
      final library = _Library({
        'https://a.example': [('夜航', '某人'), ('只在甲', '乙')],
        'https://b.example': [('夜航', '某人')],
        'https://off.example': [('沒啟用', '丙')],
      });
      final progress = <(int, int)>[];

      final result = await BookshelfExchangeService(sourceService: library)
          .importFromText(
            jsonEncode([
              {'name': '夜航', 'author': '某人', 'intro': ''},
              {'name': '只在甲', 'author': '乙', 'intro': null},
              {'name': '已在書架', 'author': '甲', 'intro': ''},
              {'name': '沒啟用', 'author': '丙', 'intro': ''},
              {'name': '', 'author': '無名', 'intro': ''},
            ]),
            onSearchProgress: (done, total) => progress.add((done, total)),
          );

      final shelf = {
        for (final book in await BookDao(db).getInBookshelf()) book.name: book,
      };
      // 兩個書源都有時照書源排序，先加排前面的。
      expect(shelf['夜航']!.origin, 'https://b.example');
      expect(shelf['夜航']!.intro, 'b.example的簡介');
      expect(shelf['只在甲']!.origin, 'https://a.example');
      expect(shelf.keys, unorderedEquals(['夜航', '只在甲', '已在書架']));
      expect(result.books, 2);
      expect(result.alreadyOnShelf, 1);
      expect(result.notFound, ['沒啟用']);
      expect(result.summary, '已匯入 2 本書，1 本已經在書架上，照這台的留著，1 本找不到：沒啟用');
      expect(progress.last, (3, 3));
      expect(
        library.searched.where((s) => s.startsWith('https://off.example')),
        isEmpty,
      );
    });

    test('取消時停在兩本之間，找到的留著', () async {
      await BookSourceDao(db).upsert(source('https://a.example'));
      final cancel = CancelToken();
      final library = _Library({
        'https://a.example': [('一', ''), ('二', '')],
      });

      final result = await BookshelfExchangeService(sourceService: library)
          .importFromText(
            jsonEncode([
              {'name': '一', 'author': ''},
              {'name': '二', 'author': ''},
            ]),
            onSearchProgress: (done, _) {
              if (done == 1) cancel.cancel();
            },
            cancelToken: cancel,
          );

      expect(result.books, 1);
      expect((await BookDao(db).getInBookshelf()).map((b) => b.name), ['一']);
    });

    // 從別處拿到的檔：替換規則、書源與其他 JSON 不當成書架，什麼都不寫。
    for (final (label, rows) in [
      (
        '替換規則',
        [
          {'name': '去廣告', 'pattern': '廣告', 'replacement': ''},
        ],
      ),
      (
        '有作者的替換規則',
        [
          {'name': '去廣告', 'author': '某人', 'regex': '廣告'},
        ],
      ),
      (
        '書源',
        [
          {'bookSourceUrl': 'https://s.example', 'bookSourceName': '某站'},
        ],
      ),
      (
        '有書名、作者的書源',
        [
          {'name': '夜航', 'author': '某人', 'bookSourceUrl': 'https://s.example'},
        ],
      ),
      (
        '夾了一筆替換規則的書架',
        [
          {'name': '夜航', 'author': '某人', 'intro': ''},
          {'name': '去廣告', 'author': '', 'pattern': '廣告'},
        ],
      ),
      (
        '舊物件格式裡夾了替換規則',
        {
          'books': [
            {'bookUrl': 'https://s.example/1', 'name': '夜航', 'author': ''},
            {'name': '去廣告', 'author': '', 'pattern': '廣告'},
          ],
        },
      ),
      (
        '書的網址是空的',
        [
          {'bookUrl': null, 'name': '夜航', 'author': '某人'},
        ],
      ),
      (
        '沒有作者欄位',
        [
          {'name': '夜航', 'intro': ''},
        ],
      ),
    ]) {
      test('$label不是書架檔，什麼都不匯入', () async {
        await BookSourceDao(db).upsert(source('https://a.example'));
        final library = _Library({
          'https://a.example': [('夜航', '某人'), ('去廣告', ''), ('去廣告', '某人')],
        });

        final result = await BookshelfExchangeService(sourceService: library)
            .importFromText(jsonEncode(rows));

        expect(result.summary, isNull);
        expect(library.searched, isEmpty);
        expect(await BookDao(db).getInBookshelf(), isEmpty);
        expect(await BookSourceDao(db).getByUrl('https://s.example'), isNull);
      });
    }

    test('匯出不帶這台的東西：本地書只有書名、作者、簡介，網路書不帶本機封面'
        '路徑與書、章節的變數', () async {
      await BookSourceDao(db).upsert(source(origin));
      await BookDao(db).upsert(
        Book(
          bookUrl: url,
          origin: origin,
          name: '夜航',
          author: '某人',
          isInBookshelf: true,
          coverUrl: 'https://img.example/c.jpg',
          coverLocalPath: '/data/本機封面.jpg',
          customCoverUrl: 'file:///sdcard/相簿封面.jpg',
          customCoverLocalPath: '/data/本機自訂封面.jpg',
          variable: '{"書的變數":"1"}',
        ),
      );
      await ChapterDao(db).insertChapters([
        BookChapter(
          url: '$url/0',
          title: '序',
          bookUrl: url,
          variable: '{"章節的變數":"1"}',
        ),
      ]);
      await BookDao(db).upsert(
        Book(
          bookUrl: '/sdcard/本機檔.txt',
          origin: 'local',
          name: '本地',
          author: '某人',
          intro: '原簡介',
          customIntro: '自己寫的簡介',
          isInBookshelf: true,
          coverLocalPath: '/data/本地封面.jpg',
          fileFingerprint: 'abc',
        ),
      );
      final root = await Directory.systemTemp.createTemp('shelf_export');
      addTearDown(() => root.delete(recursive: true));
      AppStoragePaths.useRoots((
        documents: root.path,
        support: root.path,
        temporary: root.path,
      ));

      final file = await BookshelfExchangeService().exportBookshelf();
      final text = await file.readAsString();

      for (final local in [
        '本機封面',
        '相簿封面',
        '本機自訂封面',
        '書的變數',
        '章節的變數',
        '本機檔',
        '本地封面',
        'fileFingerprint',
      ]) {
        expect(text, isNot(contains(local)), reason: local);
      }
      final rows = (jsonDecode(text) as List).cast<Map<String, dynamic>>();
      final localRow = rows.singleWhere((row) => row['name'] == '本地');
      // 同 Legado `exportBookshelf`：簡介是顯示的那一份。
      expect(localRow, {'name': '本地', 'author': '某人', 'intro': '自己寫的簡介'});
      final webRow = rows.singleWhere((row) => row['name'] == '夜航');
      expect(webRow['coverUrl'], 'https://img.example/c.jpg');
      expect(webRow['bookUrl'], url);
      expect((webRow['chapters'] as List).single['title'], '序');
    });

    test('同一個書源只匯出一份，匯入時算不重複的書源', () async {
      await BookSourceDao(db).upsert(source(origin));
      for (final i in [1, 2]) {
        await BookDao(db).upsert(
          Book(
            bookUrl: '$origin/book/$i',
            origin: origin,
            name: '書$i',
            isInBookshelf: true,
          ),
        );
      }
      final root = await Directory.systemTemp.createTemp('shelf_export');
      addTearDown(() => root.delete(recursive: true));
      AppStoragePaths.useRoots((
        documents: root.path,
        support: root.path,
        temporary: root.path,
      ));

      final file = await BookshelfExchangeService().exportBookshelf();
      final rows = (jsonDecode(await file.readAsString()) as List)
          .cast<Map<String, dynamic>>();

      expect(rows.where((row) => row['source'] != null), hasLength(1));

      // 舊版匯出的檔每本都帶一份同樣的書源。
      final old = [
        for (final row in rows) {...row, 'source': source(origin).toJson()},
      ];
      final result = await BookshelfExchangeService().importFromText(
        jsonEncode(old),
      );
      expect(result.sources, 1);
      expect(result.summary, contains('1 個書源'));
    });
  });
}
