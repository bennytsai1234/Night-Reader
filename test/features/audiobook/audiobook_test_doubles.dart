// 有聲書播放器的測試替身：假的播放引擎、書源、同步、音訊焦點與系統播放資訊。
import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/audio_url_resolver.dart';
import 'package:night_reader/core/playback/audio_focus.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/core/playback/system_playback.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/features/audiobook/audio_engine.dart';

/// 假的播放引擎：記下開了哪一集、停在哪裡，測試自己推進播放。
class FakeAudioEngine implements AudioEngine {
  final _playing = StreamController<bool>.broadcast(sync: true);
  final _position = StreamController<Duration>.broadcast(sync: true);
  final _duration = StreamController<Duration?>.broadcast(sync: true);
  final _buffering = StreamController<bool>.broadcast(sync: true);
  final _completed = StreamController<void>.broadcast(sync: true);
  final _errors = StreamController<Object>.broadcast(sync: true);

  final _opens = StreamController<void>.broadcast(sync: true);

  final List<(Uri, Duration)> opened = [];

  /// 下一次開檔。換集要先看這一集下載了沒（真的讀檔案系統），花的時間不是
  /// 固定幾輪事件佇列：等換集開好的測試等它（CI 上等 20 輪不夠，2026-11-19）。
  /// 要在觸發換集之前先拿。
  Future<void> get nextOpen => _opens.stream.first;
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
    _opens.add(null);
    await openGate?.future;
    if (failingOpens.contains(uri.toString())) throw StateError('播不出來');
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

  /// 暫停、拖動要等外面放行（測試等待途中按了什麼）。
  Completer<void>? pauseGate;
  Completer<void>? seekGate;

  /// 給了就等它才開好這一集（載入中的那段時間）。
  Completer<void>? openGate;

  /// 開這幾個網址時失敗（那一集播不出來）。
  final Set<String> failingOpens = {};

  @override
  Future<void> pause() async {
    await pauseGate?.future;
    _setPlaying(false);
  }

  @override
  Future<void> seek(Duration to) async {
    await seekGate?.future;
    position = to;
  }

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

  /// 開始或結束緩衝（等資料、沒有聲音）。
  void buffer(bool value) => _buffering.add(value);

  /// 播放途中出錯。
  void fail(Object error) => _errors.add(error);

  /// 這一集播完。
  void finish() {
    _setPlaying(false);
    _completed.add(null);
  }
}

/// 書源：每一集的音訊網址是「章節網址.mp3」，帶一個 Referer 標頭。
class FakeAudioSourceService extends BookSourceService {
  final List<String> resolved = [];

  /// 解析音訊網址前要等外面放行（測試載入中）。
  Completer<void>? gate;

  /// 這幾集的網址解析失敗。
  final Set<String> failing = {};

  /// 資料庫裡沒有目錄時向書源抓目錄：要等外面放行，放行時給的目錄（null 是
  /// 抓不到）。
  Completer<List<BookChapter>?>? chapterList;

  @override
  Future<List<BookChapter>> getChapterList(
    BookSource source,
    Book book, {
    int? chapterLimit,
    int? pageConcurrency,
    CancelToken? cancelToken,
    bool requireComplete = false,
  }) async {
    final chapters = await chapterList?.future;
    if (chapters == null) throw StateError('抓不到目錄');
    return chapters;
  }

  @override
  Future<AudioRequest> getAudioRequest(
    BookSource source,
    Book book,
    BookChapter chapter, {
    CancelToken? cancelToken,
  }) async {
    resolved.add(chapter.url);
    await gate?.future;
    if (failing.contains(chapter.url)) throw StateError('抓不到這一集');
    return AudioRequest(
      url: '${chapter.url}.mp3',
      headers: const {'Referer': 'https://audio.test/'},
    );
  }
}

/// 假的音訊工作階段：照 `audio_session` 在 Android 上的樣子，已經要過焦點
/// 就直接回給了、不再問系統，放掉才會再問。打斷由測試送事件。
class FakeAudioFocusSession implements AudioFocusPlatform {
  FakeAudioFocusSession({this.granted = true});

  bool granted;

  /// 真的問了系統幾次。
  int asked = 0;
  bool _requested = false;

  final interruptionEvents =
      StreamController<AudioInterruptionEvent>.broadcast();
  final noisyEvents = StreamController<void>.broadcast();

  @override
  Future<bool> activate() async {
    if (_requested) return true;
    _requested = true;
    asked += 1;
    return granted;
  }

  @override
  Future<void> deactivate() async {
    _requested = false;
  }

  @override
  Stream<AudioInterruptionEvent> get interruptions => interruptionEvents.stream;

  @override
  Stream<void> get becomingNoisy => noisyEvents.stream;
}

/// 系統播放資訊：不向系統開工作階段，記下最後交出去的內容；收掉時清空。
class RecordingPlayback extends SystemPlayback {
  NowPlaying? item;
  bool? playing;
  Set<PlaybackControl>? controls;
  Duration? position;
  bool? buffering;

  /// 接手系統播放要等外面放行（真的第一次接手要等系統建好工作階段）。
  Completer<void>? startGate;

  @override
  Future<void> start() async => startGate?.future;

  @override
  void show(
    PlaybackOwner owner, {
    required NowPlaying item,
    required bool playing,
    required Set<PlaybackControl> controls,
    Duration? position,
    double speed = 1.0,
    bool buffering = false,
  }) {
    super.show(
      owner,
      item: item,
      playing: playing,
      controls: controls,
      position: position,
      speed: speed,
      buffering: buffering,
    );
    this.item = item;
    this.playing = playing;
    this.controls = controls;
    this.position = position;
    this.buffering = buffering;
  }

  @override
  void release(PlaybackOwner owner) {
    super.release(owner);
    item = null;
    playing = null;
    controls = null;
    buffering = null;
  }
}

/// 原本在播的另一方（例如朗讀）。
class OtherPlaybackOwner implements PlaybackOwner {
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
  void onRewind() {}

  @override
  void onFastForward() {}

  @override
  void onSeek(Duration position) {}
}

class FakeSync extends Fake implements SyncService {
  final List<String> opened = [];
  final List<String> closed = [];

  @override
  void openBook(Book book) => opened.add(book.bookUrl);

  @override
  void closeBook(Book book) => closed.add(book.bookUrl);

  /// 要求進度優先送出的次數。
  int progressFirstRequests = 0;

  @override
  void requestSyncProgressFirst() => progressFirstRequests++;

  /// 登記成退到背景時自己送進度的閱讀器與播放器。
  final Set<Object> hideUploaders = {};

  @override
  void uploadsOnHide(Object owner, bool on) =>
      on ? hideUploaders.add(owner) : hideUploaders.remove(owner);

  /// 抓了幾次雲端進度。
  int pulls = 0;

  /// 回到前景時抓到的、另一台較新的進度；記下有沒有被記成同步過。
  PulledProgress? pulled;
  int commits = 0;

  /// 抓另一台的進度要等外面放行（測試抓的途中按了什麼）。
  Completer<void>? pullGate;

  @override
  Future<PulledProgress?> pullProgress(String bookUrl) async {
    pulls++;
    await pullGate?.future;
    return pulled;
  }
}
