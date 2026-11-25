import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/local_book/local_book_service.dart';
import 'package:night_reader/core/local_book/txt_parser.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/reading/bookmark.dart';
import 'package:night_reader/core/models/reading/highlight.dart';
import 'package:night_reader/core/utils/encoding_detect.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _DirPathProvider extends PathProviderPlatform {
  _DirPathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  late Directory picked;
  late AppDatabase db;
  late BookDao bookDao;
  late ChapterDao chapterDao;
  late BookmarkDao bookmarkDao;
  late HighlightDao highlightDao;
  late ReaderChapterContentDao contentDao;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    bookDao = BookDao(db);
    chapterDao = ChapterDao(db);
    bookmarkDao = BookmarkDao(db);
    highlightDao = HighlightDao(db);
    contentDao = ReaderChapterContentDao(db);
    documents = await Directory.systemTemp.createTemp('local_book_docs');
    picked = await Directory.systemTemp.createTemp('local_book_picked');
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _DirPathProvider(documents.path);
    addTearDown(() => PathProviderPlatform.instance = previous);
  });

  tearDown(() async {
    await LocalBookService().closeOpenFile();
    await documents.delete(recursive: true);
    await picked.delete(recursive: true);
  });

  Future<String> pick(String name, String content) async {
    final file = File(p.join(picked.path, name));
    await file.writeAsString(content);
    return file.path;
  }

  test('選到的檔案複製進 App 的本地書資料夾，原檔刪了也讀得到', () async {
    final source = await pick('書.txt', '第一章\n內容');
    final (path: stored, :created) = await LocalBookService().storeInLibrary(
      source,
      bookDao: bookDao,
    );
    expect(created, isTrue);

    expect(p.dirname(stored), p.join(documents.path, 'InkpageBooks'));
    expect(p.basename(stored), '書.txt');
    await File(source).delete();
    expect(await File(stored).readAsString(), '第一章\n內容');
  });

  test('同名同內容視為同一本，同名不同內容（大小一樣也算）另取名字', () async {
    Future<String> store(String path) async =>
        (await LocalBookService().storeInLibrary(path, bookDao: bookDao)).path;
    final first = await store(await pick('書.txt', '甲'));
    final again = await store(await pick('書.txt', '甲'));
    final other = await store(await pick('書.txt', '乙'));

    expect(again, first);
    expect(p.basename(other), '書 (2).txt');
    expect(await File(other).readAsString(), '乙');
    expect(await store(other), other);
  });

  test('同名不同內容的第二本：書名作者照選的檔名拆，「 (2)」接在書名後面', () async {
    Future<String> add(String content) async {
      final book = await LocalBookService().addToShelf(
        await pick('The Hobbit by Tolkien.txt', content),
        bookDao: bookDao,
        chapterDao: chapterDao,
      );
      return '${book!.name}／${book.author}';
    }

    expect(await add('第一章 甲\n內容'), 'The Hobbit／Tolkien');
    expect(await add('第一章 乙\n內容'), 'The Hobbit (2)／Tolkien');
  });

  group('再匯入同名、同格式、內容不同的檔（L12）', () {
    String body(String marker) => '　　$marker${'正文內容。' * 300}\n';
    final v1 = '第一章 開始\n${body('甲')}第二章 中間\n${body('乙')}';
    final v2 =
        '序\n第一章 開始\n${body('甲')}第二章 中間\n${body('乙')}'
        '第三章 新的\n${body('丙')}';

    test('問了選更新：更新同一本，目錄換新、閱讀進度照章名留在同一章', () async {
      final first = (await LocalBookService().addToShelf(
        await pick('連載.txt', v1),
        bookDao: bookDao,
        chapterDao: chapterDao,
      ))!;
      await bookDao.updateProgress(first.bookUrl, 1, '第二章 中間', 42);
      await contentDao.saveContent(
        contentKey: ReaderChapterContentDao.contentKey(
          origin: first.origin,
          bookUrl: first.bookUrl,
          chapterUrl: '${first.bookUrl}#1',
        ),
        origin: first.origin,
        bookUrl: first.bookUrl,
        chapterUrl: '${first.bookUrl}#1',
        chapterIndex: 1,
        content: '舊的正文',
        updatedAt: 1,
      );
      Book? asked;

      final updated = await LocalBookService().addToShelf(
        await pick('連載.txt', v2),
        bookDao: bookDao,
        chapterDao: chapterDao,
        contentDao: contentDao,
        askUpdate: (existing) async {
          asked = existing;
          return true;
        },
      );

      expect(asked?.bookUrl, first.bookUrl);
      expect(updated!.bookUrl, first.bookUrl);
      expect(await bookDao.getInBookshelf(), hasLength(1));
      final chapters = await chapterDao.getByBook(first.bookUrl);
      expect(chapters.map((c) => c.title), [
        '前言',
        '第一章 開始',
        '第二章 中間',
        '第三章 新的',
      ]);
      final saved = (await bookDao.getByUrl(first.bookUrl))!;
      expect(saved.name, first.name);
      expect(saved.chapterIndex, 2);
      expect(saved.durChapterTitle, '第二章 中間');
      expect(saved.charOffset, 42);
      expect(saved.totalChapterNum, 4);
      expect(saved.fileFingerprint, isNot(first.fileFingerprint));
      expect(
        await LocalBookService().getContent(saved, chapters.last),
        startsWith('第三章 新的'),
      );
      expect(
        await contentDao.getStoredChapterUrls(
          origin: first.origin,
          bookUrl: first.bookUrl,
        ),
        isEmpty,
        reason: '舊檔存著的正文要清掉',
      );
    });

    test('選另加一本：照舊多一本「書名 (2)」', () async {
      await LocalBookService().addToShelf(
        await pick('連載.txt', v1),
        bookDao: bookDao,
        chapterDao: chapterDao,
      );
      final other = await LocalBookService().addToShelf(
        await pick('連載.txt', v2),
        bookDao: bookDao,
        chapterDao: chapterDao,
        askUpdate: (_) async => false,
      );

      expect(other!.name, '連載 (2)');
      expect(await bookDao.getInBookshelf(), hasLength(2));
    });

    test('新檔分不出章時放回舊檔，書與目錄都不動', () async {
      final first = (await LocalBookService().addToShelf(
        await pick('連載.txt', v1),
        bookDao: bookDao,
        chapterDao: chapterDao,
      ))!;

      await expectLater(
        LocalBookService().addToShelf(
          await pick('連載.txt', ''),
          bookDao: bookDao,
          chapterDao: chapterDao,
          askUpdate: (_) async => true,
        ),
        throwsA(isA<Exception>()),
      );

      expect(await File(LocalBookService.filePathOf(first)).readAsString(), v1);
      expect((await chapterDao.getByBook(first.bookUrl)).map((c) => c.title), [
        '第一章 開始',
        '第二章 中間',
      ]);
      expect(
        (await bookDao.getByUrl(first.bookUrl))!.fileFingerprint,
        first.fileFingerprint,
      );
    });

    test('書名不同、格式不同或同一個檔都不問', () async {
      var asked = 0;
      Future<bool> ask(Book _) async {
        asked += 1;
        return true;
      }

      await LocalBookService().addToShelf(
        await pick('連載.txt', v1),
        bookDao: bookDao,
        chapterDao: chapterDao,
      );
      await LocalBookService().addToShelf(
        await pick('連載.txt', v1),
        bookDao: bookDao,
        chapterDao: chapterDao,
        askUpdate: ask,
      );
      await LocalBookService().addToShelf(
        await pick('另一本.txt', v2),
        bookDao: bookDao,
        chapterDao: chapterDao,
        askUpdate: ask,
      );

      expect(asked, 0);
      expect(await bookDao.getInBookshelf(), hasLength(2));
    });
  });

  test('匯入本地 TXT 時寫入總章數，書卡的進度線算得出來', () async {
    final source = await pick('書.txt', '第一章 開始\n內容\n第二章 結束\n內容');
    final book = await LocalBookService().addToShelf(
      source,
      bookDao: bookDao,
      chapterDao: chapterDao,
    );

    expect(book, isNotNull);
    final saved = await bookDao.getByUrl(book!.bookUrl);
    expect(saved!.totalChapterNum, 2);
  });

  test('手動改編碼：重新解碼分章，閱讀進度、書籤與標註留在同一章', () async {
    final dir = await Directory.systemTemp.createTemp('local_book_charset');
    addTearDown(() async {
      await LocalBookService().closeOpenFile();
      await dir.delete(recursive: true);
    });
    final file = File(p.join(dir.path, '書.txt'));
    String body(String marker) => '　　$marker${'正文內容。' * 4000}\n';
    final text =
        '第一章 開始\n${body('甲')}'
        '第二章 結束\n${body('乙')}'
        '第三章 後來\n${body('丙')}';
    await file.writeAsBytes(EncodingDetect.encodeWithCharset(text, 'UTF-16LE'));

    // 模擬認錯編碼的書：整本照大端序解、分不出章，只照字數切。
    final wrong = await TxtParser(file).splitChapters(charset: 'UTF-16BE');
    expect(wrong.chapters.length, greaterThan(1));
    final book = Book(
      bookUrl: 'local://${file.path}',
      origin: 'local',
      originName: '本地',
      name: '書',
      author: '本地',
      isInBookshelf: true,
      charset: 'UTF-16BE',
    );
    final wrongChapters = LocalBookService().chaptersOf(book, [
      for (final chapter in wrong.chapters)
        (
          title: chapter['title'] as String,
          start: chapter['start'] as int,
          end: chapter['end'] as int,
        ),
    ]);
    await bookDao.upsert(book);
    await chapterDao.insertChapters(wrongChapters);

    // 讀到亂碼那一塊的中間，留一個書籤與一個標註。
    final oldIndex = 1;
    final oldChapter = wrongChapters[oldIndex];
    final oldText = EncodingDetect.decodeWithCharset(
      (await file.readAsBytes()).sublist(oldChapter.start!, oldChapter.end!),
      'UTF-16BE',
    );
    final oldOffset = oldText.length ~/ 6;
    await bookDao.updateProgress(
      book.bookUrl,
      oldIndex,
      oldChapter.title,
      oldOffset,
      readerAnchorJson: '{"chapterIndex":$oldIndex}',
    );
    // 舊編碼讀過的正文：改好編碼後不能留在正文表裡。
    final oldContentUrl = '${book.bookUrl}#0';
    await contentDao.saveContent(
      contentKey: ReaderChapterContentDao.contentKey(
        origin: book.origin,
        bookUrl: book.bookUrl,
        chapterUrl: oldContentUrl,
      ),
      origin: book.origin,
      bookUrl: book.bookUrl,
      chapterUrl: oldContentUrl,
      chapterIndex: 0,
      content: '舊編碼的亂碼正文',
      updatedAt: 1,
    );
    final bookmark = await bookmarkDao.add(
      Bookmark(
        id: 0,
        bookName: book.name,
        bookAuthor: book.author,
        chapterIndex: oldIndex,
        chapterTitle: oldChapter.title,
        charOffset: oldOffset,
        anchor: '{"chapterIndex":$oldIndex}',
        excerpt: '亂碼的一句',
      ),
    );
    final highlight = await highlightDao.add(
      Highlight(
        id: 0,
        bookName: book.name,
        bookAuthor: book.author,
        chapterIndex: oldIndex,
        chapterTitle: oldChapter.title,
        charOffset: oldOffset,
        anchor: '{"chapterIndex":$oldIndex}',
        quote: '亂碼',
      ),
    );

    final service = LocalBookService();
    final updated = await service.changeCharset(
      (await bookDao.getByUrl(book.bookUrl))!,
      'UTF-16LE',
      bookDao: bookDao,
      chapterDao: chapterDao,
      bookmarkDao: bookmarkDao,
      highlightDao: highlightDao,
      contentDao: contentDao,
    );

    expect(updated, isNotNull);
    expect(updated!.charset, 'UTF-16LE');
    expect(updated.readerAnchorJson, isNull);
    expect(
      await contentDao.getStoredChapterUrls(
        origin: book.origin,
        bookUrl: book.bookUrl,
      ),
      isEmpty,
      reason: '舊編碼存著的正文要清掉',
    );
    final chapters = await chapterDao.getByBook(book.bookUrl);
    expect(chapters.map((c) => c.title), ['第一章 開始', '第二章 結束', '第三章 後來']);
    // 第二塊的起點在整本的中段，落在「第二章 結束」裡；章內位置照比例
    // 落在同一段附近。
    expect(updated.chapterIndex, 1);
    expect(updated.durChapterTitle, '第二章 結束');
    expect(updated.charOffset, greaterThan(0));
    expect(updated.charOffset, lessThan(60000));

    final savedBookmark =
        (await bookmarkDao.watchByBook(book.name, book.author).first).single;
    expect(savedBookmark.id, bookmark.id);
    expect(savedBookmark.chapterIndex, updated.chapterIndex);
    expect(savedBookmark.chapterTitle, '第二章 結束');
    expect(savedBookmark.charOffset, updated.charOffset);
    expect(savedBookmark.anchor, isNull);

    final savedHighlight =
        (await highlightDao.watchByBook(book.name, book.author).first).single;
    expect(savedHighlight.id, highlight.id);
    expect(savedHighlight.chapterIndex, updated.chapterIndex);
    expect(savedHighlight.chapterTitle, '第二章 結束');
    expect(savedHighlight.charOffset, updated.charOffset);
    expect(savedHighlight.anchor, isNull);
  });

  test('改編碼後章內位置照新章裡的位元組位置重算，不會用舊章的比例跳到一半', () async {
    final dir = await Directory.systemTemp.createTemp(
      'local_book_charset_ratio',
    );
    addTearDown(() async {
      await LocalBookService().closeOpenFile();
      await dir.delete(recursive: true);
    });
    final file = File(p.join(dir.path, '書.txt'));
    const chapterLength = 7500;
    String chapter(String title) {
      final bodyLength = chapterLength - title.length - 2;
      return '$title\n${'字' * bodyLength}\n';
    }

    final text = [
      chapter('第一章 開始'),
      chapter('第二章 中間'),
      chapter('第三章 轉折'),
      chapter('第四章 結束'),
    ].join();
    expect(text.length, chapterLength * 4);
    await file.writeAsBytes(EncodingDetect.encodeWithCharset(text, 'UTF-16LE'));

    // 正確編碼的新目錄：四章，每章 7500 個字（UTF-16 一個字 2 位元組）。
    final correct = await TxtParser(file).splitChapters(charset: 'UTF-16LE');
    expect(correct.chapters.map((c) => c['title']), [
      '第一章 開始',
      '第二章 中間',
      '第三章 轉折',
      '第四章 結束',
    ]);
    final thirdStart = correct.chapters[2]['start'] as int;
    expect(thirdStart, chapterLength * 2 * 2);

    // 模擬認錯編碼：整本照大端序解成一個 3 萬字的「正文」。
    final wrong = await TxtParser(file).splitChapters(charset: 'UTF-16BE');
    expect(wrong.chapters, hasLength(1));
    expect(wrong.chapters.single['title'], '正文');
    final book = Book(
      bookUrl: 'local://${file.path}',
      origin: 'local',
      originName: '本地',
      name: '書',
      author: '本地',
      isInBookshelf: true,
      charset: 'UTF-16BE',
    );
    final wrongChapters = LocalBookService().chaptersOf(book, [
      (
        title: wrong.chapters.single['title'] as String,
        start: wrong.chapters.single['start'] as int,
        end: wrong.chapters.single['end'] as int,
      ),
    ]);
    await bookDao.upsert(book);
    await chapterDao.insertChapters(wrongChapters);

    // 讀到舊章（整本）的一半：位元組位置剛好是新目錄第三章的開頭。
    final oldOffset = thirdStart ~/ 2;
    expect(oldOffset, chapterLength * 2);
    await bookDao.updateProgress(book.bookUrl, 0, '正文', oldOffset);
    final bookmark = await bookmarkDao.add(
      Bookmark(
        id: 0,
        bookName: book.name,
        bookAuthor: book.author,
        chapterIndex: 0,
        chapterTitle: '正文',
        charOffset: oldOffset,
        excerpt: '一半的地方',
      ),
    );

    final updated = await LocalBookService().changeCharset(
      (await bookDao.getByUrl(book.bookUrl))!,
      'UTF-16LE',
      bookDao: bookDao,
      chapterDao: chapterDao,
      bookmarkDao: bookmarkDao,
    );

    expect(updated!.chapterIndex, 2);
    expect(updated.durChapterTitle, '第三章 轉折');
    expect(updated.totalChapterNum, 4);
    // 位元組位置在第三章的開頭，章內位置要接近 0，不是舊比例的 7500÷2。
    expect(updated.charOffset, lessThan(10));
    final savedBookmark =
        (await bookmarkDao.watchByBook(book.name, book.author).first).single;
    expect(savedBookmark.id, bookmark.id);
    expect(savedBookmark.chapterIndex, 2);
    expect(savedBookmark.chapterTitle, '第三章 轉折');
    expect(savedBookmark.charOffset, updated.charOffset);
  });

  test('書籤與標註記的是顯示章名（繁簡轉換後）時，照章名對回舊目錄再換算', () async {
    final dir = await Directory.systemTemp.createTemp(
      'local_book_charset_titles',
    );
    addTearDown(() async {
      await LocalBookService().closeOpenFile();
      await dir.delete(recursive: true);
    });
    final file = File(p.join(dir.path, '書.txt'));
    const chapterLength = 7500;
    String chapter(String title) {
      final bodyLength = chapterLength - title.length - 2;
      return '$title\n${'字' * bodyLength}\n';
    }

    final text = [
      chapter('第一章 开始'),
      chapter('第二章 中间'),
      chapter('第三章 后来'),
      chapter('第四章 结束'),
    ].join();
    await file.writeAsBytes(EncodingDetect.encodeWithCharset(text, 'UTF-16LE'));
    final book = Book(
      bookUrl: 'local://${file.path}',
      origin: 'local',
      originName: '本地',
      name: '書',
      author: '本地',
      isInBookshelf: true,
      charset: 'UTF-16LE',
    );
    final parsed = await TxtParser(file).splitChapters(charset: 'UTF-16LE');
    final chapters = LocalBookService().chaptersOf(book, [
      for (final chapter in parsed.chapters)
        (
          title: chapter['title'] as String,
          start: chapter['start'] as int,
          end: chapter['end'] as int,
        ),
    ]);
    await bookDao.upsert(book);
    await chapterDao.insertChapters(chapters);

    // 開著簡轉繁時留下的書籤記「第三章 後來」；另一筆記原始章名。
    final displayed = await bookmarkDao.add(
      Bookmark(
        id: 0,
        bookName: book.name,
        bookAuthor: book.author,
        chapterIndex: 2,
        chapterTitle: '第三章 後來',
        charOffset: 1000,
        anchor: '{"chapterIndex":2}',
        excerpt: '顯示章名的一句',
      ),
    );
    final original = await bookmarkDao.add(
      Bookmark(
        id: 0,
        bookName: book.name,
        bookAuthor: book.author,
        chapterIndex: 2,
        chapterTitle: '第三章 后来',
        charOffset: 1000,
        anchor: '{"chapterIndex":2}',
        excerpt: '原始章名的一句',
      ),
    );

    final updated = await LocalBookService().changeCharset(
      (await bookDao.getByUrl(book.bookUrl))!,
      'UTF-16BE',
      bookDao: bookDao,
      chapterDao: chapterDao,
      bookmarkDao: bookmarkDao,
    );

    expect(updated!.chapterIndex, 0);
    final saved = await bookmarkDao.watchByBook(book.name, book.author).first;
    expect(
      saved.map((item) => item.id),
      containsAll([displayed.id, original.id]),
    );
    for (final item in saved) {
      expect(item.chapterIndex, 0, reason: '「${item.chapterTitle}」沒有被搬到新目錄');
      expect(item.chapterTitle, '正文');
      expect(item.anchor, isNull);
    }
    // 兩筆在同一個位置：都照同一個位元組位置換算，落在同一個新位置。
    expect(saved.map((item) => item.charOffset).toSet(), hasLength(1));
    expect(saved.first.charOffset, greaterThan(0));
  });
}
