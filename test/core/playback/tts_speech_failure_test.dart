import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/playback/tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 念一段沒念出來時，朗讀服務送一次 [TTSService.failures]，閱讀器的朗讀才
/// 不會一直停在「朗讀中」。朗讀服務整個 App 一份、會記住開好沒，三種情況
/// 照順序在同一份上跑。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var engineAvailable = false;
  var acceptsSpeech = true;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getLanguages':
          if (!engineAvailable) {
            throw PlatformException(code: 'no_engine');
          }
          return <String>['zh-TW'];
        case 'getEngines' || 'getVoices':
          return <Object>[];
        case 'speak':
          return acceptsSpeech ? 1 : 0;
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

  Future<int> failuresWhile(Future<void> Function() action) async {
    var failures = 0;
    final subscription = TTSService().failures.listen((_) => failures++);
    await action();
    await pumpEventQueue();
    await subscription.cancel();
    return failures;
  }

  test('speaking without a usable engine reports a failure', () async {
    final failures = await failuresWhile(() => TTSService().speak('甲。'));

    expect(failures, 1);
    expect(TTSService().isPlaying, isFalse);
  });

  test('an engine that turns the text down reports a failure', () async {
    engineAvailable = true;
    acceptsSpeech = false;
    final failures = await failuresWhile(() => TTSService().speak('甲。'));

    expect(failures, 1);
    expect(TTSService().isPlaying, isFalse);
  });

  test('an error while speaking reports a failure', () async {
    acceptsSpeech = true;
    final failures = await failuresWhile(() async {
      await TTSService().speak('甲。');
      expect(TTSService().isPlaying, isTrue);
      await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          const MethodCall('speak.onError', 'synthesis failed'),
        ),
        (_) {},
      );
    });

    expect(failures, 1);
    expect(TTSService().isPlaying, isFalse);
  });

  test('a sentence spoken to the end is not a failure', () async {
    final failures = await failuresWhile(() async {
      await TTSService().speak('甲。');
      await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          const MethodCall('speak.onComplete', true),
        ),
        (_) {},
      );
    });

    expect(failures, 0);
  });
}
