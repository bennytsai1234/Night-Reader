import 'dart:async';
import 'dart:io';

import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/services/system_playback/system_playback.dart';
import 'package:night_reader/core/services/tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 開媒體工作階段時一直不回應的系統。
class _SilentAudioPlatform extends AudioServicePlatform {
  final _never = Completer<void>();

  @override
  void setHandlerCallbacks(AudioHandlerCallbacks callbacks) {}

  @override
  Future<void> configure(ConfigureRequest request) => _never.future;
}

/// 系統一直不回應媒體工作階段時：開 App 的底色最多等
/// [SystemPlayback.launchWait]（ADR 0018），朗讀引擎照樣開。另一個檔案：
/// audio_service 一個程序只能開一次。
void main() {
  testWidgets('silent system playback holds launch only up to the limit and '
      'does not hold the TTS engine', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    addTearDown(GetIt.instance.reset);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final ttsCalls = <String>[];
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
      call,
    ) async {
      ttsCalls.add(call.method);
      return call.method == 'getLanguages' ? <String>['zh-TW'] : 1;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );
    AudioServicePlatform.instance = _SilentAudioPlatform();
    final playback = SystemPlayback.instance;
    unawaited(TTSService().init());

    var ready = false;
    unawaited(playback.ready().then((_) => ready = true));
    await tester.pump(const Duration(milliseconds: 10));
    expect(ttsCalls, contains('getLanguages'), reason: '朗讀引擎不等工作階段');

    await tester.pump(
      SystemPlayback.launchWait - const Duration(milliseconds: 100),
    );
    expect(ready, isFalse, reason: '上限之前一直等');
    await tester.pump(const Duration(milliseconds: 200));
    expect(ready, isTrue, reason: '超過上限就照常進場');
  });
}
