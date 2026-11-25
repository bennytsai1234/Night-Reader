import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/playback/audio_focus.dart';
import 'package:night_reader/core/playback/tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 假的音訊工作階段：照 `audio_session` 在 Android 上的樣子，已經要過焦點
/// 就直接回給了、不再問系統（[granted] 只在第一次要時算數），放掉才會再問。
class _FakeSession implements AudioFocusPlatform {
  bool granted = true;

  /// iOS 通話中要焦點時丟錯誤。
  bool throws = false;

  /// 朗讀要了幾次（含直接回給了的）；[asked] 是真的問了系統幾次。
  int activations = 0;
  int asked = 0;
  int released = 0;
  bool _requested = false;

  final interruptionEvents = StreamController<AudioInterruptionEvent>();
  final noisyEvents = StreamController<void>();

  @override
  Future<bool> activate() async {
    activations += 1;
    if (throws) throw PlatformException(code: '561017449');
    if (_requested) return true;
    _requested = true;
    asked += 1;
    return granted;
  }

  @override
  Future<void> deactivate() async {
    _requested = false;
    released += 1;
  }

  @override
  Stream<AudioInterruptionEvent> get interruptions => interruptionEvents.stream;

  @override
  Stream<void> get becomingNoisy => noisyEvents.stream;
}

/// 朗讀服務開始念之前向系統要音訊焦點，要不到不念；被打斷與拔耳機時通知
/// 閱讀器的朗讀（`docs/proposals/legado-reading.md` A10、A11）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final spoken = <String>[];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getLanguages':
          return <String>['zh-TW'];
        case 'getEngines' || 'getVoices':
          return <Object>[];
        case 'speak':
          spoken.add(call.arguments as String);
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

  late _FakeSession session;
  late List<TtsFailure> failures;
  late List<AudioFocusChange> changes;
  late List<StreamSubscription<Object?>> subscriptions;

  setUp(() async {
    spoken.clear();
    session = _FakeSession();
    TTSService().audioFocus = AudioFocus(platform: session);
    await TTSService().stop();
    failures = [];
    changes = [];
    subscriptions = [
      TTSService().failures.listen(failures.add),
      TTSService().audioFocusChanges.listen(changes.add),
    ];
  });
  tearDown(() async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  });

  Future<void> finishSentence() => messenger.handlePlatformMessage(
    channel.name,
    channel.codec.encodeMethodCall(const MethodCall('speak.onComplete', true)),
    (_) {},
  );

  test('asks for audio focus once when it starts reading', () async {
    await TTSService().speak('甲。');
    await finishSentence();
    await TTSService().speak('乙。');

    expect(spoken, ['甲。', '乙。']);
    expect(session.activations, 1);

    // 停了再開始是新的一次開始，再要一次。
    await TTSService().stop();
    await TTSService().speak('丙。');
    expect(session.activations, 2);
    expect(failures, isEmpty);
  });

  test('does not speak without audio focus and says why', () async {
    session.granted = false;
    await TTSService().speak('甲。');
    await pumpEventQueue();

    expect(spoken, isEmpty);
    expect(failures, [TtsFailure.noAudioFocus]);
    expect(TTSService().isPlaying, isFalse);

    // 要不到時放掉這次的請求，下次才會真的再問系統。
    expect(session.released, 1);
    session.granted = true;
    await TTSService().speak('甲。');
    expect(session.asked, 2);
    expect(spoken, ['甲。']);
  });

  test('a refusal reported as an error does not speak either', () async {
    session.throws = true;
    await TTSService().speak('甲。');
    await pumpEventQueue();

    expect(spoken, isEmpty);
    expect(failures, [TtsFailure.noAudioFocus]);
  });

  test('while a call has the focus, starting again does not speak; after it '
      'ends it does', () async {
    await TTSService().speak('甲。');
    // Android 來電：暫時被拿走。
    session.interruptionEvents.add(
      AudioInterruptionEvent(true, AudioInterruptionType.pause),
    );
    await pumpEventQueue();
    expect(changes, [AudioFocusChange.interrupted]);

    await TTSService().stop();
    await TTSService().speak('甲。');
    await pumpEventQueue();
    expect(spoken, ['甲。']);
    expect(failures, [TtsFailure.noAudioFocus]);

    session.interruptionEvents.add(
      AudioInterruptionEvent(false, AudioInterruptionType.pause),
    );
    await pumpEventQueue();
    expect(changes.last, AudioFocusChange.regained);
    await TTSService().speak('甲。');
    expect(spoken, ['甲。', '甲。']);
  });

  test('after being interrupted it asks for focus again', () async {
    await TTSService().speak('甲。');
    // iOS 的打斷開始都是 unknown，結束時才說要不要接著播。
    session.interruptionEvents.add(
      AudioInterruptionEvent(true, AudioInterruptionType.unknown),
    );
    session.interruptionEvents.add(
      AudioInterruptionEvent(false, AudioInterruptionType.unknown),
    );
    await pumpEventQueue();
    expect(changes, [AudioFocusChange.interrupted, AudioFocusChange.lost]);

    await TTSService().speak('乙。');
    expect(spoken, ['甲。', '乙。']);
  });

  test('a sound that only lowers the volume is not an interruption', () async {
    await TTSService().speak('甲。');
    session.interruptionEvents.add(
      AudioInterruptionEvent(true, AudioInterruptionType.duck),
    );
    session.interruptionEvents.add(
      AudioInterruptionEvent(false, AudioInterruptionType.duck),
    );
    await pumpEventQueue();
    expect(changes, isEmpty);
  });

  test('unplugging headphones is reported', () async {
    await TTSService().speak('甲。');
    session.noisyEvents.add(null);
    await pumpEventQueue();
    expect(changes, [AudioFocusChange.lost]);
  });
}
