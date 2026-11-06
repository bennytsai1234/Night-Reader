import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/services/tts_service.dart';
import 'package:night_reader/core/sync/settings_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 同步把另一台刪掉的語速、音調套過來時，正在跑的朗讀服務回到預設，
/// 和重開 App 時讀到的一樣，不留著記憶體裡上一次的值。
void main() {
  testWidgets('a synced removal of rate and pitch falls back to the defaults', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreferKey.readerTtsSpeedMultiplier: 1.3,
      PreferKey.readerTtsPitch: 1.4,
    });
    final prefs = await SharedPreferences.getInstance();
    GetIt.instance.registerSingleton<SharedPreferences>(prefs);
    addTearDown(GetIt.instance.reset);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final engineRates = <double>[];
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
      call,
    ) async {
      switch (call.method) {
        case 'setSpeechRate':
          engineRates.add((call.arguments as num).toDouble());
        case 'getLanguages':
          return <String>['zh-TW'];
        case 'getEngines' || 'getVoices':
          return <Object>[];
      }
      return 1;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );

    final tts = TTSService();
    await tester.runAsync(tts.init);
    expect(tts.rate, 1.3);
    expect(tts.pitch, 1.4);

    await prefs.remove(PreferKey.readerTtsSpeedMultiplier);
    await prefs.remove(PreferKey.readerTtsPitch);
    engineRates.clear();
    SettingsSync.applied.value++;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );

    expect(tts.rate, TTSService.defaultRate);
    expect(tts.pitch, TTSService.defaultPitch);
    // flutter_tts 的刻度是 0.5 = 正常速度。
    expect(engineRates, contains(TTSService.defaultRate * 0.5));
  });
}
