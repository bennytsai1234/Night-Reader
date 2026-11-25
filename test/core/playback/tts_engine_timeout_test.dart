import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/playback/tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 系統的朗讀服務一直不回話時，初始化與念一句都不能一直等：逾時就當成引擎
/// 出錯，閱讀器的朗讀才停得下來、提示「朗讀引擎出錯，已暫停」。
///
/// 朗讀服務整個 App 一份、會記住開好沒，三種情況照順序在同一份上跑：先讓
/// 初始化卡住（服務沒開成），再讓它正常開好，最後讓念一句卡住。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// 測試用的等待上限，比 [TTSService.engineReplyWait] 短很多。
  const wait = Duration(milliseconds: 500);

  /// 卡住不回的引擎回覆；測試放手後讓卡住的那次呼叫跑完，不留給下一個測試。
  Completer<List<String>>? hangLanguages;
  Completer<int>? hangSpeak;
  final spoken = <String>[];

  /// 等 [future] 完成，最多三秒；沒完成就照現在的狀態繼續斷言。
  Future<void> settle(Future<void> future) async {
    await Future.any([
      future,
      Future<void>.delayed(const Duration(seconds: 3)),
    ]);
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getLanguages':
          final hanging = hangLanguages;
          if (hanging != null) return hanging.future;
          return <String>['zh-TW'];
        case 'getEngines' || 'getVoices':
          return <Object>[];
        case 'speak':
          final hanging = hangSpeak;
          if (hanging != null) return hanging.future;
          spoken.add(call.arguments as String);
          return 1;
      }
      return 1;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );
  });
  tearDownAll(() {
    messenger.setMockMethodCallHandler(channel, null);
    GetIt.instance.reset();
  });

  setUp(() {
    TTSService.debugEngineReplyWait = wait;
    spoken.clear();
  });
  tearDown(() {
    TTSService.debugEngineReplyWait = null;
  });

  test('an engine that never answers initialization fails instead of '
      'waiting forever', () async {
    hangLanguages = Completer<List<String>>();
    final failures = <TtsFailure>[];
    final subscription = TTSService().failures.listen(failures.add);
    var finished = false;

    final speaking = TTSService().speak('甲。');
    unawaited(speaking.whenComplete(() => finished = true));
    await settle(speaking);
    await pumpEventQueue();

    expect(finished, isTrue);
    expect(failures, [TtsFailure.engine]);
    expect(TTSService().isPlaying, isFalse);
    await subscription.cancel();

    // 放手讓卡住的初始化跑完，不留著排隊的呼叫。
    hangLanguages!.complete(<String>['zh-TW']);
    hangLanguages = null;
    await speaking.timeout(const Duration(seconds: 3), onTimeout: () {});
    await pumpEventQueue();
  });

  test('a working engine still initializes and speaks', () async {
    await TTSService().speak('乙。');

    expect(spoken, ['乙。']);
    expect(TTSService().isPlaying, isTrue);
  });

  test('a sentence the engine never answers fails instead of waiting '
      'forever', () async {
    hangSpeak = Completer<int>();
    final failures = <TtsFailure>[];
    final subscription = TTSService().failures.listen(failures.add);
    var finished = false;

    final speaking = TTSService().speak('丙。');
    unawaited(speaking.whenComplete(() => finished = true));
    await settle(speaking);
    await pumpEventQueue();

    expect(finished, isTrue);
    expect(failures, [TtsFailure.engine]);
    expect(TTSService().isPlaying, isFalse);
    await subscription.cancel();

    hangSpeak!.complete(1);
    hangSpeak = null;
    await speaking.timeout(const Duration(seconds: 3), onTimeout: () {});
    await pumpEventQueue();
  });
}
