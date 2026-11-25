import 'dart:async';
import 'dart:io';

import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/chinese/chinese_display.dart';
import 'package:night_reader/core/chinese/chinese_utils.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/playback/now_playing_artwork.dart';
import 'package:night_reader/core/playback/system_playback.dart';
import 'package:night_reader/features/reader/chapter/reader_chapter_repository.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/reader/features/tts/reader_tts_controller.dart';
import 'package:night_reader/features/reader/features/tts/reader_tts_phase.dart';
import 'package:night_reader/core/playback/sleep_timer.dart';
import 'package:night_reader/features/reader/layout/reader_layout_spec.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';
import 'package:night_reader/features/reader/session/reader_progress_controller.dart';
import 'package:night_reader/features/reader/session/reader_runtime.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBookDao extends Fake implements BookDao {}

class _FakeChapterDao extends Fake implements ChapterDao {
  @override
  Future<int?> indexOfUrl(String bookUrl, String url) async => null;

  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) => action();
}

class _FakeSourceDao extends Fake implements BookSourceDao {}

/// 換掉 audio_service 的平台：記下系統實際收到的系統播放資訊。收掉時
/// 各欄是 null。
class _FakeAudioPlatform extends AudioServicePlatform {
  MediaItemMessage? _mediaItem;
  PlaybackStateMessage? _state;

  bool get _shown =>
      _state != null &&
      _state!.processingState != AudioProcessingStateMessage.idle;

  String? get title => _shown ? _mediaItem?.title : null;
  String? get subtitle => _shown ? _mediaItem?.artist : null;
  bool? get playing => _shown ? _state!.playing : null;

  /// 播放／暫停以外的按鈕。
  Set<PlaybackControl>? get controls => !_shown
      ? null
      : {for (final control in _state!.controls) ?_buttons[control.action]};

  static const _buttons = {
    MediaActionMessage.skipToPrevious: PlaybackControl.skipToPrevious,
    MediaActionMessage.skipToNext: PlaybackControl.skipToNext,
    MediaActionMessage.stop: PlaybackControl.stop,
  };

  @override
  void setHandlerCallbacks(AudioHandlerCallbacks callbacks) {}

  @override
  Future<void> configure(ConfigureRequest request) async {}

  @override
  Future<void> setState(SetStateRequest request) async =>
      _state = request.state;

  @override
  Future<void> setMediaItem(SetMediaItemRequest request) async =>
      _mediaItem = request.mediaItem;

  @override
  Future<void> setQueue(SetQueueRequest request) async {}

  @override
  Future<void> setAndroidPlaybackInfo(
    SetAndroidPlaybackInfoRequest request,
  ) async {}

  @override
  Future<void> stopService(StopServiceRequest request) async {}
}

/// 系統播放資訊開工作階段時建的圖片快取放在這裡。
class _TempPaths extends PathProviderPlatform {
  _TempPaths(this.path);

  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

/// 另一個在播的（例如之後的有聲書播放器）。
class _OtherOwner implements PlaybackOwner {
  int pauses = 0;

  @override
  void onPause() => pauses += 1;

  @override
  void onPlay() {}

  @override
  void onStop() {}

  @override
  void onSkipToNext() {}

  @override
  void onSkipToPrevious() {}

  @override
  void onSeek(Duration position) {}

  @override
  void onRewind() {}

  @override
  void onFastForward() {}
}

class _FakeTtsEngine extends ReaderTtsEngine {
  final StreamController<void> _completions =
      StreamController<void>.broadcast();
  final StreamController<void> _failures = StreamController<void>.broadcast();
  final List<String> spoken = <String>[];

  /// 有值時，下一次停止等第一個完成才停好（引擎回覆得慢）。
  final List<Completer<void>> stopGates = <Completer<void>>[];
  bool _playing = false;
  String _text = '';

  @override
  bool get isPlaying => _playing;

  @override
  double get rate => 1;

  @override
  double get pitch => 1;

  @override
  String? get language => null;

  @override
  String get currentSpokenText => _text;

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Stream<void> get failures => _failures.stream;

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    _text = text;
    _playing = true;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    if (stopGates.isNotEmpty) await stopGates.removeAt(0).future;
    _text = '';
    _playing = false;
    notifyListeners();
  }

  /// 引擎念完目前這句。
  void complete() {
    _text = '';
    _playing = false;
    _completions.add(null);
  }

  /// 引擎沒念出目前這句（出錯、不收）。
  void fail() {
    _text = '';
    _playing = false;
    _failures.add(null);
  }

  @override
  Future<void> setRate(double value) async {}

  @override
  Future<void> setPitch(double value) async {}

  @override
  Future<void> setLanguage(String value) async {}
}

