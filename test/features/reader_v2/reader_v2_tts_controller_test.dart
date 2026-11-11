import 'dart:async';
import 'dart:io';

import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/system_playback/now_playing_artwork.dart';
import 'package:night_reader/core/services/system_playback/system_playback.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_controller.dart';
import 'package:night_reader/core/services/sleep_timer.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
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

class _FakeTtsEngine extends ReaderV2TtsEngine {
  final StreamController<void> _completions =
      StreamController<void>.broadcast();
  final List<String> spoken = <String>[];
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
  Future<void> speak(String text) async {
    spoken.add(text);
    _text = text;
    _playing = true;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
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

  @override
  Future<void> setRate(double value) async {}

  @override
  Future<void> setPitch(double value) async {}

  @override
  Future<void> setLanguage(String value) async {}
}

void main() {
  late ReaderV2Runtime runtime;
  late _FakeTtsEngine engine;
  late ReaderV2TtsController tts;
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

  /// [gates] 裡的章節等它完成才載入好。
  Future<void> open(
    Map<int, String?> contents, {
    Map<int, String> titles = const {},
    Map<int, Completer<void>> gates = const {},
  }) async {
    final book = Book(
      bookUrl: 'http://tts.test',
      name: '朗讀測試書',
      author: '作者',
      origin: 'local',
      originName: '本地',
    );
    final bookDao = _FakeBookDao();
    final repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: [
        for (final index in contents.keys)
          BookChapter(
            url: 'chapter_$index',
            title: titles[index] ?? '',
            bookUrl: book.bookUrl,
            index: index,
          ),
      ],
      contentLoader: (index, _) async {
        await gates[index]?.future;
        final content = contents[index];
        if (content == null) {
          throw const ReaderV2ContentUnavailableException('暫時無法取得');
        }
        return content;
      },
      bookDao: bookDao,
      chapterDao: _FakeChapterDao(),
      sourceDao: _FakeSourceDao(),
    );
    runtime = ReaderV2Runtime(
      book: book,
      repository: repository,
      progressController: ReaderV2ProgressController(
        book: book,
        repository: repository,
        bookDao: bookDao,
      ),
      initialLayoutSpec: ReaderV2LayoutSpec.fromViewport(
        viewportSize: const Size(400, 600),
        style: const ReaderV2LayoutStyle(
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
      initialLocation: const ReaderV2Location(chapterIndex: 0, charOffset: 0),
    );
    runtime.registerViewportRestore(Object(), (_) async => true);
    await runtime.openBook();
    engine = _FakeTtsEngine();
    tts = ReaderV2TtsController(
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
      ReaderV2Location(chapterIndex: chapterIndex, charOffset: 0),
    );
  }

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
      expect(tts.isPaused, isTrue);

      moveTo(1);
      await tts.followManualJump();
      expect(tts.isPaused, isFalse);
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
    expect(runtime.takeUserNotice()?.message, '第 2 章無法載入，朗讀已停止');
  });

  test('finishing the last chapter says the book has ended', () async {
    await open({0: '唯一的一句。'});
    await tts.startFromVisibleLocation();
    engine.complete();
    await pumpEventQueue();

    expect(tts.currentHighlight, isNull);
    expect(runtime.takeUserNotice()?.message, '已朗讀到書尾');
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
      expect(tts.isPaused, isTrue);
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
      expect(tts.isPaused, isTrue);
      expect(tts.sleepTimer.remaining, const Duration(minutes: 10));

      await tts.toggle();
      await elapse(tester, const Duration(minutes: 10));
      expect(tts.isPlaying, isFalse);
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
      expect(tts.isPaused, isTrue);
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
      expect(tts.isPaused, isTrue);

      await tts.toggleTimed();
      expect(engine.spoken, ['唯一的一句。', '唯一的一句。']);
      await tts.stop();
    });

    testWidgets('the timer key uses 30 minutes when the timer is off', (
      tester,
    ) async {
      await open({0: '唯一的一句。'});

      await tts.toggleTimed();
      expect(tts.sleepTimer.option, SleepTimerOption.minutes30);
      expect(tts.sleepTimer.remaining, const Duration(minutes: 30));
      await tts.stop();
    });

    testWidgets('the timer key resumes after the timer paused reading', (
      tester,
    ) async {
      await open({0: '第一句。第二句。'});
      await tts.sleepTimer.choose(SleepTimerOption.minutes15);
      await tts.startFromVisibleLocation();
      await elapse(tester, const Duration(minutes: 15));
      expect(tts.isPaused, isTrue);

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

    test('a chapter without a title shows its number', () async {
      await open({0: '第一句。'});
      await tts.startFromVisibleLocation();
      await pumpEventQueue();

      expect(system.title, '第 1 章');
      expect(system.controls, {PlaybackControl.stop});
    });

    test('pausing shows paused, stopping takes it away', () async {
      await open({0: '第一句。'});
      await tts.startFromVisibleLocation();

      tts.onPause();
      await pumpEventQueue();
      expect(tts.isPaused, isTrue);
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
      expect(tts.isPaused, isTrue);

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
      expect(tts.isPaused, isTrue);
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
        // 念完第二章、第三章還在載入時按上一章：第一章先念起來，念完一句
        // 要接著念下一句，不被還在等第三章的那一輪擋掉。
        final third = Completer<void>();
        await open({0: '甲。乙。', 1: '丙。', 2: '丁。'}, gates: {2: third});
        moveTo(1);
        await tts.startFromVisibleLocation();
        engine.complete();
        await pumpEventQueue();

        tts.onSkipToPrevious();
        await pumpEventQueue();
        engine.complete();
        await pumpEventQueue();

        expect(engine.spoken, ['丙。', '甲。', '乙。']);
        third.complete();
        await pumpEventQueue();
        expect(engine.spoken.last, '乙。');
        expect(tts.currentHighlight?.chapterIndex, 0);
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
