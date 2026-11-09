import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/source_type.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/engine/web_book/audio_url_resolver.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/features/audiobook/audio_engine.dart';
import 'package:night_reader/features/audiobook/audiobook_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 假的播放引擎：記下開了哪一集、停在哪裡，測試自己推進播放。
class _Engine implements AudioEngine {
  final _playing = StreamController<bool>.broadcast(sync: true);
  final _position = StreamController<Duration>.broadcast(sync: true);
  final _duration = StreamController<Duration?>.broadcast(sync: true);
  final _buffering = StreamController<bool>.broadcast(sync: true);
  final _completed = StreamController<void>.broadcast(sync: true);
  final _errors = StreamController<Object>.broadcast(sync: true);

  final List<(Uri, Duration)> opened = [];
  Map<String, String> lastHeaders = const {};
  double lastSpeed = 1;

  @override
  bool playing = false;

  @override
  Duration position = Duration.zero;

  @override
  Duration? duration;

  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration?> get durationStream => _duration.stream;
  @override
  Stream<bool> get bufferingStream => _buffering.stream;
  @override
  Stream<void> get completedStream => _completed.stream;
  @override
  Stream<Object> get errorStream => _errors.stream;

  @override
  Future<void> open(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration start = Duration.zero,
  }) async {
    opened.add((uri, start));
    lastHeaders = headers;
    position = start;
    duration = const Duration(minutes: 20);
  }

  void _setPlaying(bool value) {
    playing = value;
    _playing.add(value);
  }

  @override
  Future<void> play() async => _setPlaying(true);

  @override
  Future<void> pause() async => _setPlaying(false);

  @override
  Future<void> seek(Duration to) async => position = to;

  @override
  Future<void> setSpeed(double speed) async => lastSpeed = speed;

  @override
  Future<void> stop() async => _setPlaying(false);

  @override
  Future<void> dispose() async {}

  /// 播到 [at]。
  void advance(Duration at) {
    position = at;
    _position.add(at);
  }

  /// 這一集播完。
  void finish() {
    _setPlaying(false);
    _completed.add(null);
  }
}

/// 書源：每一集的音訊網址是「章節網址.mp3」，帶一個 Referer 標頭。
class _Source extends BookSourceService {
  final List<String> resolved = [];

  @override
  Future<AudioRequest> getAudioRequest(
    BookSource source,
    Book book,
    BookChapter chapter, {
    CancelToken? cancelToken,
  }) async {
    resolved.add(chapter.url);
    return AudioRequest(
      url: '${chapter.url}.mp3',
      headers: const {'Referer': 'https://audio.test/'},
    );
  }
}

class _Sync extends Fake implements SyncService {
  final List<String> opened = [];
  final List<String> closed = [];

  @override
  Future<void>? get progressReady => null;

  @override
  void openBook(Book book) => opened.add(book.bookUrl);

  @override
  void closeBook(Book book) => closed.add(book.bookUrl);

  @override
  void requestSyncProgressFirst() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BookDao bookDao;
  late _Engine engine;
  late _Source source;
  late _Sync sync;
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
    engine = _Engine();
    source = _Source();
    sync = _Sync();
    player = AudiobookPlayer(
      engine: () => engine,
      bookDao: bookDao,
      chapterDao: chapterDao,
      sourceDao: sourceDao,
      sourceService: source,
      sync: sync,
      session: () async => null,
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

  test('音訊網址取正文第一個非空行，去掉縮排', () {
    expect(
      AudioUrlResolver.firstUrl('\n　　https://a.test/1.mp3\n　　x'),
      'https://a.test/1.mp3',
    );
    expect(AudioUrlResolver.firstUrl('  \n'), '');
  });
}
