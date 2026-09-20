import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_highlight_follower.dart';

void main() {
  const target = ReaderV2TtsHighlight(
    chapterIndex: 2,
    highlightStart: 40,
    highlightEnd: 52,
  );

  test('failed ensure keeps the target pending and retries later', () async {
    var calls = 0;
    final follower = ReaderV2TtsHighlightFollower(
      ensureHighlightVisible: (_) async {
        calls += 1;
        return calls > 1;
      },
    );

    follower.update(target);
    await Future<void>.delayed(Duration.zero);

    expect(calls, 1);
    expect(follower.lastFollowedHighlight, isNull);
    expect(follower.pendingHighlight, target);

    follower.update(target);
    await Future<void>.delayed(Duration.zero);

    expect(calls, 2);
    expect(follower.lastFollowedHighlight, target);
    expect(follower.pendingHighlight, isNull);
  });

  test('viewport exception is not converted into retryable false', () async {
    final error = StateError('hybrid invariant broke');
    final observed = Completer<Object>();
    late ReaderV2TtsHighlightFollower follower;

    runZonedGuarded(
      () {
        follower = ReaderV2TtsHighlightFollower(
          ensureHighlightVisible: (_) => Future<bool>.error(error),
        );
        follower.update(target);
      },
      (caught, _) {
        if (!observed.isCompleted) observed.complete(caught);
      },
    );

    expect(await observed.future, same(error));
    expect(follower.isFollowing, isFalse);
    expect(follower.pendingHighlight, isNull);
    expect(follower.lastFollowedHighlight, isNull);
  });

  test(
    'a newer highlight supersedes an in-flight target after failure',
    () async {
      final firstEnsure = Completer<bool>();
      final calls = <ReaderV2TtsHighlight>[];
      final follower = ReaderV2TtsHighlightFollower(
        ensureHighlightVisible: (highlight) {
          calls.add(highlight);
          if (highlight == target) return firstEnsure.future;
          return Future<bool>.value(true);
        },
      );
      const newer = ReaderV2TtsHighlight(
        chapterIndex: 2,
        highlightStart: 52,
        highlightEnd: 64,
      );

      follower.update(target);
      await Future<void>.delayed(Duration.zero);
      follower.update(newer);
      firstEnsure.complete(false);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(calls, [target, newer]);
      expect(follower.lastFollowedHighlight, newer);
      expect(follower.pendingHighlight, isNull);
    },
  );
}
