import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/services/book_storage_service.dart';
import 'package:night_reader/core/services/books_in_use.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => p.join(root, 'docs');

  @override
  Future<String?> getApplicationSupportPath() async => p.join(root, 'support');

  @override
  Future<String?> getTemporaryPath() async => p.join(root, 'temp');
}

void main() {
  late AppDatabase db;
  late Directory root;
  late BookDao books;
  late ChapterDao chapters;
  late ReaderChapterContentDao contents;
  late DownloadDao downloads;

  setUp(() async {
    await GetIt.instance.reset();
    root = await Directory.systemTemp.createTemp('book_storage_test');
    PathProviderPlatform.instance = _Paths(root.path);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    books = BookDao(db);
    chapters = ChapterDao(db);
    contents = ReaderChapterContentDao(db);
    downloads = DownloadDao(db);
  });

  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  Future<void> addBook(String url, {required bool onShelf}) async {
    await books.upsert(
      Book(
        bookUrl: url,
        origin: 'https://source.example',
        name: url,
        isInBookshelf: onShelf,
      ),
    );
  }

  Future<void> addChapter(
    String bookUrl, {
    String origin = 'https://source.example',
  }) async {
    final chapterUrl = '$bookUrl/c1';
    await chapters.insertChapters([
      BookChapter(url: chapterUrl, title: '第一章', bookUrl: bookUrl, index: 0),
    ]);
    await contents.saveContent(
      contentKey: ReaderChapterContentDao.contentKey(
        origin: origin,
        bookUrl: bookUrl,
        chapterUrl: chapterUrl,
      ),
      origin: origin,
      bookUrl: bookUrl,
      chapterUrl: chapterUrl,
      chapterIndex: 0,
      content: '正文',
      updatedAt: 1,
    );
  }

  Future<List<String>> contentBooks() async => [
    for (final row in await db.select(db.readerChapterContents).get())
      '${row.origin} ${row.bookUrl}',
  ];

  test('books off the shelf are discarded with their chapters, content and '
      'downloads; data of no shelf book goes too, open books stay', () async {
    await addBook('shelf', onShelf: true);
    await addChapter('shelf');
    // 換過書源前留下的正文：鍵含舊書源網址，再也讀不到。
    await addChapter('shelf', origin: 'https://old-source.example');
    await addBook('preview', onShelf: false);
    await addChapter('preview');
    await downloads.upsert(DownloadTask(bookUrl: 'preview', bookName: '暫存'));
    // 書早就不在資料庫裡，正文、目錄與下載任務還在。
    await addChapter('gone');
    await downloads.upsert(DownloadTask(bookUrl: 'gone', bookName: '已刪'));
    // 正在書籍詳情或閱讀器裡開著的試讀。
    await addBook('open', onShelf: false);
    await addChapter('open');
    final open = BooksInUse.hold('open');
    addTearDown(open.release);

    await BookStorageService(
      bookDao: books,
      chapterDao: chapters,
      contentDao: contents,
      downloadDao: downloads,
    ).discardUnshelvedBooks();

    expect(
      (await books.getAll()).map((book) => book.bookUrl),
      unorderedEquals(['shelf', 'open']),
    );
    expect(
      await contentBooks(),
      unorderedEquals([
        'https://source.example shelf',
        'https://source.example open',
      ]),
    );
    expect(await chapters.getByBook('shelf'), hasLength(1));
    expect(await chapters.getByBook('open'), hasLength(1));
    expect(await chapters.getByBook('preview'), isEmpty);
    expect(await chapters.getByBook('gone'), isEmpty);
    expect(await downloads.getAll(), isEmpty);
  });
}