void main() {
  late ReaderRuntime runtime;
  late _FakeTtsEngine engine;
  late ReaderTtsController tts;
  var now = DateTime(2026, 10, 15, 23);

  // audio_service 一個程序只能開一次工作階段：整個檔案共用一份真的系統播放
  // 資訊，看平台收到什麼。
  final system = _FakeAudioPlatform();
  late Directory tempDir;
  late SystemPlayback playback;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('tts_playback_');
    PathProviderPlatform.instance = _TempPaths(tempDir.path);
    AudioServicePlatform.instance = system;
    playback = SystemPlayback(
      artwork: NowPlayingArtwork(directory: () async => tempDir),
    );
    await playback.start();
  });
  tearDownAll(() => tempDir.deleteSync(recursive: true));

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// [gates] 裡的章節等它完成才載入好；[paid] 裡的是付費章節，和書源一樣
  /// 抓不到正文。
  Future<void> open(
    Map<int, String?> contents, {
    Map<int, String> titles = const {},
    Map<int, Completer<void>> gates = const {},
    Set<int> paid = const {},
  }) async {
    final book = Book(
      bookUrl: 'http://tts.test',
      name: '朗讀測試書',
      author: '作者',
      origin: 'local',
      originName: '本地',
    );
    final bookDao = _FakeBookDao();
    final repository = ReaderChapterRepository(
      book: book,
      initialChapters: [
        for (final index in contents.keys)
          BookChapter(
            url: 'chapter_$index',
            title: titles[index] ?? '',
            bookUrl: book.bookUrl,
            index: index,
            isVip: paid.contains(index),
          ),
      ],
      contentLoader: (index, _) async {
        await gates[index]?.future;
        final content = contents[index];
        if (paid.contains(index)) throw LockedChapterException();
        if (content == null) {
          throw const ReaderContentUnavailableException('暫時無法取得');
        }
        return content;
      },
      bookDao: bookDao,
      chapterDao: _FakeChapterDao(),
      sourceDao: _FakeSourceDao(),
    );
    runtime = ReaderRuntime(
      book: book,
      repository: repository,
      progressController: ReaderProgressController(
        book: book,
        repository: repository,
        bookDao: bookDao,
      ),
      initialLayoutSpec: ReaderLayoutSpec.fromViewport(
        viewportSize: const Size(400, 600),
        style: const ReaderLayoutStyle(
          fontSize: 18,
          lineHeight: 1.5,
          letterSpacing: 0,
          paragraphSpacing: 0.8,
          paddingTop: 12,
          paddingBottom: 12,
          paddingLeft: 12,
          paddingRight: 12,
        ),
      ),
      initialLocation: const ReaderLocation(chapterIndex: 0, charOffset: 0),
    );
    runtime.registerViewportRestore(Object(), (_) async => true);
    await runtime.openBook();
    engine = _FakeTtsEngine();
    tts = ReaderTtsController(
      runtime: runtime,
      tts: engine,
      playback: playback,
      now: () => now,
    );
  }

  /// 讓時間前進：同時推進測試的時鐘與定時器。
  Future<void> elapse(WidgetTester tester, Duration duration) async {
    now = now.add(duration);
    await tester.pump(duration);
  }

  tearDown(() {
    tts.dispose();
    engine.dispose();
    runtime.dispose();
  });

  void moveTo(int chapterIndex) {
    runtime.updateVisibleLocation(
      ReaderLocation(chapterIndex: chapterIndex, charOffset: 0),
    );
  }

  test('獨立成行的刪節號不發聲，接著念下一句', () async {
    const text = '第一句。\n\n......\n\n……\n\n下一句。';
    await open({0: text});
    await tts.startFromVisibleLocation();
    expect(engine.spoken, <String>['第一句。']);

    engine.complete();
    await pumpEventQueue();

    expect(engine.spoken, <String>['第一句。', '下一句。']);
    expect(tts.currentHighlight?.sentenceStart, text.indexOf('下一句'));
    expect(tts.currentHighlight?.sentenceEnd, text.length);
  });

  test('句中刪節號用停頓取代，原文高亮範圍不變', () async {
    const text = '他想了......接著說……好吧。';
    await open({0: text});
    await tts.startFromVisibleLocation();

    expect(engine.spoken, <String>['他想了，接著說，好吧。']);
    expect(tts.currentHighlight?.sentenceStart, 0);
    expect(tts.currentHighlight?.sentenceEnd, text.length);
  });

  test('整章只有刪節號時跳到下一章朗讀', () async {
    await open({0: '......\n……', 1: '第二章開始。'});
    await tts.startFromVisibleLocation();

    expect(engine.spoken, <String>['第二章開始。']);
    expect(tts.currentHighlight?.chapterIndex, 1);
  });

  test('a manual jump while reading continues from the new place', () async {
    await open({0: '第一章開頭。', 1: '第二章開頭。'});
    await tts.startFromVisibleLocation();
    expect(engine.spoken.last, '第一章開頭。');

    moveTo(1);
    await tts.followManualJump();

    expect(engine.spoken.last, '第二章開頭。');
    expect(tts.isPlaying, isTrue);
    expect(tts.currentHighlight?.chapterIndex, 1);
  });

  test(
    'a manual jump while paused makes play start at the new place',
    () async {
      await open({0: '第一章開頭。', 1: '第二章開頭。'});
      await tts.startFromVisibleLocation();
      await tts.toggle();
      expect(tts.phase, ReaderTtsPhase.paused);

      moveTo(1);
      await tts.followManualJump();
      expect(tts.phase, isNot(ReaderTtsPhase.paused));
      expect(tts.isPlaying, isFalse);

      await tts.toggle();
      expect(engine.spoken.last, '第二章開頭。');
    },
  );

  test(
    'starting in an empty chapter reads the next chapter with text',
    () async {
      await open({0: '', 1: '', 2: '第三章開頭。'});
      await tts.startFromVisibleLocation();

      expect(engine.spoken, ['第三章開頭。']);
    },
  );

  test('a chapter that fails to load stops reading and says so', () async {
    await open({0: '第一章。', 1: null, 2: '第三章。'});
    await tts.startFromVisibleLocation();
    engine.complete();
    await pumpEventQueue();

    expect(engine.spoken, ['第一章。']);
    expect(tts.currentHighlight, isNull);
    expect(runtime.takeUserNotice()?.message, '第 2 章無法載入，朗讀已結束');
  });

  test('finishing the last chapter says the book has ended', () async {
    await open({0: '唯一的一句。'});
    await tts.startFromVisibleLocation();
    engine.complete();
    await pumpEventQueue();

    expect(tts.currentHighlight, isNull);
    expect(runtime.takeUserNotice()?.message, '已朗讀到書尾');
  });

  group('reading on', () {
    test(
      'finishing a chapter reads on from the next one, the highlight and the '
      'system info follow',
      () async {
        await open({0: '第一句。', 1: '第二章開頭。'}, titles: {0: '第一章', 1: '第二章'});
        await tts.startFromVisibleLocation();
        engine.complete();
        await pumpEventQueue();
        expect(engine.spoken.last, '第一句。');
        expect(tts.currentHighlight?.chapterIndex, 0);

        engine.complete();
        await pumpEventQueue();
        expect(engine.spoken.last, '第二章');
        expect(tts.currentHighlight?.chapterIndex, 1);
        expect(tts.currentHighlight?.sentenceStart, 0);
        expect(tts.isPlaying, isTrue);
        expect(system.title, '第二章');
        expect(system.playing, isTrue);
      },
    );

    test('paid chapters ahead are skipped', () async {
      await open({0: '甲。', 1: null, 2: '丙。'}, paid: {1});
      await tts.startFromVisibleLocation();
      engine.complete();
      await pumpEventQueue();

      expect(engine.spoken, ['甲。', '丙。']);
      expect(tts.currentHighlight?.chapterIndex, 2);
    });

    test(
      'paid chapters after a chapter without text are skipped too',
      () async {
        await open({0: '甲。', 1: '', 2: null, 3: '丁。'}, paid: {2});
        await tts.startFromVisibleLocation();
        engine.complete();
        await pumpEventQueue();

        expect(engine.spoken, ['甲。', '丁。']);
        expect(tts.currentHighlight?.chapterIndex, 3);
        expect(runtime.takeUserNotice(), isNull);
      },
    );

    test(
      'only paid chapters after a chapter without text end reading as paid',
      () async {
        await open({0: '甲。', 1: '', 2: null}, paid: {2});
        await tts.startFromVisibleLocation();
        engine.complete();
        await pumpEventQueue();

        expect(tts.isPlaying, isFalse);
        expect(runtime.takeUserNotice()?.message, '付費章節');
      },
    );

    test(
      'when only paid chapters are left, reading ends and says so',
      () async {
        await open({0: '甲。', 1: null}, paid: {1});
        await tts.startFromVisibleLocation();
        engine.complete();
        await pumpEventQueue();

        expect(engine.spoken, ['甲。']);
        expect(tts.isPlaying, isFalse);
        expect(tts.currentHighlight, isNull);
        expect(system.title, isNull);
        expect(runtime.takeUserNotice()?.message, '付費章節');
      },
    );

    test(
      'a completion the engine reports after pausing does not read on',
      () async {
        await open({0: '甲。乙。'});
        await tts.startFromVisibleLocation();

        tts.onPause();
        engine.complete();
        await pumpEventQueue();

        expect(engine.spoken, ['甲。']);
        expect(tts.phase, ReaderTtsPhase.paused);
        expect(tts.currentHighlight?.sentenceStart, 0);
      },
    );

    test('while the picked chapter loads the highlight stays on the sentence '
        'read last', () async {
      final second = Completer<void>();
      await open({0: '甲。乙。', 1: '丙。'}, gates: {1: second});
      await tts.startFromVisibleLocation();

      tts.onSkipToNext();
      await pumpEventQueue();
      expect(tts.currentHighlight?.chapterIndex, 0);
      tts.onPause();
      await pumpEventQueue();
      expect(tts.currentHighlight?.chapterIndex, 0);

      second.complete();
      await tts.toggle();
      await pumpEventQueue();
      expect(tts.currentHighlight?.chapterIndex, 1);
    });
  });

  // 要念的那一章還在載入時，不管怎麼進來都算朗讀中：面板與定時鍵是
  // 「暫停朗讀」，系統播放資訊是要念的那章，暫停停在要念的位置。
  group('jumping by hand', () {
    test('ending while the jump waits for the engine stays ended', () async {
      await open({0: '甲。', 1: '乙。'});
      await tts.startFromVisibleLocation();
      moveTo(1);
      final engineStopped = Completer<void>();
      engine.stopGates.add(engineStopped);

      final jumping = tts.followManualJump();
      await tts.stop();
      engineStopped.complete();
      await jumping;
      await pumpEventQueue();

      expect(engine.spoken, ['甲。']);
      expect(tts.phase, ReaderTtsPhase.idle);
    });

    testWidgets('the countdown keeps running across a jump', (tester) async {
      await open({0: '甲。', 1: '乙。'});
      await tts.sleepTimer.choose(SleepTimerOption.minutes15);
      await tts.startFromVisibleLocation();
      await elapse(tester, const Duration(minutes: 5));

      moveTo(1);
      await tts.followManualJump();
      await tester.pump();
      expect(engine.spoken.last, '乙。');
      expect(tts.sleepTimer.remaining, const Duration(minutes: 10));
      await tts.stop();
    });
  });

  group('while the chapter to read loads', () {
    test('starting counts as reading and can be paused', () async {
      final second = Completer<void>();
      await open({0: '甲。', 1: '乙。'}, gates: {1: second});
      moveTo(1);
      unawaited(tts.startFromVisibleLocation());
      await pumpEventQueue();

      expect(tts.phase, ReaderTtsPhase.reading);
      expect(system.title, '第 2 章');
      expect(system.playing, isTrue);

      tts.onPause();
      second.complete();
      await pumpEventQueue();
      expect(engine.spoken, isEmpty);
      expect(tts.phase, ReaderTtsPhase.paused);

      await tts.toggle();
      expect(engine.spoken, ['乙。']);
    });

    test('a manual jump while starting reads from the new place', () async {
      final second = Completer<void>();
      await open({0: '甲。', 1: '乙。'}, gates: {1: second});
      moveTo(1);
      unawaited(tts.startFromVisibleLocation());
      await pumpEventQueue();

      moveTo(0);
      await tts.followManualJump();
      second.complete();
      await pumpEventQueue();

      expect(engine.spoken, ['甲。']);
      expect(tts.currentHighlight?.chapterIndex, 0);
    });

    test(
      'reading on to the next chapter shows it, pausing stops at its start',
      () async {
        final second = Completer<void>();
        await open({0: '甲。', 1: '乙。'}, gates: {1: second});
        await tts.startFromVisibleLocation();
        engine.complete();
        await pumpEventQueue();
        expect(system.title, '第 2 章');

        tts.onPause();
        second.complete();
        await pumpEventQueue();
        await tts.toggle();
        // 念完的「甲。」不再念一次。
        expect(engine.spoken, ['甲。', '乙。']);
      },
    );

    test('next while reading on counts from the chapter loading', () async {
      final second = Completer<void>();
      await open({0: '甲。', 1: '乙。', 2: '丙。'}, gates: {1: second});
      await tts.startFromVisibleLocation();
      engine.complete();
      await pumpEventQueue();

      tts.onSkipToNext();
      second.complete();
      await pumpEventQueue();
      expect(engine.spoken, ['甲。', '丙。']);
    });

    test(
      'passing a chapter without text counts as reading and can be paused',
      () async {
        final third = Completer<void>();
        await open({0: '甲。', 1: '', 2: '丙。'}, gates: {2: third});
        await tts.startFromVisibleLocation();
        engine.complete();
        await pumpEventQueue();

        expect(tts.phase, ReaderTtsPhase.reading);
        expect(system.title, '第 3 章');
        tts.onPause();
        third.complete();
        await pumpEventQueue();
        expect(engine.spoken, ['甲。']);

        await tts.toggle();
        expect(engine.spoken, ['甲。', '丙。']);
      },
    );

    test('passing a chapter without text keeps the highlight on the sentence '
        'read last', () async {
      final third = Completer<void>();
      await open({0: '甲。', 1: '', 2: '丙。'}, gates: {2: third});
      await tts.startFromVisibleLocation();
      final last = tts.currentHighlight;
      engine.complete();
      await pumpEventQueue();

      expect(tts.currentHighlight, last);
      third.complete();
      await pumpEventQueue();
      expect(tts.currentHighlight?.chapterIndex, 2);
    });

    test(
      'playing after pausing on a picked chapter shows that chapter',
      () async {
        final second = Completer<void>();
        await open({0: '甲。', 1: '乙。'}, gates: {1: second});
        await tts.startFromVisibleLocation();
        tts.onSkipToNext();
        await pumpEventQueue();
        tts.onPause();
        await pumpEventQueue();

        unawaited(tts.toggle());
        await pumpEventQueue();
        expect(system.title, '第 2 章');
        expect(system.playing, isTrue);

        second.complete();
        await pumpEventQueue();
        expect(engine.spoken, ['甲。', '乙。']);
      },
    );
  });

  group('jumping by sentence', () {
    test('next sentence reads the following one in the same chapter', () async {
      const text = '第一句。第二句。第三句。';
      await open({0: text});
      await tts.startFromVisibleLocation();
      expect(engine.spoken, ['第一句。']);

      await tts.skipToNextSentence();
      await pumpEventQueue();

      expect(engine.spoken.last, '第二句。');
      expect(tts.currentHighlight?.sentenceStart, text.indexOf('第二句'));
      expect(tts.currentHighlight?.sentenceEnd, text.indexOf('第三句'));
      expect(tts.isPlaying, isTrue);
    });

    test('previous goes back one and starts reading while paused', () async {
      const text = '第一句。第二句。第三句。';
      await open({0: text});
      await tts.startFromVisibleLocation();
      await tts.skipToNextSentence();
      await tts.skipToNextSentence();
      await pumpEventQueue();
      expect(engine.spoken.last, '第三句。');
      await tts.toggle();
      expect(tts.phase, ReaderTtsPhase.paused);

      await tts.skipToPreviousSentence();
      await pumpEventQueue();

      expect(tts.phase, ReaderTtsPhase.reading);
      expect(engine.spoken.last, '第二句。');
      expect(tts.currentHighlight?.sentenceStart, text.indexOf('第二句'));
    });

    test('next while paused starts reading the following sentence', () async {
      const text = '第一句。第二句。第三句。';
      await open({0: text});
      await tts.startFromVisibleLocation();
      await tts.toggle();
      expect(tts.phase, ReaderTtsPhase.paused);

      await tts.skipToNextSentence();
      await pumpEventQueue();

      expect(tts.phase, ReaderTtsPhase.reading);
      expect(engine.spoken.last, '第二句。');
    });

    test(
      'the last sentence of a chapter reads on from the next chapter',
      () async {
        await open({0: '第一句。最後一句。', 1: '第二章開頭。'}, titles: {1: '第二章'});
        await tts.startFromVisibleLocation();
        await tts.skipToNextSentence();
        await pumpEventQueue();
        expect(engine.spoken.last, '最後一句。');

        await tts.skipToNextSentence();
        await pumpEventQueue();

        expect(engine.spoken.last, '第二章');
        expect(tts.currentHighlight?.chapterIndex, 1);
        expect(tts.currentHighlight?.sentenceStart, 0);
      },
    );

    test(
      'the first sentence of a chapter reads the last one before it',
      () async {
        const first = '第一章第一句。第一章最後一句。';
        await open({0: first, 1: '第二章第一句。'});
        moveTo(1);
        await tts.startFromVisibleLocation();
        expect(engine.spoken, ['第二章第一句。']);

        await tts.skipToPreviousSentence();
        await pumpEventQueue();

        expect(engine.spoken.last, '第一章最後一句。');
        expect(tts.currentHighlight?.chapterIndex, 0);
        expect(tts.currentHighlight?.sentenceStart, first.indexOf('第一章最後一句'));
      },
    );

    test('previous skips paid chapters', () async {
      await open({0: '甲。乙。', 1: null, 2: '丙。'}, paid: {1});
      moveTo(2);
      await tts.startFromVisibleLocation();

      await tts.skipToPreviousSentence();
      await pumpEventQueue();

      expect(engine.spoken.last, '乙。');
      expect(tts.currentHighlight?.chapterIndex, 0);
    });

    test(
      'previous from a reading started mid-chapter goes back within it',
      () async {
        const text = '第一句。第二句。第三句。';
        await open({0: text});
        runtime.updateVisibleLocation(
          ReaderLocation(chapterIndex: 0, charOffset: text.indexOf('第三句')),
        );
        await tts.startFromVisibleLocation();
        expect(engine.spoken, ['第三句。']);

        await tts.skipToPreviousSentence();
        await pumpEventQueue();

        expect(engine.spoken.last, '第二句。');
        expect(tts.currentHighlight?.chapterIndex, 0);
      },
    );

    test('the first sentence of the book has nothing before it', () async {
      await open({0: '唯一的一句。'});
      await tts.startFromVisibleLocation();

      await tts.skipToPreviousSentence();
      await pumpEventQueue();

      expect(engine.spoken, ['唯一的一句。']);
      expect(tts.isPlaying, isTrue);
      expect(tts.currentHighlight?.sentenceStart, 0);
    });

    test('the last sentence of the book reads no further', () async {
      await open({0: '唯一的一句。'});
      await tts.startFromVisibleLocation();

      await tts.skipToNextSentence();
      await pumpEventQueue();

      expect(engine.spoken, ['唯一的一句。']);
      expect(tts.isPlaying, isTrue);
      expect(tts.currentHighlight?.sentenceStart, 0);
    });

    test(
      'starting from a selection reads the sentence at that place',
      () async {
        const text = '第一句。第二句。第三句。';
        await open({0: text});

        await tts.startFromSelection(
          ReaderLocation(chapterIndex: 0, charOffset: text.indexOf('第二句')),
        );
        await pumpEventQueue();

        expect(engine.spoken, ['第二句。']);
        expect(tts.currentHighlight?.sentenceStart, text.indexOf('第二句'));
        expect(tts.isPlaying, isTrue);
      },
    );
  });

  group('when the engine cannot speak', () {
    test('reading pauses on that sentence and says so', () async {
      await open({0: '甲。乙。'});
      await tts.startFromVisibleLocation();
      engine.complete();
      await pumpEventQueue();

      engine.fail();
      await pumpEventQueue();
      expect(tts.phase, ReaderTtsPhase.paused);
      expect(tts.currentHighlight?.sentenceStart, 2);
      expect(system.playing, isFalse);
      expect(runtime.takeUserNotice()?.message, '朗讀引擎出錯，已暫停');

      await tts.toggle();
      expect(engine.spoken, ['甲。', '乙。', '乙。']);
    });

    test('a failure reported after pausing changes nothing', () async {
      await open({0: '甲。乙。'});
      await tts.startFromVisibleLocation();
      tts.onPause();

      engine.fail();
      await pumpEventQueue();
      expect(tts.phase, ReaderTtsPhase.paused);
      expect(runtime.takeUserNotice(), isNull);
    });
  });

  group('ending from the panel', () {
    test('ending while paused clears the highlight and the system info, the '
        'next start reads from the page', () async {
      await open({0: '甲。乙。', 1: '丙。'});
      await tts.startFromVisibleLocation();
      engine.complete();
      await pumpEventQueue();
      await tts.toggle();
      expect(tts.phase, ReaderTtsPhase.paused);

      await tts.stop();
      await pumpEventQueue();
      expect(tts.phase, isNot(ReaderTtsPhase.paused));
      expect(tts.isPlaying, isFalse);
      expect(tts.currentHighlight, isNull);
      expect(system.title, isNull);

      moveTo(1);
      await tts.toggle();
      expect(engine.spoken.last, '丙。');
    });

    test('ending while the next chapter loads keeps it silent', () async {
      final second = Completer<void>();
      await open({0: '甲。', 1: '乙。'}, gates: {1: second});
      await tts.startFromVisibleLocation();
      engine.complete();
      await pumpEventQueue();

      await tts.stop();
      second.complete();
      await pumpEventQueue();

      expect(engine.spoken, ['甲。']);
      expect(tts.isPlaying, isFalse);
      expect(tts.currentHighlight, isNull);
      expect(system.title, isNull);
    });
  });

  group('sleep timer', () {
    testWidgets('pauses on the sentence being read when time is up', (
      tester,
    ) async {
      await open({0: '第一句。第二句。'});
      await tts.sleepTimer.choose(SleepTimerOption.minutes15);
      await tts.startFromVisibleLocation();
      engine.complete();
      await tester.pump();
      expect(engine.spoken.last, '第二句。');
      final sentenceStart = tts.currentHighlight?.sentenceStart;

      await elapse(tester, const Duration(minutes: 15));

      expect(tts.isPlaying, isFalse);
      expect(tts.phase, ReaderTtsPhase.paused);
      expect(tts.currentHighlight?.sentenceStart, sentenceStart);

      await tts.toggle();
      expect(engine.spoken.last, '第二句。');
      expect(tts.sleepTimer.remaining, const Duration(minutes: 15));
      await tts.stop();
    });

    testWidgets('does not count down while paused', (tester) async {
      await open({0: '唯一的一句。'});
      await tts.sleepTimer.choose(SleepTimerOption.minutes15);
      await tts.startFromVisibleLocation();
      await elapse(tester, const Duration(minutes: 5));

      await tts.toggle();
      await elapse(tester, const Duration(hours: 1));
      expect(tts.phase, ReaderTtsPhase.paused);
      expect(tts.sleepTimer.remaining, const Duration(minutes: 10));

      await tts.toggle();
      await elapse(tester, const Duration(minutes: 10));
      expect(tts.isPlaying, isFalse);
    });

    testWidgets('keeps counting down when next lands on a chapter without '
        'text', (tester) async {
      await open({0: '甲。', 1: '', 2: '丙。'});
      await tts.sleepTimer.choose(SleepTimerOption.minutes15);
      await tts.startFromVisibleLocation();
      await elapse(tester, const Duration(minutes: 5));

      tts.onSkipToNext();
      await tester.pump();
      expect(engine.spoken.last, '丙。');
      expect(tts.sleepTimer.remaining, const Duration(minutes: 10));
      await tts.stop();
    });

    testWidgets('does not count down while the chapter to read loads', (
      tester,
    ) async {
      final second = Completer<void>();
      await open({0: '甲。', 1: '乙。'}, gates: {1: second});
      moveTo(1);
      await tts.sleepTimer.choose(SleepTimerOption.minutes15);
      unawaited(tts.startFromVisibleLocation());
      await elapse(tester, const Duration(minutes: 5));

      expect(tts.phase, ReaderTtsPhase.reading);
      expect(engine.spoken, isEmpty);
      expect(tts.sleepTimer.remaining, isNull);

      second.complete();
      await tester.pump();
      expect(engine.spoken, ['乙。']);
      expect(tts.sleepTimer.remaining, const Duration(minutes: 15));
      await tts.stop();
    });

    testWidgets('stops counting down while the next chapter loads', (
      tester,
    ) async {
      final second = Completer<void>();
      await open({0: '甲。', 1: '乙。'}, gates: {1: second});
      await tts.sleepTimer.choose(SleepTimerOption.minutes15);
      await tts.startFromVisibleLocation();
      await elapse(tester, const Duration(minutes: 5));

      engine.complete();
      await tester.pump();
      await elapse(tester, const Duration(minutes: 5));
      expect(tts.phase, ReaderTtsPhase.reading);
      expect(tts.sleepTimer.remaining, const Duration(minutes: 10));

      second.complete();
      await tester.pump();
      expect(engine.spoken.last, '乙。');
      expect(tts.sleepTimer.remaining, const Duration(minutes: 10));
      await tts.stop();
    });

    testWidgets('keeps counting down across chapters', (tester) async {
      await open({0: '甲。', 1: '乙。'});
      await tts.sleepTimer.choose(SleepTimerOption.minutes15);
      await tts.startFromVisibleLocation();
      await elapse(tester, const Duration(minutes: 5));

      engine.complete();
      await tester.pump();
      expect(engine.spoken.last, '乙。');
      expect(tts.sleepTimer.remaining, const Duration(minutes: 10));
      await tts.stop();
    });

    testWidgets('starting again right after ending counts down afresh', (
      tester,
    ) async {
      await open({0: '甲。'});
      await tts.sleepTimer.choose(SleepTimerOption.minutes15);
      await tts.startFromVisibleLocation();
      await elapse(tester, const Duration(minutes: 5));

      final engineStopped = Completer<void>();
      engine.stopGates.add(engineStopped);
      final ending = tts.stop();
      await tts.startFromVisibleLocation();
      engineStopped.complete();
      await ending;
      await tester.pump();

      expect(tts.sleepTimer.remaining, const Duration(minutes: 15));
      await tts.stop();
    });

    testWidgets('a custom timer counts down its own minutes', (tester) async {
      await open({0: '唯一的一句。'});
      await tts.sleepTimer.setCustomMinutes(20);
      await tts.sleepTimer.choose(SleepTimerOption.custom);
      await tts.startFromVisibleLocation();
      expect(tts.sleepTimer.remaining, const Duration(minutes: 20));

      await elapse(tester, const Duration(minutes: 5));
      await tts.sleepTimer.setCustomMinutes(10);
      expect(tts.sleepTimer.remaining, const Duration(minutes: 10));

      await elapse(tester, const Duration(minutes: 10));
      expect(tts.isPlaying, isFalse);
      expect(tts.phase, ReaderTtsPhase.paused);
    });

    testWidgets('changing the custom minutes leaves a preset alone', (
      tester,
    ) async {
      await open({0: '唯一的一句。'});
      await tts.sleepTimer.choose(SleepTimerOption.minutes15);
      await tts.startFromVisibleLocation();
      await elapse(tester, const Duration(minutes: 5));

      await tts.sleepTimer.setCustomMinutes(40);
      expect(tts.sleepTimer.remaining, const Duration(minutes: 10));
      await tts.stop();
    });

    testWidgets('custom minutes stay within range', (tester) async {
      await open({0: '唯一的一句。'});
      await tts.sleepTimer.setCustomMinutes(0);
      expect(tts.sleepTimer.customMinutes, 1);
      await tts.sleepTimer.setCustomMinutes(999);
      expect(tts.sleepTimer.customMinutes, 180);
    });

    testWidgets('stopping clears the countdown but keeps the choice', (
      tester,
    ) async {
      await open({0: '唯一的一句。'});
      await tts.sleepTimer.choose(SleepTimerOption.minutes30);
      await tts.startFromVisibleLocation();
      await elapse(tester, const Duration(minutes: 10));

      await tts.stop();
      expect(tts.sleepTimer.remaining, isNull);

      await tts.startFromVisibleLocation();
      expect(tts.sleepTimer.remaining, const Duration(minutes: 30));
      await tts.stop();
    });

    testWidgets('the timer key reads aloud with the remembered timer', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({PreferKey.ttsTimer: 45});
      await open({0: '唯一的一句。'});
      await tts.loadSettings();

      await tts.toggleTimed();
      expect(engine.spoken, ['唯一的一句。']);
      expect(tts.sleepTimer.remaining, const Duration(minutes: 45));

      // 念著時再按是暫停在這一句，再按一次從這句接著念。
      await tts.toggleTimed();
      expect(tts.isPlaying, isFalse);
      expect(tts.phase, ReaderTtsPhase.paused);

      await tts.toggleTimed();
      expect(engine.spoken, ['唯一的一句。', '唯一的一句。']);
      await tts.stop();
    });

    // 使用者在朗讀面板關掉定時後按定時鍵，原本改成 30 分並記住，關掉的
    // 設定每按一次就被蓋掉。
    testWidgets('the timer key reads without a timer when the timer is off', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({PreferKey.ttsTimer: 0});
      await open({0: '唯一的一句。'});
      await tts.loadSettings();

      await tts.toggleTimed();
      expect(engine.spoken, ['唯一的一句。']);
      expect(tts.sleepTimer.option, SleepTimerOption.off);
      expect(tts.sleepTimer.remaining, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PreferKey.ttsTimer), 0);
      await tts.stop();
    });

    testWidgets('the timer key resumes after the timer paused reading', (
      tester,
    ) async {
      await open({0: '第一句。第二句。'});
      await tts.sleepTimer.choose(SleepTimerOption.minutes15);
      await tts.startFromVisibleLocation();
      await elapse(tester, const Duration(minutes: 15));
      expect(tts.phase, ReaderTtsPhase.paused);

      await tts.toggleTimed();
      expect(engine.spoken, ['第一句。', '第一句。']);
      expect(tts.sleepTimer.remaining, const Duration(minutes: 15));
      await tts.stop();
    });

    testWidgets('the last choice is remembered', (tester) async {
      SharedPreferences.setMockInitialValues({
        PreferKey.ttsTimer: 45,
        PreferKey.ttsTimerCustomMinutes: 25,
      });
      await open({0: '唯一的一句。'});
      await tts.loadSettings();
      expect(tts.sleepTimer.option, SleepTimerOption.minutes45);
      expect(tts.sleepTimer.customMinutes, 25);

      await tts.sleepTimer.choose(SleepTimerOption.custom);
      await tts.sleepTimer.setCustomMinutes(70);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PreferKey.ttsTimer), -1);
      expect(prefs.getInt(PreferKey.ttsTimerCustomMinutes), 70);
    });
  });
  group('system playback info', () {
    test('shows the chapter, the book and the buttons it can do', () async {
      await open({0: '第一句。', 1: '第二章開頭。'}, titles: {0: '第一章 夜雨', 1: '第二章 天明'});
      await tts.startFromVisibleLocation();
      await pumpEventQueue();

      expect(system.title, '第一章 夜雨');
      expect(system.subtitle, '朗讀測試書 · 作者');
      expect(system.playing, isTrue);
      // 第一章沒有上一章。
      expect(system.controls, {
        PlaybackControl.skipToNext,
        PlaybackControl.stop,
      });
    });

    test(
      'a chapter still loading shows its title converted like the header',
      () async {
        ChineseUtils.initializeFromDictionaryData([
          for (final path in ChineseUtils.dictionaryAssetPaths)
            File(path).readAsStringSync(),
        ]);
        final mode = ChineseDisplay.mode.value;
        ChineseDisplay.mode.value = 1;
        addTearDown(() => ChineseDisplay.mode.value = mode);
        final second = Completer<void>();
        await open({0: '甲。', 1: '乙。'}, titles: {1: '斗罗大陆'}, gates: {1: second});
        await tts.startFromVisibleLocation();

        tts.onSkipToNext();
        await pumpEventQueue();
        expect(system.title, '斗羅大陸');
        second.complete();
      },
    );

    test('a chapter without a title shows its number', () async {
      await open({0: '第一句。'});
      await tts.startFromVisibleLocation();
      await pumpEventQueue();

      expect(system.title, '第 1 章');
      expect(system.controls, {PlaybackControl.stop});
    });

    test('only paid chapters that way leaves that button out', () async {
      await open({0: null, 1: '乙。', 2: null}, paid: {0, 2});
      moveTo(1);
      await tts.startFromVisibleLocation();
      await pumpEventQueue();

      expect(system.controls, {PlaybackControl.stop});
    });

    test('pausing shows paused, stopping takes it away', () async {
      await open({0: '第一句。'});
      await tts.startFromVisibleLocation();

      tts.onPause();
      await pumpEventQueue();
      expect(tts.phase, ReaderTtsPhase.paused);
      expect(system.playing, isFalse);

      tts.onPlay();
      await pumpEventQueue();
      expect(system.playing, isTrue);

      tts.onStop();
      await pumpEventQueue();
      expect(tts.isPlaying, isFalse);
      expect(system.title, isNull);
    });

    test(
      'next chapter reads from its start and the highlight goes there',
      () async {
        await open({0: '第一句。', 1: '第二章開頭。'}, titles: {0: '第一章', 1: '第二章'});
        await tts.startFromVisibleLocation();

        tts.onSkipToNext();
        await pumpEventQueue();

        expect(tts.currentHighlight?.chapterIndex, 1);
        expect(engine.spoken.last, '第二章');
        expect(system.title, '第二章');
        // 最後一章沒有下一章。
        expect(system.controls, {
          PlaybackControl.skipToPrevious,
          PlaybackControl.stop,
        });

        tts.onSkipToPrevious();
        await pumpEventQueue();
        expect(tts.currentHighlight?.chapterIndex, 0);
        expect(system.title, '第一章');
      },
    );

    testWidgets('next chapter while paused by the timer starts reading', (
      tester,
    ) async {
      await open({0: '第一句。', 1: '第二章開頭。'});
      await tts.sleepTimer.choose(SleepTimerOption.minutes15);
      await tts.startFromVisibleLocation();
      await elapse(tester, const Duration(minutes: 15));
      expect(tts.phase, ReaderTtsPhase.paused);

      tts.onSkipToNext();
      await tester.pump();

      expect(engine.spoken.last, '第二章開頭。');
      expect(tts.isPlaying, isTrue);
      expect(system.playing, isTrue);
      await tts.stop();
    });

    test('another player starting pauses reading on its sentence', () async {
      await open({0: '第一句。第二句。'});
      await tts.startFromVisibleLocation();
      engine.complete();
      await pumpEventQueue();
      final sentenceStart = tts.currentHighlight?.sentenceStart;

      final other = _OtherOwner();
      const audio = NowPlaying(
        id: 'audio',
        title: '第一集',
        bookName: '有聲書',
        author: '',
      );
      playback.show(other, item: audio, playing: true, controls: const {});
      await pumpEventQueue();

      expect(tts.isPlaying, isFalse);
      expect(tts.phase, ReaderTtsPhase.paused);
      expect(tts.currentHighlight?.sentenceStart, sentenceStart);
      // 暫停中的朗讀不把系統播放資訊搶回來。
      expect(system.title, '第一集');

      // 回到朗讀按播放：從那一句開頭接著念，換有聲書暫停。
      await tts.toggle();
      await pumpEventQueue();
      expect(engine.spoken.last, '第二句。');
      expect(other.pauses, 1);
      expect(system.title, '第 1 章');
      expect(system.playing, isTrue);
    });

    test('a completion the engine reports while the picked chapter loads does '
        'not read the old chapter on', () async {
      final second = Completer<void>();
      await open({0: '甲。乙。', 1: '丙。'}, gates: {1: second});
      await tts.startFromVisibleLocation();

      tts.onSkipToNext();
      await pumpEventQueue();
      engine.complete();
      await pumpEventQueue();
      expect(engine.spoken, ['甲。']);

      second.complete();
      await pumpEventQueue();
      expect(engine.spoken, ['甲。', '丙。']);
    });

    test('another player starting after pausing on a picked chapter keeps the '
        'place to read on from', () async {
      final second = Completer<void>();
      await open({0: '甲。', 1: '乙。'}, gates: {1: second});
      await tts.startFromVisibleLocation();
      tts.onSkipToNext();
      await pumpEventQueue();
      tts.onPause();
      await pumpEventQueue();

      final other = _OtherOwner();
      playback.show(
        other,
        item: const NowPlaying(
          id: 'audio',
          title: '第一集',
          bookName: '有聲書',
          author: '',
        ),
        playing: true,
        controls: const {},
      );
      second.complete();
      await pumpEventQueue();

      await tts.toggle();
      await pumpEventQueue();
      expect(engine.spoken, ['甲。', '乙。']);
    });

    test('pressing next twice quickly moves two chapters', () async {
      await open({0: '第一句。', 1: '第二句。', 2: '第三句。'});
      await tts.startFromVisibleLocation();

      tts.onSkipToNext();
      tts.onSkipToNext();
      await pumpEventQueue();

      expect(tts.currentHighlight?.chapterIndex, 2);
      expect(engine.spoken, ['第一句。', '第三句。']);
      expect(system.title, '第 3 章');
    });

    test(
      'a chapter picked while the next one is still loading reads on',
      () async {
        // 念完第二章、第三章還在載入時按上一章：從載入中的第三章往前算，
        // 第二章先念起來，念完一句要接著念下一句，不被還在等第三章的那一輪
        // 擋掉。
        final third = Completer<void>();
        await open({0: '甲。', 1: '丙。戊。', 2: '丁。'}, gates: {2: third});
        moveTo(1);
        await tts.startFromVisibleLocation();
        engine.complete();
        await pumpEventQueue();
        engine.complete();
        await pumpEventQueue();

        tts.onSkipToPrevious();
        await pumpEventQueue();
        engine.complete();
        await pumpEventQueue();

        expect(engine.spoken, ['丙。', '戊。', '丙。', '戊。']);
        third.complete();
        await pumpEventQueue();
        expect(engine.spoken.last, '戊。');
        expect(tts.currentHighlight?.chapterIndex, 1);
      },
    );

    test('pausing while the picked chapter loads stops at its start', () async {
      final second = Completer<void>();
      await open({0: '第一句。', 1: '第二句。'}, gates: {1: second});
      await tts.startFromVisibleLocation();

      tts.onSkipToNext();
      await pumpEventQueue();
      // 系統播放資訊先換到按的那一章。
      expect(system.title, '第 2 章');
      tts.onPause();
      second.complete();
      await pumpEventQueue();
      expect(engine.spoken, ['第一句。']);
      expect(system.playing, isFalse);

      await tts.toggle();
      expect(engine.spoken.last, '第二句。');
    });

    test('the panel pauses while the picked chapter loads', () async {
      final second = Completer<void>();
      await open({0: '第一句。', 1: '第二句。'}, gates: {1: second});
      await tts.startFromVisibleLocation();

      tts.onSkipToNext();
      await pumpEventQueue();
      // 引擎停著等第二章，朗讀還在進行：面板按下去是暫停，不是從畫面重念。
      expect(tts.isPlaying, isTrue);
      await tts.toggle();
      expect(tts.phase, ReaderTtsPhase.paused);
      second.complete();
      await pumpEventQueue();
      expect(engine.spoken, ['第一句。']);

      await tts.toggle();
      expect(engine.spoken.last, '第二句。');
    });

    test('a picked chapter that fails to load takes the info away', () async {
      await open({0: '第一句。', 1: null});
      await tts.startFromVisibleLocation();

      tts.onSkipToNext();
      await pumpEventQueue();

      expect(tts.isPlaying, isFalse);
      expect(system.title, isNull);
    });
  });
}
