import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:night_reader/core/services/app_log_service.dart';

/// 系統播放控制（通知、鎖定畫面、耳機與藍牙按鍵、各家的「島」）的一個來源：
/// 朗讀或有聲書。整個 App 只能 `AudioService.init` 一次，兩者共用同一個
/// [ReaderAudioHandler]，誰開始播誰接手（ADR 0050）。
abstract interface class MediaSessionOwner {
  /// 另一個來源接手了：暫停自己，記住停在哪裡。
  void yieldMedia();

  Future<void> onPlay();
  Future<void> onPause();
  Future<void> onStop();
  Future<void> onSkipToNext();
  Future<void> onSkipToPrevious();
  Future<void> onRewind();
  Future<void> onFastForward();
  Future<void> onSeek(Duration position);
}

/// 把系統送來的指令轉給目前的 [MediaSessionOwner]。朗讀不是 owner：沒有人
/// 接手時指令照舊以事件送給朗讀（[eventStream]）。
class ReaderAudioHandler extends BaseAudioHandler with SeekHandler {
  static final StreamController<String> _eventController =
      StreamController<String>.broadcast();
  static Stream<String> get eventStream => _eventController.stream;

  /// 朗讀用的按鈕：上一章、播放／暫停、下一章、停止。
  static List<MediaControl> _ttsControls(bool playing) => [
    MediaControl.skipToPrevious,
    playing ? MediaControl.pause : MediaControl.play,
    MediaControl.skipToNext,
    MediaControl.stop,
  ];

  ReaderAudioHandler() {
    playbackState.add(
      PlaybackState(
        controls: _ttsControls(false),
        systemActions: const {MediaAction.playPause},
        playing: false,
        processingState: AudioProcessingState.ready,
      ),
    );
  }

  MediaSessionOwner? _owner;

  /// 目前的來源；null 是朗讀（或還沒有人播）。
  MediaSessionOwner? get owner => _owner;

  /// 靜態方法：供 TTSService 廣播事件給 UI (例如: 章節朗讀完成)
  static void emitEvent(String event) {
    _eventController.add(event);
  }

  /// [owner] 開始播：上一個來源讓出。傳 null 表示朗讀接手。
  void claim(MediaSessionOwner? owner) {
    final previous = _owner;
    if (identical(previous, owner)) return;
    _owner = owner;
    if (previous != null) {
      previous.yieldMedia();
    } else if (owner != null && playbackState.value.playing) {
      // 朗讀正在念：照通知列按暫停的方式停在那一句。
      emitEvent('onPause');
    }
  }

  /// [owner] 不再播放（停止、關掉）：交還控制，通知與鎖定畫面收起。
  void release(MediaSessionOwner owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    mediaItem.add(null);
    playbackState.add(
      PlaybackState(
        controls: _ttsControls(false),
        systemActions: const {MediaAction.playPause},
        playing: false,
        processingState: AudioProcessingState.idle,
      ),
    );
  }

  /// 更新通知欄顯示的書名與作者（朗讀）。
  void updateMetadata({
    required String title,
    required String author,
    String? artUri,
  }) {
    if (_owner != null) return;
    final normalizedArtUri = artUri?.trim();
    mediaItem.add(
      MediaItem(
        id: 'night_reader_tts',
        album: '夜讀朗讀',
        title: title,
        artist: author,
        artUri: normalizedArtUri == null || normalizedArtUri.isEmpty
            ? null
            : Uri.tryParse(normalizedArtUri),
      ),
    );
  }

  /// 朗讀的播放狀態。開始念就接手；有聲書接手後朗讀的「停了」不覆蓋它的。
  void setPlaying(bool playing) {
    if (playing) claim(null);
    if (_owner != null) return;
    playbackState.add(
      playbackState.value.copyWith(
        playing: playing,
        controls: _ttsControls(playing),
        processingState: AudioProcessingState.ready,
      ),
    );
  }

  /// 有聲書的播放資訊（[owner] 是目前的來源才寫）。
  void publish(
    MediaSessionOwner owner, {
    required MediaItem? item,
    required PlaybackState state,
  }) {
    if (!identical(_owner, owner)) return;
    if (item != mediaItem.value) mediaItem.add(item);
    playbackState.add(state);
  }

  // --- 接收來自系統的指令 ---

  Future<void> _send(
    Future<void> Function(MediaSessionOwner owner) toOwner,
    String ttsEvent,
  ) async {
    final owner = _owner;
    if (owner == null) {
      _eventController.add(ttsEvent);
      return;
    }
    try {
      await toOwner(owner);
    } catch (error, stackTrace) {
      AppLog.e('處理播放控制失敗：$ttsEvent', error: error, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> play() => _send((o) => o.onPlay(), 'onPlay');

  @override
  Future<void> pause() => _send((o) => o.onPause(), 'onPause');

  @override
  Future<void> stop() => _send((o) => o.onStop(), 'onStop');

  @override
  Future<void> skipToNext() => _send((o) => o.onSkipToNext(), 'onSkipToNext');

  @override
  Future<void> skipToPrevious() =>
      _send((o) => o.onSkipToPrevious(), 'onSkipToPrevious');

  @override
  Future<void> rewind() => _send((o) => o.onRewind(), 'onRewind');

  @override
  Future<void> fastForward() =>
      _send((o) => o.onFastForward(), 'onFastForward');

  @override
  Future<void> seek(Duration position) =>
      _send((o) => o.onSeek(position), 'onSeek');
}

/// 整個 App 唯一的 [ReaderAudioHandler]；第一次要用時才 `AudioService.init`。
/// 開不起來（例如平台不支援）時是 null，朗讀與有聲書照樣能播，只是沒有
/// 通知與耳機鍵。
class AppAudioSession {
  AppAudioSession._();

  static Future<ReaderAudioHandler?>? _handler;

  /// 跳秒按鈕跳的長度，和播放器的倒退、快轉一致（ADR 0050）。
  static const Duration skipInterval = Duration(seconds: 10);

  static Future<ReaderAudioHandler?> ensure() => _handler ??= _init();

  static Future<ReaderAudioHandler?> _init() async {
    try {
      return await AudioService.init(
        builder: ReaderAudioHandler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.night_reader.tts',
          androidNotificationChannelName: '夜讀播放',
          androidNotificationOngoing: true,
          fastForwardInterval: skipInterval,
          rewindInterval: skipInterval,
        ),
      );
    } catch (error, stackTrace) {
      AppLog.e('系統播放控制開不起來，沒有通知與耳機鍵', error: error, stackTrace: stackTrace);
      return null;
    }
  }
}
