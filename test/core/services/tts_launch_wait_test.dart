import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/services/tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 開 App 的底色等朗讀引擎開好才長骨架（ADR 0018），但系統的朗讀服務一直
/// 不回應時，最多等 [TTSService.launchWait] 就照常進場。
void main() {
  testWidgets('launch stops waiting for a silent engine after the limit', (
    tester,
  ) async {
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

    var ready = false;
    unawaited(TTSService().ready().then((_) => ready = true));
    await tester.pump(
      TTSService.launchWait - const Duration(milliseconds: 100),
    );
    expect(ready, isFalse, reason: '上限之前一直等');
    await tester.pump(const Duration(milliseconds: 200));
    expect(ready, isTrue, reason: '超過上限就照常進場');
  });
}
