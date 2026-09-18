import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/tts_speech_coordinator.dart';

void main() {
  test(
    'stop during delayed initialization cancels the pending speak',
    () async {
      final coordinator = TtsSpeechCoordinator();
      final initialization = Completer<bool>();
      var speakCalls = 0;
      var stopCalls = 0;

      final speakFuture = coordinator.speak(
        prepare: () => initialization.future,
        speak: () async => speakCalls += 1,
      );
      await Future<void>.delayed(Duration.zero);

      await coordinator.stop(stop: () async => stopCalls += 1);
      initialization.complete(true);
      await speakFuture;

      expect(stopCalls, 1);
      expect(speakCalls, 0);
    },
  );

  test('a newer speak request supersedes an older prepared request', () async {
    final coordinator = TtsSpeechCoordinator();
    final firstPreparation = Completer<bool>();
    final spoken = <String>[];

    final first = coordinator.speak(
      prepare: () => firstPreparation.future,
      speak: () async => spoken.add('first'),
    );
    final second = coordinator.speak(
      prepare: () async => true,
      speak: () async => spoken.add('second'),
    );
    firstPreparation.complete(true);
    await Future.wait(<Future<void>>[first, second]);

    expect(spoken, ['second']);
  });
}
