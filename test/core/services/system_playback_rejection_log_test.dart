import 'dart:io';

import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/system_playback/now_playing_artwork.dart';
import 'package:night_reader/core/services/system_playback/system_playback.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 每次送播放狀態都被拒收的系統，例如通知按鈕圖示被發布版刪掉時。
class _RejectingAudioPlatform extends AudioServicePlatform {
  @override
  void setHandlerCallbacks(AudioHandlerCallbacks callbacks) {}

  @override
  Future<void> configure(ConfigureRequest request) async {}

  @override
  Future<void> setState(SetStateRequest request) async {
    if (request.state.processingState == AudioProcessingStateMessage.idle) {
      return;
    }
    throw PlatformException(
      code: 'You must specify an icon resource id to build a CustomAction',
    );
  }

  @override
  Future<void> setMediaItem(SetMediaItemRequest request) async {}

  @override
  Future<void> setQueue(SetQueueRequest request) async {}

  @override
  Future<void> setAndroidPlaybackInfo(
    SetAndroidPlaybackInfoRequest request,
  ) async {}

  @override
  Future<void> stopService(StopServiceRequest request) async {}
}

class _TempPaths extends PathProviderPlatform {
  _TempPaths(this.path);

  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Owner implements PlaybackOwner {
  @override
  void onPlay() {}
  @override
  void onPause() {}
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

void main() {
  test('系統一直拒收播放資訊時，同一個錯誤只記一筆', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tempDir = Directory.systemTemp.createTempSync('playback_reject_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    PathProviderPlatform.instance = _TempPaths(tempDir.path);
    AudioServicePlatform.instance = _RejectingAudioPlatform();
    final logs = <String>[];
    AppLog.delegate = (message, error, stackTrace, toast) => logs.add(message);
    addTearDown(() => AppLog.delegate = null);

    final playback = SystemPlayback(
      artwork: NowPlayingArtwork(directory: () async => tempDir),
    );
    await playback.start();
    final owner = _Owner();
    NowPlaying chapter(int index) => NowPlaying(
      id: 'book#$index',
      title: '第 $index 章',
      bookName: '書',
      author: '作者',
    );
    // 播放、暫停、換章：每次都送一次播放狀態，每次都被拒收。
    for (final (item, playing) in [
      (chapter(1), true),
      (chapter(1), false),
      (chapter(2), true),
    ]) {
      playback.show(owner, item: item, playing: playing, controls: const {});
      await pumpEventQueue();
    }

    final rejections = logs.where((m) => m.contains('rejected')).toList();
    expect(rejections, hasLength(1));
    expect(rejections.single, contains('CustomAction'));
  });
}
