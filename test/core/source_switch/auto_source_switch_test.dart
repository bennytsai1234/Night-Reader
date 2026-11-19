import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/source_switch/auto_source_switch.dart';
import 'package:night_reader/core/background_work/background_work.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/core/source_switch/source_switch_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 每個書源的網站：搜得到《夜雨》，目錄是第 1 到 10 章。[searches] 記下
/// 搜了哪些書源；[gate] 給了就等它完成才回搜尋結果（模擬搜很久）。
class _Sites extends BookSourceService {
  final List<String> searches = [];
  Completer<void>? gate;

  @override
  Future<List<SearchBook>> searchBooks(
    BookSource source,
    String key, {
    int page = 1,
    bool Function(String name, String author)? filter,
    bool Function(int size)? shouldBreak,
    CancelToken? cancelToken,
  }) async {
    searches.add(source.bookSourceUrl);
    await gate?.future;
    return [
      SearchBook(
        bookUrl: '${source.bookSourceUrl}/book',
        name: key,
        author: '作者',
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
  }) async => book;

  @override
  Future<List<BookChapter>> getChapterList(
    BookSource source,
    Book book, {
    int? chapterLimit,
    int? pageConcurrency,
    CancelToken? cancelToken,
    bool requireComplete = false,
  }) async => _toc(book.bookUrl);

  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async => '這是一段足夠長的章節正文內容，用來通過可讀性檢查。';
}

List<BookChapter> _toc(String bookUrl) => [
  for (var i = 0; i < 10; i++)
    BookChapter(
      url: '$bookUrl/c$i',
      title: '第${i + 1}章',
      bookUrl: bookUrl,
      index: i,
    ),
];

class _OtherJob implements BackgroundJob {
  @override
  void pauseFromSystem() {}

  @override
  void endFromSystem() {}

