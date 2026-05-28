import 'package:audio_service/audio_service.dart';
import 'dart:async';

/// ReaderAudioHandler - 處理系統媒體控制 (通知欄、鎖屏、藍牙耳機)
/// 專為 TTS 朗讀優化，移除了 MP3 播放邏輯
class ReaderAudioHandler extends BaseAudioHandler {
  static final StreamController<String> _eventController =
      StreamController<String>.broadcast();
  static Stream<String> get eventStream => _eventController.stream;

  ReaderAudioHandler() {
    // 預設狀態為暫停
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.pause,
          MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {MediaAction.seek, MediaAction.playPause},
        playing: false,
        processingState: AudioProcessingState.ready,
      ),
    );
  }

  /// 靜態方法：供 TTSService 廣播事件給 UI (例如: 章節朗讀完成)
  static void emitEvent(String event) {
    _eventController.add(event);
  }

  /// 更新通知欄顯示的書名與作者
  void updateMetadata({
    required String title,
    required String author,
    String? artUri,
  }) {
    mediaItem.add(
      MediaItem(
        id: 'inkpage_tts',
        album: '夜讀朗讀',
        title: title,
        artist: author,
        artUri: artUri != null ? Uri.parse(artUri) : null,
      ),
    );
  }

  /// 同步播放狀態到系統
  void setPlaying(bool playing) {
    playbackState.add(
      playbackState.value.copyWith(
        playing: playing,
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
      ),
    );
  }

  // --- 接收來自系統的指令 ---

  @override
  Future<void> play() async => _eventController.add('onPlay');

  @override
  Future<void> pause() async => _eventController.add('onPause');

  @override
  Future<void> stop() async => _eventController.add('onStop');

  @override
  Future<void> skipToNext() async => _eventController.add('onSkipToNext');

  @override
  Future<void> skipToPrevious() async =>
      _eventController.add('onSkipToPrevious');

  Future<void> onMethodCall(String method, dynamic arguments) async {
    _eventController.add(method);
  }
}
