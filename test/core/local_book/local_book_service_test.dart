import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/local_book/local_book_formats.dart';
import 'package:night_reader/core/local_book/local_book_service.dart';
import 'package:night_reader/core/local_book/txt_parser.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/reading/bookmark.dart';
import 'package:night_reader/core/models/reading/highlight.dart';
import 'package:night_reader/core/storage/books_in_use.dart';
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

    Future<Book> addV1({String name = '連載.txt', String? content}) async =>
        (await LocalBookService().addToShelf(
          await pick(name, content ?? v1),
          bookDao: bookDao,
          chapterDao: chapterDao,
        ))!;

    Future<Book?> update(String content, {String name = '連載.txt'}) async =>
        LocalBookService().addToShelf(
          await pick(name, content),
          bookDao: bookDao,
          chapterDao: chapterDao,
          askUpdate: (_) async => true,
        );

    test('換到一半 App 被關掉：資料庫還沒寫的退回舊檔，寫好了的收尾成新檔', () async {
      for (final (step, committed) in [
        ('prepared', false),
        ('swapped', false),
        ('committed', true),
      ]) {
        // 每一輪的內容不同：同一份內容是同一本書（原檔指紋相同）。
        final old = '$v1$step\n';
        final next = '$v2$step\n';
        final first = await addV1(name: '$step.txt', content: old);
        final target = LocalBookService.filePathOf(first);
        LocalBookService.debugUpdateStep = (at) async {
          if (at == step) throw LocalBookUpdateInterrupted();
        };
        addTearDown(() => LocalBookService.debugUpdateStep = null);

        await expectLater(
          update(next, name: '$step.txt'),
          throwsA(isA<LocalBookUpdateInterrupted>()),
        );
        LocalBookService.debugUpdateStep = null;
        await LocalBookService.recoverInterruptedUpdates(bookDao);

        final saved = (await bookDao.getByUrl(first.bookUrl))!;
        final chapters = await chapterDao.getByBook(first.bookUrl);
        expect(
          await File(target).readAsString(),
          committed ? next : old,
          reason: step,
        );
        expect(chapters, hasLength(committed ? 4 : 2), reason: step);
        expect(
          saved.fileFingerprint == first.fileFingerprint,
          !committed,
          reason: step,
        );
        // 讀得出來的就是資料庫記的那一章。
        expect(
          await LocalBookService().getContent(saved, chapters.last),
          startsWith(chapters.last.title),
          reason: step,
        );
        final leftovers = Directory(p.dirname(target))
            .listSync()
            .map((f) => p.basename(f.path))
            .where(
              (name) =>
                  name.startsWith(p.basename(target)) &&
                  name != p.basename(target),
            );
        expect(leftovers, isEmpty, reason: '$step：暫存的新舊檔與紀錄都清掉');
      }
    });

    test('這本書正開著時不更新、也不問，提示先關掉', () async {
      final first = await addV1();
      final open = BooksInUse.hold(first.bookUrl);
      addTearDown(open.release);
      var asked = false;

      await expectLater(
        LocalBookService().addToShelf(
          await pick('連載.txt', v2),
          bookDao: bookDao,
          chapterDao: chapterDao,
          askUpdate: (_) async => asked = true,
        ),
        throwsA(
          isA<LocalBookContentException>().having(
            (e) => e.message,
            'message',
            '《連載》正開著，關掉後再加入一次',
          ),
        ),
      );
      expect(asked, isFalse);
      expect(await File(LocalBookService.filePathOf(first)).readAsString(), v1);
    });

    test('讀者手動改過編碼的，新檔照那個編碼讀；沒改過的照新檔自動偵測', () async {
      String text(String extra) =>
          '第一章 開始\n${body('甲')}第二章 中間\n${body('乙')}$extra';
      Future<String> pickBytes(String name, List<int> bytes) async {
        final file = File(p.join(picked.path, name));
        await file.writeAsBytes(bytes);
        return file.path;
      }

      // 手動改過：沒有 BOM 的 UTF-16LE 自動偵測會認成大端，讀者改成 UTF-16LE。
      final manual = (await LocalBookService().addToShelf(
        await pickBytes(
          '手動.txt',
          EncodingDetect.encodeWithCharset(text(''), 'UTF-16LE'),
        ),
        bookDao: bookDao,
        chapterDao: chapterDao,
      ))!;
      expect(manual.charset, 'UTF-16BE');
      await LocalBookService().changeCharset(
        manual,
        'UTF-16LE',
        bookDao: bookDao,
        chapterDao: chapterDao,
      );
      final manualUpdated = await LocalBookService().addToShelf(
        await pickBytes(
          '手動.txt',
          EncodingDetect.encodeWithCharset(
            text('第三章 新的\n${body('丙')}'),
            'UTF-16LE',
          ),
        ),
        bookDao: bookDao,
        chapterDao: chapterDao,
        askUpdate: (_) async => true,
      );
      expect(manualUpdated!.charset, 'UTF-16LE');
      expect((await chapterDao.getByBook(manual.bookUrl)).map((c) => c.title), [
        '第一章 開始',
        '第二章 中間',
        '第三章 新的',
      ]);

      // 沒改過：舊檔 GBK、新檔換成 UTF-8，照新檔偵測。
      final auto = (await LocalBookService().addToShelf(
        await pickBytes(
          '自動.txt',
          EncodingDetect.encodeWithCharset(text(''), 'GBK'),
        ),
        bookDao: bookDao,
        chapterDao: chapterDao,
      ))!;
      final autoUpdated = await LocalBookService().addToShelf(
        await pick('自動.txt', text('第三章 新的\n${body('丙')}')),
        bookDao: bookDao,
        chapterDao: chapterDao,
        askUpdate: (_) async => true,
      );
      expect(autoUpdated!.charset, isNot(auto.charset));
      expect((await chapterDao.getByBook(auto.bookUrl)).map((c) => c.title), [
        '第一章 開始',
        '第二章 中間',
        '第三章 新的',
      ]);
    });

    test('書架上有兩本同名同格式的書時不問，照舊另加一本', () async {
      await addV1();
      await LocalBookService().addToShelf(
        await pick('連載.txt', '第一章 別本\n${body('丁')}'),
        bookDao: bookDao,
        chapterDao: chapterDao,
      );
      // 第二本是「連載 (2)」；改名成同名，模擬讀者自己改過。
      final second = (await bookDao.getInBookshelf()).firstWhere(
        (b) => b.name != '連載',
      );
      await bookDao.upsert(second.copyWith(name: '連載'));
      var asked = false;

      final third = await LocalBookService().addToShelf(
        await pick('連載.txt', v2),
        bookDao: bookDao,
        chapterDao: chapterDao,
        askUpdate: (_) async => asked = true,
      );

      expect(asked, isFalse);
      expect(await bookDao.getInBookshelf(), hasLength(3));
      expect(third!.name, '連載 (3)');
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
          isVolume: false,
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

  test('改編碼後「前言」當成的簡介照新編碼重讀', () async {
    final file = File(p.join(picked.path, '簡介.txt'));
    await file.writeAsBytes(
      EncodingDetect.encodeWithCharset(
        '一段簡介。\n第一章 開始\n${'正文。' * 100}\n',
        'UTF-16LE',
      ),
    );
    final wrong = await TxtParser(file).splitChapters(charset: 'UTF-16BE');
    final book = Book(
      bookUrl: 'local://${file.path}',
      origin: 'local',
      originName: '本地',
      name: '簡介',
      author: '本地',
      isInBookshelf: true,
      charset: 'UTF-16BE',
      intro: wrong.intro,
    );
    await bookDao.upsert(book);
    await chapterDao.insertChapters(
      LocalBookService().chaptersOf(book, [
        for (final chapter in wrong.chapters)
          (
            title: chapter['title'] as String,
            start: chapter['start'] as int,
            end: chapter['end'] as int,
            isVolume: false,
          ),
      ]),
    );

    final updated = await LocalBookService().changeCharset(
      book,
      'UTF-16LE',
      bookDao: bookDao,
      chapterDao: chapterDao,
    );

    expect(updated!.intro, '一段簡介。');
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
        isVolume: false,
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
          isVolume: false,
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

  group('舊版分章規則切的 TXT，開書時照現在的規則重新分章', () {
    String body(String marker) => '　　$marker${'正文內容。' * 300}\n';
    // 全形數字的章名：舊版規則不認，整本切成一章。
    final text = '第１章 開始\n${body('甲')}第２章 中間\n${body('乙')}第３章 結尾\n${body('丙')}';

    /// 舊版匯入的書：資料庫裡整本只有一章，沒有記分章版本的檔。
    Future<Book> seedOld({String content = '', String name = '全形'}) async {
      final file = File(p.join(picked.path, '$name.txt'));
      await file.writeAsString(content.isEmpty ? text : content);
      final book = Book(
        bookUrl: 'local://${file.path}',
        origin: 'local',
        originName: '本地',
        name: name,
        author: '本地',
        isInBookshelf: true,
        charset: 'UTF-8',
        durChapterTitle: '正文',
        durChapterTime: 111,
        progressTime: 222,
        totalChapterNum: 1,
      );
      await bookDao.upsert(book);
      await chapterDao.insertChapters([
        BookChapter(
          url: '${book.bookUrl}#0',
          title: '正文',
          bookUrl: book.bookUrl,
          index: 0,
          start: 0,
          end: await file.length(),
        ),
      ]);
      return book;
    }

    Future<({List<BookChapter> chapters, TxtChapterRemap? remap})> ensure(
      Book book,
    ) => LocalBookService().ensureTxtChapters(
      book,
      bookDao: bookDao,
      chapterDao: chapterDao,
      bookmarkDao: bookmarkDao,
      highlightDao: highlightDao,
      contentDao: contentDao,
    );

    /// [book] 現在目錄第 [index] 章的正文。
    Future<String> chapterText(Book book, int index) async {
      final chapter = (await chapterDao.getByBook(book.bookUrl))[index];
      final bytes = await File(LocalBookService.filePathOf(book)).readAsBytes();
      return utf8.decode(bytes.sublist(chapter.start!, chapter.end!));
    }

    Future<List<LocalChapterRange>?> recorded(Book book) async =>
        readChapterRanges(
          await LocalBookService.txtChaptersPath(book),
          TxtParser.tocVersion,
        );

    test('目錄換新，進度、書籤與標註對到同一段字，正文清掉，時間不動', () async {
      final book = await seedOld();
      final atBing = text.indexOf('丙');
      final atYi = text.indexOf('乙');
      await bookDao.updateProgress(
        book.bookUrl,
        0,
        '正文',
        atBing,
        readerAnchorJson: '{"chapterIndex":0}',
      );
      final stored = (await bookDao.getByUrl(book.bookUrl))!;
      await bookmarkDao.add(
        Bookmark(
          id: 0,
          bookName: book.name,
          bookAuthor: book.author,
          chapterTitle: '正文',
          charOffset: atYi,
        ),
      );
      await highlightDao.add(
        Highlight(
          id: 0,
          bookName: book.name,
          bookAuthor: book.author,
          chapterTitle: '正文',
          charOffset: atBing,
          quote: '丙',
        ),
      );
      final contentUrl = '${book.bookUrl}#0';
      await contentDao.saveContent(
        contentKey: ReaderChapterContentDao.contentKey(
          origin: book.origin,
          bookUrl: book.bookUrl,
          chapterUrl: contentUrl,
        ),
        origin: book.origin,
        bookUrl: book.bookUrl,
        chapterUrl: contentUrl,
        chapterIndex: 0,
        content: '舊目錄讀過的正文',
        updatedAt: 1,
      );

      final result = await ensure(stored);

      expect(result.remap, isNotNull);
      expect(result.chapters.map((c) => c.title).skip(1), ['第２章 中間', '第３章 結尾']);
      final saved = (await bookDao.getByUrl(book.bookUrl))!;
      expect(saved.chapterIndex, 2);
      expect(saved.durChapterTitle, '第３章 結尾');
      final third = await chapterText(book, 2);
      expect(saved.charOffset, closeTo(third.indexOf('丙'), 2));
      expect(saved.readerAnchorJson, isNull);
      expect(saved.totalChapterNum, 3);
      expect(saved.durChapterTime, stored.durChapterTime, reason: '不是讀者讀了');
      expect(saved.progressTime, stored.progressTime, reason: '不算比另一台新的進度');
      // 記憶體裡的書跟著換。
      expect(stored.chapterIndex, 2);
      expect(stored.charOffset, saved.charOffset);
      expect(stored.totalChapterNum, 3);

      final mark =
          (await bookmarkDao.watchByBook(book.name, book.author).first).single;
      expect(mark.chapterIndex, 1);
      expect(mark.chapterTitle, '第２章 中間');
      final second = await chapterText(book, 1);
      expect(mark.charOffset, closeTo(second.indexOf('乙'), 2));
      final note =
          (await highlightDao.watchByBook(book.name, book.author).first).single;
      expect(note.chapterIndex, 2);
      expect(note.charOffset, closeTo(third.indexOf('丙'), 2));

      expect(
        await contentDao.getStoredChapterUrls(
          origin: book.origin,
          bookUrl: book.bookUrl,
        ),
        isEmpty,
      );
      expect(await recorded(book), hasLength(3));
    });

    test('沒有記版本、但目錄和現在的規則切的一樣：不換，只記下版本', () async {
      final file = File(p.join(picked.path, '新.txt'));
      await file.writeAsString(text);
      final split = await TxtParser(file).splitChapters();
      final book = Book(
        bookUrl: 'local://${file.path}',
        origin: 'local',
        name: '新',
        author: '本地',
        isInBookshelf: true,
        charset: split.charset,
        chapterIndex: 1,
        charOffset: 7,
      );
      final chapters = LocalBookService().chaptersOf(book, [
        for (final chapter in split.chapters)
          (
            title: chapter['title'] as String,
            start: chapter['start'] as int,
            end: chapter['end'] as int,
            isVolume: chapter['isVolume'] == true,
          ),
      ]);
      await bookDao.upsert(book);
      await chapterDao.insertChapters(chapters);

      final result = await ensure(book);

      expect(result.remap, isNull);
      expect(
        LocalBookService.chaptersMatch(result.chapters, [
          for (final c in chapters)
            (
              title: c.title,
              start: c.start!,
              end: c.end!,
              isVolume: c.isVolume,
            ),
        ]),
        isTrue,
      );
      final saved = (await bookDao.getByUrl(book.bookUrl))!;
      expect(saved.chapterIndex, 1);
      expect(saved.charOffset, 7);
      expect(await recorded(book), hasLength(chapters.length));
    });

    test('記下的版本與範圍都對上：不再讀原檔分章', () async {
      final book = await seedOld();
      await ensure(book);
      final before = await chapterDao.getByBook(book.bookUrl);
      // 原檔換成切法完全不同的內容：要是又讀原檔分章，目錄就會變。
      await File(LocalBookService.filePathOf(book))
          .writeAsString('第１章 只有一章\n${body('丁')}');
      LocalBookService().forgetTxtChapterChecks();

      final result = await ensure((await bookDao.getByUrl(book.bookUrl))!);

      expect(result.remap, isNull);
      expect(
        (await chapterDao.getByBook(book.bookUrl)).map((c) => c.title),
        before.map((c) => c.title),
      );
    });

    test('同時對兩次只分一次章；對好之後才來的拿結果，不改它手上的書', () async {
      final book = await seedOld();
      final again = book.copyWith();

      final results = await Future.wait([ensure(book), ensure(again)]);

      expect(results[0].remap, isNotNull);
      expect(identical(results[0].remap, results[1].remap), isTrue);
      expect(again.chapterIndex, book.chapterIndex);
      expect(LocalBookService().txtChaptersChecked(book), isTrue);

      // 對好之後讀了幾章，再拿一次：同一份結果，不把位置改回對好當時的。
      final later = (await bookDao.getByUrl(book.bookUrl))!..chapterIndex = 2;
      final third = await ensure(later);
      expect(identical(third.remap, results[0].remap), isTrue);
      expect(later.chapterIndex, 2);
    });

    test('原檔不在這台：照原樣回傳，不丟錯，也不記成對過', () async {
      final book = await seedOld();
      await File(LocalBookService.filePathOf(book)).delete();

      final result = await ensure(book);

      expect(result.remap, isNull);
      expect(result.chapters.single.title, '正文');
      expect(LocalBookService().txtChaptersChecked(book), isFalse);
      expect(
        await LocalBookService().txtChaptersCurrent(book, result.chapters),
        isTrue,
        reason: '沒有原檔可以重新分章，背景同步照舊套進度',
      );
    });

    test('匯入與改編碼時記下分章版本，背景同步看得出目錄是現在的', () async {
      final added = await LocalBookService().addToShelf(
        await pick('匯入.txt', text),
        bookDao: bookDao,
        chapterDao: chapterDao,
      );
      final chapters = await chapterDao.getByBook(added!.bookUrl);
      expect(
        LocalBookService.chaptersMatch(chapters, (await recorded(added))!),
        isTrue,
      );
      expect(
        await LocalBookService().txtChaptersCurrent(added, chapters),
        isTrue,
      );

      final old = await seedOld(name: '舊');
      final oldChapters = await chapterDao.getByBook(old.bookUrl);
      expect(
        await LocalBookService().txtChaptersCurrent(old, oldChapters),
        isFalse,
      );

      await LocalBookService().changeCharset(
        old,
        'UTF-8',
        bookDao: bookDao,
        chapterDao: chapterDao,
      );
      final changed = await chapterDao.getByBook(old.bookUrl);
      expect(changed, hasLength(3));
      expect(await LocalBookService().txtChaptersCurrent(old, changed), isTrue);
    });
  });
}