  @override
  void openFromNotification() {}
}

Book _book(String origin, {String name = '夜雨', bool shelf = true}) => Book(
  bookUrl: '$origin/$name',
  origin: origin,
  originName: origin,
  name: name,
  author: '作者',
  chapterIndex: 5,
  durChapterTitle: '第6章',
  totalChapterNum: 10,
  isInBookshelf: shelf,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _Sites sites;
  late BackgroundWork work;
  late Set<String> inUse;
  late StreamController<String> released;
  late List<String> downloads;
  late AutoSourceSwitch auto;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sites = _Sites();
    work = BackgroundWork(platform: null);
    inUse = {};
    released = StreamController<String>.broadcast();
    downloads = [];
    auto = AutoSourceSwitch(
      work: work,
      bookDao: db.bookDao,
      sourceDao: db.bookSourceDao,
      chapterDao: db.chapterDao,
      switcher: SourceSwitchService(
        service: sites,
        sourceDao: db.bookSourceDao,
      ),
      booksInUse: () => inUse,
      releasedBooks: released.stream,
      keepDownloaded: (bookUrl) async => downloads.add(bookUrl),
    )..listen();
    await db.bookSourceDao.upsertAll([
      BookSource(bookSourceUrl: 'old', bookSourceName: 'old'),
      BookSource(bookSourceUrl: 'new', bookSourceName: 'new'),
    ]);
  });

  tearDown(() async {
    await auto.dispose();
    await released.close();
    await db.close();
  });

  Future<void> shelve(Book book) async {
    await db.bookDao.upsert(book);
    await db.chapterDao.insertChapters(_toc(book.bookUrl));
  }

  /// 等這一輪換完（背景工作的位置空出來）。
  Future<void> settled() async {
    for (var i = 0; i < 500; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      if (!work.isBusy) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (!work.isBusy) return;
      }
    }
    fail('自動換源沒有結束');
  }

  Future<void> launched() async =>
      auto.onLaunchSettled(await SharedPreferences.getInstance());

  Future<List<Book>> shelf() => db.bookDao.getInBookshelf();

  test('a shelf book whose source is deleted moves to another source, '
      'keeping its place, and downloads from there', () async {
    await shelve(_book('old'));
    await shelve(_book('old', name: '別的書', shelf: false));
    await launched();
    final switched = AppEventBus().onName(AppEventBus.bookSwitched).first;

    await db.bookSourceDao.deleteByUrl('old');
    final event = (await switched).data as BookSwitchedEvent;
    await settled();

    expect(event.fromBookUrl, 'old/夜雨');
    final books = await shelf();
    expect(books.map((b) => (b.origin, b.chapterIndex, b.durChapterTitle)), [
      ('new', 5, '第6章'),
    ]);
    expect(downloads, [books.single.bookUrl]);
    expect(work.isBusy, isFalse);
  });

  test('nothing happens before the launch has settled', () async {
    await shelve(_book('old'));
    await db.bookSourceDao.deleteByUrl('old');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(sites.searches, isEmpty);

    await launched();
    await settled();
    expect((await shelf()).single.origin, 'new');
  });

  test(
    'a source that is back by the time its turn comes is left alone',
    () async {
      await launched();
      await shelve(_book('old'));
      await shelve(_book('gone'));
      sites.gate = Completer<void>();
      await db.bookSourceDao.upsert(
        BookSource(bookSourceUrl: 'gone', bookSourceName: 'gone'),
      );

      // 兩個一起刪，換第一本時把第二本的書源加回來。
      await db.bookSourceDao.deleteByUrls(['old', 'gone']);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await db.bookSourceDao.upsert(
        BookSource(bookSourceUrl: 'gone', bookSourceName: 'gone'),
      );
      sites.gate!.complete();
      await settled();

      final origins = {for (final book in await shelf()) book.origin};
      expect(origins, {'new', 'gone'});
    },
  );

  test('a book open in the reader waits until it is closed', () async {
    // 閱讀器手上還是舊的書，存進度時會把它寫回來。
    await launched();
    await shelve(_book('old'));
    inUse = {'old/夜雨'};

    await db.bookSourceDao.deleteByUrl('old');
    await settled();
    expect((await shelf()).single.origin, 'old');
    expect(sites.searches, isEmpty);

    inUse = {};
    released.add('old/夜雨');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await settled();
    expect((await shelf()).single.origin, 'new');
  });

  test(
    'another background job runs first; the switch waits behind it',
    () async {
      await launched();
      await shelve(_book('old'));
      final other = _OtherJob();
      work.begin(other, const BackgroundWorkStatus(title: '校驗書源', text: ''));

      await db.bookSourceDao.deleteByUrl('old');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sites.searches, isEmpty);
      expect(work.current, same(other));

      work.end(other);
      await settled();
      expect((await shelf()).single.origin, 'new');
    },
  );

  test('ending it drops the books not reached yet; they are not searched '
      'again', () async {
    await launched();
    await shelve(_book('old'));
    await shelve(_book('old', name: '第二本'));
    sites.gate = Completer<void>();

    await db.bookSourceDao.deleteByUrl('old');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(work.current, same(auto));
    auto.endFromSystem();
    sites.gate!.complete();
    await settled();

    expect({for (final book in await shelf()) book.origin}, {'old'});
    expect(sites.searches, ['new'], reason: '只搜了第一本');
  });

  test(
    'what changed on the book while its sources were searched is kept',
    () async {
      await launched();
      await shelve(_book('old'));
      sites.gate = Completer<void>();

      await db.bookSourceDao.deleteByUrl('old');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final book = (await db.bookDao.getByUrl('old/夜雨'))!;
      await db.bookDao.upsert(book.copyWith(group: 4, customIntro: '改過的簡介'));
      sites.gate!.complete();
      await settled();

      final switched = (await shelf()).single;
      expect(switched.origin, 'new');
      expect((switched.group, switched.customIntro), (4, '改過的簡介'));
    },
  );

  test('the chapter title changed while searching, at the same index: a new '
      'source without that chapter is not switched to', () async {
    // 搜的時候同步把讀到的那一章改成「番外」（位置還是第 6 章）：新書源
    // 沒有這一章，對不到章名就不換（ADR 0069），不能因為照比例估出同一個
    // 位置就沿用驗證過「第6章」的候選。
    await launched();
    await shelve(_book('old'));
    sites.gate = Completer<void>();

    await db.bookSourceDao.deleteByUrl('old');
    // 等它照「第6章」開始搜了才改，測到的是搜完重對的那一段。
    for (var i = 0; i < 500 && sites.searches.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(sites.searches, isNotEmpty);
    final book = (await db.bookDao.getByUrl('old/夜雨'))!;
    await db.bookDao.upsert(book.copyWith(durChapterTitle: '番外'));
    sites.gate!.complete();
    await settled();

    final kept = (await shelf()).single;
    expect(kept.origin, 'old');
    expect((kept.chapterIndex, kept.durChapterTitle), (5, '番外'));
  });

  test(
    'a book already on the shelf from the new source is not overwritten',
    () async {
      // 換過去會蓋掉那本的進度、書架少一本：兩本都留著。
      await launched();
      await shelve(_book('old'));
      await shelve(_book('new').copyWith(bookUrl: 'new/book', chapterIndex: 8));

      await db.bookSourceDao.deleteByUrl('old');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await settled();

      final books = {for (final b in await shelf()) b.bookUrl: b.chapterIndex};
      expect(books, {'old/夜雨': 5, 'new/book': 8});
    },
  );

  test('books that had no source before this version are searched once, on '
      'the first launch', () async {
    await shelve(_book('missing'));
    await launched();
    await settled();
    expect((await shelf()).single.origin, isNot('missing'));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PreferKey.orphanedBooksSwitched), isTrue);

    await shelve(_book('missing', name: '後來的書'));
    sites.searches.clear();
    await launched();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(sites.searches, isEmpty);
  });
}
