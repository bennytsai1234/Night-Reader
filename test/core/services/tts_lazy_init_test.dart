import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/services/tts_service.dart';
import 'package:night_reader/features/settings/settings_provider.dart';
import 'package:night_reader/features/settings/tts_settings_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 朗讀引擎的呼叫在 Android 主執行緒上執行，和 Flutter 畫畫面是同一條：
/// 開 App 時不開引擎，第一次用到才開（2026-10-25，使用者的手機上骨架
/// 長出後半段因此卡住約 0.2 秒）。
void main() {
  final calls = <String>[];

  setUp(() async {
    calls.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreferKey.readerTtsSpeedMultiplier: 1.4,
    });
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
      call,
    ) async {
      calls.add(call.method);
      return call.method == 'getLanguages' ? <String>['zh-TW'] : null;
    });
    // 系統通知欄的播放控制要一個放封面快取的資料夾。
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );
  });

  tearDown(GetIt.instance.reset);

  // 兩個測試共用 TTSService 這個單例，照順序跑：先確認開 App 不開引擎，
  // 再打開設定頁。
  test('launch restores the saved speed without touching the engine', () async {
    SettingsProvider();
    await TTSService().restoreSavedParams();
    expect(TTSService().rate, 1.4);
    expect(calls, isEmpty);
  });

  testWidgets('the 朗讀與語音 page opens the engine', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.values.first, Brightness.dark),
        home: const TtsSettingsPage(),
      ),
    );
    // 開引擎先等系統通知欄的播放控制（測試裡沒有原生端，丟例外後接著做）。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(calls, isNotEmpty);
  });
}
