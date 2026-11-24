import 'dart:io';

import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/core/playback/now_playing_artwork.dart';
import 'package:night_reader/core/playback/system_playback.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 換掉 audio_service 的平台：記下送給系統的播放狀態，留著系統按鍵交回來的
/// 入口。
class _RecordingAudioPlatform extends AudioServicePlatform {
  PlaybackStateMessage? state;
  late AudioHandlerCallbacks callbacks;

  @override
  void setHandlerCallbacks(AudioHandlerCallbacks callbacks) =>
      this.callbacks = callbacks;

  @override
  Future<void> configure(ConfigureRequest request) async {}

  @override
  Future<void> setState(SetStateRequest request) async => state = request.state;

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
  int plays = 0;
  int pauses = 0;

  @override
  void onPlay() => plays += 1;
  @override
  void onPause() => pauses += 1;
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

/// 不畫封面：給絕對路徑的 file 網址，audio_service 直接讀檔、不連網。
class _NoArtwork extends NowPlayingArtwork {
  @override
  Future<Uri> resolve(
    String? coverSource,
    String bookName, {
    BookSourceKind kind = BookSourceKind.novel,
    String? origin,
  }) async => Uri.file(
    '${Directory.systemTemp.path}${Platform.pathSeparator}cover.png',
  );
}

void main() {
  // audio_service 把通知上「播放」鈕的動作送成 KEYCODE_MUTE；Android 14 起它
  // 不在 KeyEvent.isMediaSessionKey 裡，MediaController 直接丟掉，夜讀什麼
  // 都收不到。照通知按鈕送鍵的系統（vivo）暫停後按播放就沒反應。
  test('暫停中通知的播放鈕送播放／暫停鍵，按了交給在播的那一方繼續', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tempDir = Directory.systemTemp.createTempSync('playback_play_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    PathProviderPlatform.instance = _TempPaths(tempDir.path);
    final platform = _RecordingAudioPlatform();
    AudioServicePlatform.instance = platform;

    final playback = SystemPlayback(artwork: _NoArtwork());
    await playback.start();
    final owner = _Owner();
    const item = NowPlaying(
      id: 'book#1',
      title: '第 1 章',
      bookName: '書',
      author: '作者',
    );
    playback.show(owner, item: item, playing: true, controls: const {});
    await pumpEventQueue();
    playback.show(owner, item: item, playing: false, controls: const {});
    await pumpEventQueue();

    final state = platform.state!;
    expect(state.playing, isFalse);
    final actions = [for (final control in state.controls) control.action];
    expect(actions, isNot(contains(MediaActionMessage.play)));
    expect(actions, contains(MediaActionMessage.playPause));
    // iPhone 的鎖定畫面照動作開放播放指令，暫停中照舊開著。
    expect(state.systemActions, contains(MediaActionMessage.play));

    await platform.callbacks.click(
      const ClickRequest(button: MediaButtonMessage.media),
    );
    expect(owner.plays, 1);
    expect(owner.pauses, 0);
  });
}
