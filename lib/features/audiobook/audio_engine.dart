import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// 有聲書播放器背後的播放引擎。實際用 `just_audio`（[JustAudioEngine]），
/// 測試換成假的。
abstract interface class AudioEngine {
  bool get playing;
  Duration get position;

  /// 這一集的總長；還不知道（剛開始載入、直播串流）時是 null。
  Duration? get duration;

  Stream<bool> get playingStream;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;

  /// 正在等資料（載入或緩衝）。
  Stream<bool> get bufferingStream;

  /// 這一集播到結尾。
  Stream<void> get completedStream;

  /// 載入或播放中出錯。
  Stream<Object> get errorStream;

  /// 換成 [uri] 這一集，停在 [start]，不自動播。
  Future<void> open(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration start = Duration.zero,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> stop();
  Future<void> dispose();
}

class JustAudioEngine implements AudioEngine {
  JustAudioEngine() : _player = AudioPlayer() {
    _subscriptions.add(
      _player.playbackEventStream.listen(
        (_) {},
        onError: (Object error, StackTrace _) => _errors.add(error),
      ),
    );
  }

  final AudioPlayer _player;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final StreamController<Object> _errors = StreamController.broadcast();

  @override
  bool get playing => _player.playing;

  @override
  Duration get position => _player.position;

  @override
  Duration? get duration => _player.duration;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Stream<Duration> get positionStream => _player.createPositionStream(
    minPeriod: const Duration(milliseconds: 200),
    maxPeriod: const Duration(milliseconds: 500),
  );

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<bool> get bufferingStream => _player.processingStateStream.map(
    (state) =>
        state == ProcessingState.loading || state == ProcessingState.buffering,
  );

  @override
  Stream<void> get completedStream => _player.processingStateStream
      .where((state) => state == ProcessingState.completed)
      .map((_) {});

  @override
  Stream<Object> get errorStream => _errors.stream;

  @override
  Future<void> open(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration start = Duration.zero,
  }) async {
    await _player.setAudioSource(
      uri.isScheme('file')
          ? AudioSource.file(uri.toFilePath())
          : AudioSource.uri(uri, headers: headers.isEmpty ? null : headers),
      initialPosition: start,
    );
  }

  @override
  Future<void> play() async {
    // just_audio 的 play() 要等暫停或播完才完成；這裡只要開始播。
    unawaited(
      _player.play().catchError((Object error) {
        if (!_errors.isClosed) _errors.add(error);
      }),
    );
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _errors.close();
    await _player.dispose();
  }
}
