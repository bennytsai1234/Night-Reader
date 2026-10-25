import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/services/tts_service.dart';
import 'package:night_reader/features/settings/tts_settings_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「朗讀與語音」在朗讀引擎開好之前就打開時，引擎開好後選單跟著更新，
/// 顯示保存的引擎（原本只有開 App 時開引擎，頁面打開時一定已經開好）。
void main() {
  testWidgets('the 朗讀與語音 page shows the saved engine once the engine is up', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreferKey.ttsEngine: 'com.google.android.tts',
    });
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    addTearDown(GetIt.instance.reset);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // 朗讀服務在頁面打開之後才回應（例如開 App 時等超過上限）。
    final engineUp = Completer<void>();
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
      call,
    ) async {
      switch (call.method) {
        case 'getLanguages':
          await engineUp.future;
          return <String>['zh-TW'];
        case 'getEngines':
          return <Map<String, String>>[
            {'name': 'com.google.android.tts', 'label': 'Google 語音'},
          ];
        case 'getVoices':
          return <Object>[];
      }
      return 1;
    });
    // 系統通知欄的播放控制要一個放封面快取的資料夾。
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );

    // 開 App 時開始開引擎：保存的語速讀好了，停在等朗讀服務。
    final starting = TTSService().init();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.values.first, Brightness.dark),
        home: const TtsSettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Google 語音'), findsNothing, reason: '引擎還沒開好');

    engineUp.complete();
    await tester.runAsync(() => starting);
    await tester.pumpAndSettle();
    expect(find.text('Google 語音'), findsOneWidget);
  });
}
