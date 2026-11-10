import 'package:night_reader/core/services/sleep_timer.dart';
import 'package:night_reader/core/constant/prefer_key.dart';

import 'dart:async';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/source_type.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/engine/web_book/audio_url_resolver.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/system_playback/system_playback.dart';
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
    engine.finish();
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
