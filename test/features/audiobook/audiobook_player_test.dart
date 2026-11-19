import 'package:night_reader/core/playback/sleep_timer.dart';
import 'package:night_reader/core/constant/prefer_key.dart';

import 'dart:async';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/source_type.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/engine/web_book/audio_url_resolver.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/storage/books_in_use.dart';
import 'package:night_reader/core/playback/system_playback.dart';
import 'package:night_reader/core/sync/progress_sync.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/features/audiobook/audiobook_player.dart';

import 'audiobook_test_doubles.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BookDao bookDao;
  late FakeAudioEngine engine;
  late FakeAudioSourceService source;
  late FakeSync sync;
  late RecordingPlayback playback;
  late AudiobookPlayer player;
  late Book book;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bookDao = BookDao(db);
    final sourceDao = BookSourceDao(db);
    final chapterDao = ChapterDao(db);
    await sourceDao.upsert(
      BookSource(
        bookSourceUrl: 'https://audio.test',
        bookSourceName: '聽書',
        bookSourceType: SourceType.audio,
      ),
    );
    book = Book(
      bookUrl: 'https://audio.test/book/1',
      origin: 'https://audio.test',
      name: '長夜將盡',
      author: '沈墨',
      type: SourceType.audio,
      chapterIndex: 2,
      charOffset: 95000,
      durChapterTitle: '第 2 集',
    );
    await bookDao.upsert(book);
    await chapterDao.insertChapters([
      BookChapter(
        url: 'https://audio.test/vol',
        title: '第一卷',
        isVolume: true,
        bookUrl: book.bookUrl,
        index: 0,
      ),
      for (var i = 1; i <= 3; i++)
        BookChapter(
          url: 'https://audio.test/ep$i',
          title: '第 $i 集',
          bookUrl: book.bookUrl,
          index: i,
        ),
    ]);
    engine = FakeAudioEngine();
    source = FakeAudioSourceService();
    sync = FakeSync();
    playback = RecordingPlayback();
    player = AudiobookPlayer(
      engine: () => engine,
      bookDao: bookDao,
      chapterDao: chapterDao,
      sourceDao: sourceDao,
      sourceService: source,
      sync: sync,
      playback: playback,
      random: Random(1),
    );
  });

  tearDown(() async {
    // 背景存進度做完才關資料庫。
    await pumpEventQueue();
    player.dispose();
    await db.close();
  });

  Future<Book> stored() async => (await bookDao.getByUrl(book.bookUrl))!;

  test('接著上次聽的那一集與毫秒開始播，帶書源的標頭', () async {
    await player.open(book);

    expect(engine.opened.single.$1.toString(), 'https://audio.test/ep2.mp3');
    expect(engine.opened.single.$2, const Duration(milliseconds: 95000));
    expect(engine.lastHeaders, {'Referer': 'https://audio.test/'});
    expect(player.playing, isTrue);
    expect(player.chapterIndex, 2);
    expect(sync.opened, [book.bookUrl]);
  });

  test('開書還沒讀到目錄時，畫面問有沒有上一集、下一集不會出錯', () async {
    // 開書先通知畫面「載入中」，這時目錄還是空的、集數已經是上次聽的那集；
    // 資料庫在另一個 isolate，回覆前畫面會照這個狀態畫一幀播放鈕。
    final errors = <Object>[];
    player.addListener(() {
      try {
        player.hasPrevious;
        player.hasNext;
      } catch (error) {
        errors.add(error);
      }
    });

    await player.open(book);

    expect(errors, isEmpty);
    expect(player.hasPrevious, isTrue);
  });

  /// 書架上另一本有聲書，資料庫裡沒有目錄：開書要向書源抓（[source] 的
  /// `chapterList` 放行）。
  Future<Book> bookWithoutChapters() async {
    final other = book.copyWith(
      bookUrl: 'https://audio.test/book/2',
      name: '另一本',
      chapterIndex: 5,
      charOffset: 0,
    );
    await bookDao.upsert(other);
    return other;
  }

  test('列表循環時目錄還在抓，不算有下一集，按下一集也不出錯', () async {
    while (player.mode != AudiobookPlayMode.listLoop) {
      player.cycleMode();
    }
    final other = await bookWithoutChapters();
    source.chapterList = Completer();
    final opening = player.open(other);
    await pumpEventQueue();
    expect(player.chapters, isEmpty);

    expect(player.hasNext, isFalse);
    await player.next();

    source.chapterList!.complete([
      for (var i = 0; i <= 6; i++)
        BookChapter(
          url: 'https://audio.test/b2/ep$i',
          title: '第 $i 集',
          bookUrl: other.bookUrl,
          index: i,
        ),
    ]);
    await opening;
    expect(player.chapterIndex, 5);
  });

  test('抓不到目錄之後按播放、回到前景，都不出錯', () async {
    // 先播過一本：播放引擎已經在了，播放鍵才會走到重載這一集。
    await player.open(book);
    final other = await bookWithoutChapters();
    source.chapterList = Completer()..complete(null);
    await player.open(other);
    expect(player.error, isNotNull);
    expect(player.chapters, isEmpty);

    await player.play();

    // 另一台聽到較新的地方：沒有目錄跳不過去，不記成同步過。
    sync.pulled = PulledProgress(
      SyncedProgress(
        chapterIndex: 3,
        charOffset: 1000,
        chapterTitle: '第 3 集',
        time: 1,
      ),
      (_) async => sync.commits++,
    );
    final binding = TestWidgetsFlutterBinding.instance;
    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(sync.commits, 0);
  });

  test('打不開時按播放鍵或收聽圓鈕就是重試', () async {
    // 第一次開書就打不開：播放引擎還沒建起來。
    final other = await bookWithoutChapters();
    source.chapterList = Completer()..complete(null);
    await player.open(other);
    expect(player.phase, AudiobookPhase.openFailed);

    source.chapterList = Completer()
      ..complete([
        for (var i = 0; i <= 6; i++)
          BookChapter(
            url: 'https://audio.test/b2/ep$i',
            title: '第 $i 集',
            bookUrl: other.bookUrl,
            index: i,
          ),
      ]);
    await player.toggle();
    await pumpEventQueue();

    expect(player.chapters, hasLength(7));
    expect(engine.opened.last.$1.toString(), 'https://audio.test/b2/ep5.mp3');
    expect(player.playing, isTrue);
  });

  test('播著的書算開著，停了才放掉：播的時候不自動換源（ADR 0069）', () async {
    // 開著時換了源，之後存的收聽進度寫不到換過去的那本。
    await player.open(book);
    expect(BooksInUse.bookUrls, contains(book.bookUrl));

    await player.stop();
    expect(BooksInUse.bookUrls, isNot(contains(book.bookUrl)));
  });

  test('收聽時間只算出聲的時間，記在有聲書自己的名下（ADR 0055）', () async {
    var now = DateTime(2026, 11, 9, 20);
    final records = ReadRecordDao(db);
    final timed = AudiobookPlayer(
      engine: () => engine,
      bookDao: bookDao,
      chapterDao: ChapterDao(db),
      sourceDao: BookSourceDao(db),
      sourceService: source,
      sync: sync,
      playback: playback,
      random: Random(1),
      now: () => now,
      readRecordDao: records,
    );

    await timed.open(book);
    now = now.add(const Duration(seconds: 90));
    await timed.pause();
    now = now.add(const Duration(minutes: 5));
    await timed.play();
    now = now.add(const Duration(seconds: 30));
    await timed.stop();

    final days = await records.getAllDays();
    expect(days.single.bookName, book.recordName);
    expect(book.recordName, isNot(book.name));
    expect(days.single.seconds, 120);
  });

  test('載入中按了暫停，載入完不自己開始播', () async {
    source.gate = Completer<void>();
    final opening = player.open(book);
    await Future<void>.delayed(Duration.zero);
    while (source.resolved.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await player.pause();
    source.gate!.complete();
    await opening;

    expect(player.playing, isFalse);
    expect(engine.playing, isFalse);
  });

  test('載入中按播放只記下要出聲，不讓還沒換掉的上一集出聲，載好才播', () async {
    await player.open(book);
    await pumpEventQueue();
    source.gate = Completer<void>();
    final switching = player.playChapter(1);
    await pumpEventQueue();
    await player.play();
    expect(engine.playing, isFalse);
    source.gate!.complete();
    await switching;
    expect(engine.opened.last.$1.toString(), 'https://audio.test/ep1.mp3');
    expect(engine.playing, isTrue);

    // 開別本書、還在讀目錄時也一樣：引擎停著的是上一本。
    final other = await bookWithoutChapters();
    source.chapterList = Completer();
    final opening = player.open(other);
    await pumpEventQueue();
    await player.play();
    expect(engine.playing, isFalse);
    source.chapterList!.complete([
      for (var i = 0; i <= 6; i++)
        BookChapter(
          url: 'https://audio.test/b2/ep$i',
          title: '第 $i 集',
          bookUrl: other.bookUrl,
          index: i,
        ),
    ]);
    await opening;
    expect(engine.opened.last.$1.toString(), 'https://audio.test/b2/ep5.mp3');
    expect(engine.playing, isTrue);
  });

  test('按了下一集、上一集還沒停聲時停止：換集不再往下做', () async {
    await player.open(book, chapterIndex: 1);
    await pumpEventQueue();
    engine.pauseGate = Completer<void>();
    final switching = player.next();
    await pumpEventQueue();
    await player.stop();
    engine.pauseGate!.complete();
    await switching;

    expect(player.book, isNull);
    expect(engine.opened, hasLength(1));
  });

  test('按了下一集、上一集還沒停聲時開了別本：不換到別本的同一集', () async {
    await player.open(book, chapterIndex: 1);
    await pumpEventQueue();
    final other = await bookWithoutChapters();
    source.chapterList = Completer()
      ..complete([
        for (var i = 0; i <= 6; i++)
          BookChapter(
            url: 'https://audio.test/b2/ep$i',
            title: '第 $i 集',
            bookUrl: other.bookUrl,
            index: i,
          ),
      ]);
    engine.pauseGate = Completer<void>();
    final switching = player.next();
    await pumpEventQueue();
    final opening = player.open(other);
    await pumpEventQueue();
    engine.pauseGate!.complete();
    await switching;
    await opening;
    await pumpEventQueue();

    expect(player.chapterIndex, 5);
    expect(engine.opened.last.$1.toString(), 'https://audio.test/b2/ep5.mp3');
  });

  test('開書中按了暫停：開好不自己播', () async {
    final other = await bookWithoutChapters();
    source.chapterList = Completer();
    final opening = player.open(other);
    await pumpEventQueue();
    await player.pause();
    source.chapterList!.complete([
      for (var i = 0; i <= 6; i++)
        BookChapter(
          url: 'https://audio.test/b2/ep$i',
          title: '第 $i 集',
          bookUrl: other.bookUrl,
          index: i,
        ),
    ]);
    await opening;

    expect(player.phase, AudiobookPhase.paused);
    expect(engine.playing, isFalse);
  });

  test('按了暫停之後才報播完：接下一集但不出聲', () async {
    await player.open(book, chapterIndex: 1);
    await pumpEventQueue();
    await player.pause();
    final opening = engine.nextOpen;
    engine.finish();
    await opening.timeout(const Duration(seconds: 5));
    await pumpEventQueue();

    expect(player.chapterIndex, 2);
    expect(engine.playing, isFalse);
  });

  test('回到前景接另一台的進度、還在載入時按播放：載好就播', () async {
    await player.open(book);
    await player.pause();
    sync.pulled = PulledProgress(
      SyncedProgress(
        chapterIndex: 1,
        charOffset: 1000,
        chapterTitle: '第 1 集',
        time: 1,
      ),
      (_) async => sync.commits++,
    );
    source.gate = Completer<void>();
    final binding = TestWidgetsFlutterBinding.instance;
    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(player.phase, AudiobookPhase.loading);
    await player.play();
    final opening = engine.nextOpen;
    source.gate!.complete();
    await opening.timeout(const Duration(seconds: 5));
    await pumpEventQueue();

    expect(player.chapterIndex, 1);
    expect(engine.playing, isTrue);
  });

  test('換到抓不到的一集時，上一集也停聲，不會畫面停在新集、還聽著舊集', () async {
    await player.open(book);
    expect(engine.playing, isTrue);
    source.failing.add('https://audio.test/ep3');

    await player.playChapter(3);

    expect(player.error, isNotNull);
    expect(player.playing, isFalse);
    expect(engine.playing, isFalse);
  });

  test('播放途中出錯：停下、記下原因，按播放重新載入這一集', () async {
    await player.open(book);
    engine.fail(StateError('斷線'));
    await Future<void>.delayed(Duration.zero);
    expect(player.error, isNotNull);
    expect(engine.playing, isFalse);

    await player.play();
    expect(engine.opened, hasLength(2));
    expect(player.playing, isTrue);
  });

  test('從目錄點正在播的那一集：從頭播', () async {
    await player.open(book);
    engine.advance(const Duration(minutes: 2));
    await player.open(book, chapterIndex: 2);

    expect(engine.opened.last.$2, Duration.zero);
    expect(player.playing, isTrue);
  });

  test('定時記得上次選的；緩衝沒有聲音時不倒數', () async {
    SharedPreferences.setMockInitialValues({PreferKey.ttsTimer: 15});
    var now = DateTime(2026, 11, 10, 22);
    final timed = AudiobookPlayer(
      engine: () => engine,
      bookDao: bookDao,
      chapterDao: ChapterDao(db),
      sourceDao: BookSourceDao(db),
      sourceService: source,
      sync: sync,
      playback: playback,
      random: Random(1),
      now: () => now,
    );
    await timed.open(book);
    expect(timed.sleepTimer.option, SleepTimerOption.minutes15);

    engine.buffer(true);
    now = now.add(const Duration(minutes: 5));
    expect(timed.sleepTimer.remaining, const Duration(minutes: 15));
    engine.buffer(false);
    now = now.add(const Duration(minutes: 1));
    expect(timed.sleepTimer.remaining, const Duration(minutes: 14));
    await timed.stop();
  });

  test('暫停時把位置以毫秒存進閱讀進度', () async {
    await player.open(book);
    engine.advance(const Duration(minutes: 3, seconds: 7));
    await player.pause();

    final saved = await stored();
    expect(saved.chapterIndex, 2);
    expect(saved.durChapterTitle, '第 2 集');
    expect(saved.charOffset, 187000);
  });

  test('一集播完接著播下一集，最後一集播完停在結尾', () async {
    await player.open(book);
    final opening = engine.nextOpen;
    engine.finish();
    await opening.timeout(const Duration(seconds: 5));
    await pumpEventQueue();

    expect(player.chapterIndex, 3);
    expect(engine.opened.last.$1.toString(), 'https://audio.test/ep3.mp3');
    expect(engine.opened.last.$2, Duration.zero);
    expect(player.playing, isTrue);

    engine.finish();
    await pumpEventQueue();
    expect(player.chapterIndex, 3);
    expect(engine.opened, hasLength(2));
    expect(player.playing, isFalse);

    // 再按播放：從這一集開頭重播。
    await player.play();
    expect(engine.opened.last.$2, Duration.zero);
    expect(player.playing, isTrue);
  });

  test('最後一集播完後拖回去再按播放：從拖到的地方接著播', () async {
    await player.open(book, chapterIndex: 3);
    engine.finish();
    await pumpEventQueue();
    expect(player.phase, AudiobookPhase.ended);

    await player.seek(const Duration(minutes: 5));
    expect(player.phase, AudiobookPhase.paused);
    await player.play();

    expect(engine.opened, hasLength(1));
    expect(engine.position, const Duration(minutes: 5));
    expect(player.playing, isTrue);
  });

  test('最後一集播完後拖回去、引擎還沒拖好就按播放：不從開頭重播', () async {
    await player.open(book, chapterIndex: 3);
    engine.finish();
    await pumpEventQueue();
    engine.seekGate = Completer<void>();
    final seeking = player.seek(const Duration(minutes: 5));
    await pumpEventQueue();
    final playing = player.play();
    engine.seekGate!.complete();
    await seeking;
    await playing;

    expect(engine.opened, hasLength(1));
    expect(engine.position, const Duration(minutes: 5));
    expect(player.playing, isTrue);
  });

  test('換集抓網址時拖動不算數：不把拖到的位置記到新的一集', () async {
    await player.open(book);
    await pumpEventQueue();
    source.gate = Completer<void>();
    final switching = player.playChapter(1);
    await pumpEventQueue();
    player.onSeek(const Duration(minutes: 7));
    await pumpEventQueue();
    source.gate!.complete();
    await switching;
    await pumpEventQueue();

    expect(player.position.value, Duration.zero);
    expect((await stored()).chapterIndex, 1);
    expect((await stored()).charOffset, 0);
  });

  test('付費的集跳過，不問書源；後面都是付費的就停在結尾（ADR 0057）', () async {
    await ChapterDao(db).insertChapters([
      BookChapter(
        url: 'https://audio.test/ep3',
        title: '第 3 集',
        bookUrl: book.bookUrl,
        index: 3,
        isVip: true,
      ),
    ]);
    await player.open(book);
    engine.finish();
    await pumpEventQueue();

    expect(player.chapterIndex, 2);
    expect(engine.opened, hasLength(1));
    expect(player.playing, isFalse);
  });

  test('單集循環播完從頭再播同一集', () async {
    await player.open(book);
    player.cycleMode();
    expect(player.mode, AudiobookPlayMode.singleLoop);
    engine.advance(const Duration(minutes: 20));
    engine.finish();
    await pumpEventQueue();

    expect(player.chapterIndex, 2);
    expect(engine.position, Duration.zero);
    expect(player.playing, isTrue);
  });

  test('單集循環播完、還沒重播前按了暫停：不再出聲', () async {
    await player.open(book);
    player.cycleMode();
    expect(player.mode, AudiobookPlayMode.singleLoop);
    engine.finish();
    await player.pause();
    await pumpEventQueue();

    expect(engine.playing, isFalse);
    expect(player.playing, isFalse);
  });

  test('隨機播放只剩這一集時播完、還沒重播前按了暫停：不再出聲', () async {
    await ChapterDao(db).insertChapters([
      for (final i in [1, 3])
        BookChapter(
          url: 'https://audio.test/ep$i',
          title: '第 $i 集',
          bookUrl: book.bookUrl,
          index: i,
          isVip: true,
        ),
    ]);
    await player.open(book);
    while (player.mode != AudiobookPlayMode.shuffle) {
      player.cycleMode();
    }
    engine.finish();
    await player.pause();
    await pumpEventQueue();

    expect(engine.playing, isFalse);
    expect(player.playing, isFalse);
  });

  test('列表循環在最後一集之後回到第一集，跳過分卷標題', () async {
    await player.open(book, chapterIndex: 3);
    player
      ..cycleMode()
      ..cycleMode()
      ..cycleMode();
    expect(player.mode, AudiobookPlayMode.listLoop);
    engine.finish();
    await pumpEventQueue();

    expect(player.chapterIndex, 1);
  });

  test('上一集停在第一集；分卷標題不當成一集', () async {
    await player.open(book, chapterIndex: 1);
    await player.previous();
    expect(player.chapterIndex, 1);
    await player.next();
    expect(player.chapterIndex, 2);
    await player.previous();
    expect(player.chapterIndex, 1);
  });

  test('倒退與快轉不超出這一集的頭尾', () async {
    await player.open(book, chapterIndex: 1);
    await player.skipBy(-AudiobookPlayer.skipStep);
    expect(engine.position, Duration.zero);
    engine.advance(const Duration(minutes: 19, seconds: 55));
    await player.skipBy(AudiobookPlayer.skipStep);
    expect(engine.position, const Duration(minutes: 20));
  });

  test('先解析好下一集，換集時不再問書源', () async {
    await player.open(book, chapterIndex: 1);
    await pumpEventQueue();
    expect(source.resolved, [
      'https://audio.test/ep1',
      'https://audio.test/ep2',
    ]);

    await player.next();
    expect(source.resolved, hasLength(3));
    expect(source.resolved.last, 'https://audio.test/ep3');
    expect(engine.opened.last.$1.toString(), 'https://audio.test/ep2.mp3');
  });

  test('停止後存好進度、交還同步，書不再是正在播', () async {
    await player.open(book);
    engine.advance(const Duration(seconds: 42));
    await player.stop();

    expect(player.book, isNull);
    expect(sync.closed, [book.bookUrl]);
    expect((await stored()).charOffset, 42000);
  });

  test('倍速套用到之後的每一集', () async {
    await player.open(book, chapterIndex: 1);
    await player.setSpeed(1.5);
    await player.next();
    expect(engine.lastSpeed, 1.5);
  });

  test('開書讀目錄、換集抓網址時都算載入中，載好就不是', () async {
    final other = await bookWithoutChapters();
    source.chapterList = Completer();
    final opening = player.open(other);
    await pumpEventQueue();
    expect(player.loading, isTrue);
    expect(player.playing, isFalse);
    source.chapterList!.complete([
      for (var i = 0; i <= 6; i++)
        BookChapter(
          url: 'https://audio.test/b2/ep$i',
          title: '第 $i 集',
          bookUrl: other.bookUrl,
          index: i,
        ),
    ]);
    await opening;
    await pumpEventQueue();
    expect(player.loading, isFalse);
    expect(player.playing, isTrue);

    // 換到沒預先解析的那一集，抓網址要等書源。
    source.gate = Completer<void>();
    final switching = player.playChapter(1);
    await pumpEventQueue();
    expect(player.loading, isTrue);
    expect(player.playing, isFalse);
    source.gate!.complete();
    await switching;
    expect(player.loading, isFalse);
    expect(player.playing, isTrue);
  });

  test('緩衝時播放鍵轉圈、系統播放資訊寫等資料，不算出聲', () async {
    await player.open(book);
    expect(playback.buffering, isFalse);

    engine.buffer(true);
    expect(player.loading, isTrue);
    expect(player.playing, isTrue);
    expect(playback.buffering, isTrue);
    expect(playback.playing, isTrue);

    engine.buffer(false);
    expect(player.loading, isFalse);
    expect(playback.buffering, isFalse);
  });

  test('換集抓網址時，系統播放資訊停在上一集、暫停；載好換成新的一集', () async {
    await player.open(book);
    await pumpEventQueue();
    source.gate = Completer<void>();
    final switching = player.playChapter(1);
    await pumpEventQueue();
    expect(playback.item?.title, '第 2 集');
    expect(playback.playing, isFalse);

    source.gate!.complete();
    await switching;
    expect(playback.item?.title, '第 1 集');
    expect(playback.playing, isTrue);
  });

  test('最後一集播完、換集失敗時，系統播放資訊是暫停', () async {
    await player.open(book, chapterIndex: 3);
    engine.finish();
    await pumpEventQueue();
    expect(playback.item?.title, '第 3 集');
    expect(playback.playing, isFalse);

    source.failing.add('https://audio.test/ep1');
    await player.playChapter(1);
    expect(player.error, isNotNull);
    expect(playback.playing, isFalse);
  });

  test('抓網址時引擎送來上一集的錯：不算這一集的，照樣載好播', () async {
    await player.open(book);
    await pumpEventQueue();
    source.gate = Completer<void>();
    final switching = player.playChapter(1);
    await pumpEventQueue();
    engine.fail(StateError('斷線'));
    expect(player.error, isNull);
    source.gate!.complete();
    await switching;

    expect(engine.opened.last.$1.toString(), 'https://audio.test/ep1.mp3');
    expect(player.playing, isTrue);
    expect(player.error, isNull);
  });

  test('回到前景時暫停中：另一台聽到別集，跳過去停著、記成同步過', () async {
    await player.open(book);
    await player.pause();
    sync.pulled = PulledProgress(
      SyncedProgress(
        chapterIndex: 3,
        charOffset: 1000,
        chapterTitle: '第 3 集',
        time: 1,
      ),
      (_) async => sync.commits++,
    );
    final opening = engine.nextOpen;
    final binding = TestWidgetsFlutterBinding.instance;
    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await opening.timeout(const Duration(seconds: 5));
    await pumpEventQueue();

    expect(player.chapterIndex, 3);
    expect(player.position.value, const Duration(milliseconds: 1000));
    expect(engine.opened.last.$2, const Duration(milliseconds: 1000));
    expect(player.playing, isFalse);
    expect(engine.playing, isFalse);
    expect(sync.commits, 1);
  });

  test('回到前景接進度的途中按播放重載失敗的那一集：照按的播，不接另一台', () async {
    await player.open(book);
    engine.fail(StateError('斷線'));
    await pumpEventQueue();
    expect(player.phase, AudiobookPhase.failed);

    sync
      ..pulled = PulledProgress(
        SyncedProgress(
          chapterIndex: 3,
          charOffset: 1000,
          chapterTitle: '第 3 集',
          time: 1,
        ),
        (_) async => sync.commits++,
      )
      ..pullGate = Completer<void>();
    final binding = TestWidgetsFlutterBinding.instance;
    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpEventQueue();

    // 重載要等書源給網址；這段時間另一台的進度回來了。
    source.gate = Completer<void>();
    final reloading = player.play();
    await pumpEventQueue();
    sync.pullGate!.complete();
    await pumpEventQueue();
    source.gate!.complete();
    await reloading;
    await pumpEventQueue();

    expect(player.chapterIndex, 2);
    expect(player.playing, isTrue);
    expect(sync.commits, 0);
  });

  test('回到前景接進度的途中按播放、還在等系統接手：照按的播，不接另一台', () async {
    await player.open(book);
    await player.pause();
    sync
      ..pulled = PulledProgress(
        SyncedProgress(
          chapterIndex: 3,
          charOffset: 1000,
          chapterTitle: '第 3 集',
          time: 1,
        ),
        (_) async => sync.commits++,
      )
      ..pullGate = Completer<void>();
    final binding = TestWidgetsFlutterBinding.instance;
    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpEventQueue();

    playback.startGate = Completer<void>();
    final playing = player.play();
    await pumpEventQueue();
    sync.pullGate!.complete();
    await pumpEventQueue();
    playback.startGate!.complete();
    await playing;
    await pumpEventQueue();

    expect(player.chapterIndex, 2);
    expect(player.playing, isTrue);
    expect(sync.commits, 0);
  });

  group('系統播放資訊', () {
    test('開始播就接手：原本在播的暫停，交出集名、副標、總長與五顆按鈕', () async {
      final other = OtherPlaybackOwner();
      playback.show(
        other,
        item: const NowPlaying(
          id: 'tts',
          title: '第一章',
          bookName: '小說',
          author: '',
        ),
        playing: true,
        controls: const {},
      );

      await player.open(book, chapterIndex: 2);

      expect(other.pauses, 1);
      expect(playback.item?.title, '第 2 集');
      expect(playback.item?.subtitle, '${book.name} · ${book.author}');
      expect(playback.item?.duration, const Duration(minutes: 20));
      // 沒有封面時通知畫有聲書的預設封面。
      expect(playback.item?.kind, BookSourceKind.audio);
      expect(playback.playing, isTrue);
      expect(playback.controls, {
        PlaybackControl.skipToPrevious,
        PlaybackControl.rewind,
        PlaybackControl.fastForward,
        PlaybackControl.skipToNext,
        PlaybackControl.seek,
      });
    });

    test('第一集沒有上一集，最後一集沒有下一集（列表循環才有）', () async {
      await player.open(book, chapterIndex: 1);
      expect(
        playback.controls,
        isNot(contains(PlaybackControl.skipToPrevious)),
      );

      await player.playChapter(3);
      expect(playback.controls, isNot(contains(PlaybackControl.skipToNext)));

      while (player.mode != AudiobookPlayMode.listLoop) {
        player.cycleMode();
      }
      expect(playback.controls, contains(PlaybackControl.skipToNext));
    });

    test('系統的倒退、快轉與拖動照播放器的跳法，暫停時交出停的位置', () async {
      await player.open(book, chapterIndex: 1);
      engine.advance(const Duration(minutes: 1));

      player.onRewind();
      await pumpEventQueue();
      expect(engine.position, const Duration(seconds: 50));
      player.onFastForward();
      await pumpEventQueue();
      expect(engine.position, const Duration(minutes: 1));
      player.onSeek(const Duration(minutes: 5));
      await pumpEventQueue();
      expect(engine.position, const Duration(minutes: 5));

      player.onPause();
      await pumpEventQueue();
      expect(playback.playing, isFalse);
      expect(playback.position, const Duration(minutes: 5));
    });

    test('停止就收掉系統播放資訊', () async {
      await player.open(book);
      player.onStop();
      await pumpEventQueue();
      expect(player.book, isNull);
      expect(playback.item, isNull);
    });
  });

  test('音訊網址取正文第一個非空行，去掉縮排', () {
    expect(
      AudioUrlResolver.firstUrl('\n　　https://a.test/1.mp3\n　　x'),
      'https://a.test/1.mp3',
    );
    expect(AudioUrlResolver.firstUrl('  \n'), '');
  });
}
