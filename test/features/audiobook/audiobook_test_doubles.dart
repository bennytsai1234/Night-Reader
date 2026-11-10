// 有聲書播放器的測試替身：假的播放引擎、書源、同步與系統播放資訊。
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/audio_url_resolver.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/system_playback/system_playback.dart';
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

/// 系統播放資訊：不向系統開工作階段，記下最後交出去的內容；收掉時清空。
class RecordingPlayback extends SystemPlayback {
  NowPlaying? item;
  bool? playing;
  Set<PlaybackControl>? controls;
  Duration? position;

  @override
  Future<void> start() async {}

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
  }

  @override
  void release(PlaybackOwner owner) {
    super.release(owner);
    item = null;
    playing = null;
    controls = null;
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
  Future<void>? get progressReady => null;

  @override
  void openBook(Book book) => opened.add(book.bookUrl);

  @override
  void closeBook(Book book) => closed.add(book.bookUrl);

  @override
  void requestSyncProgressFirst() {}
}
