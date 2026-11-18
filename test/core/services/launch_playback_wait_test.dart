import 'dart:async';
import 'dart:io';

import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/services/system_playback/system_playback.dart';
import 'package:night_reader/core/services/tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 馬上開好媒體工作階段的系統。
class _ReadyAudioPlatform extends AudioServicePlatform {
  @override
  void setHandlerCallbacks(AudioHandlerCallbacks callbacks) {}

  @override
  Future<void> configure(ConfigureRequest request) async {}

  @override
  Future<void> setState(SetStateRequest request) async {}

  @override
  Future<void> setMediaItem(SetMediaItemRequest request) async {}

  @override
  Future<void> setQueue(SetQueueRequest request) async {}
}

/// 開 App 的底色只等系統播放資訊的媒體工作階段（ADR 0018），不等朗讀引擎。
void main() {
  testWidgets('launch does not wait for a silent TTS engine', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    addTearDown(GetIt.instance.reset);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // 朗讀服務一直不回應。
    final never = Completer<Object?>();
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) => never.future,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );
    AudioServicePlatform.instance = _ReadyAudioPlatform();
    final playback = SystemPlayback.instance;
    unawaited(TTSService().init());

    var ready = false;
    unawaited(playback.ready().then((_) => ready = true));
    await tester.pump(const Duration(milliseconds: 10));
    expect(ready, isTrue, reason: '媒體工作階段開好就進場，不等朗讀引擎');
  });
}
