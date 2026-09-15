import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

import '../../../reader_correctness/reader_correctness_operations.dart';
import 'reader_correctness_host_harness.dart';

const BlockKey _center = BlockKey(chapterIndex: 0, blockIndex: 0);

HybridFrameInvariantRecord _record({
  int timestampMicros = 1,
  String phase = 'ready',
  double scrollOffset = 0,
  bool dragging = false,
  bool isScrolling = false,
  bool restoreLocked = false,
  bool initialRestoreCompleted = true,
  ReaderV2Location? pendingChapterJumpTarget,
  int epoch = 1,
  int layoutGeneration = 1,
  int documentIndexRevision = 1,
  int resetGeneration = 1,
  int indexBindingResetGeneration = 1,
  List<BlockKey> visibleKeys = const <BlockKey>[_center],
  List<int> visibleChapters = const <int>[0],
  int missingParagraphCount = 0,
  int unloadedChapterCount = 0,
  int? dominantVisibleChapter = 0,
  int? displayedProgressChapter = 0,
  int pumpQueueDepth = 0,
  double? scrollPixels = 0,
  double? minScrollExtent = 0,
  double? maxScrollExtent = 1000,
  String scrollActivity = 'idle',
  double? scrollVelocity = 0,
  int? operationTokenId = 1,
  bool operationIsCurrent = true,
  int chapterCount = 2,
  bool errorPresent = false,
}) {
  return HybridFrameInvariantRecord(
    timestampMicros: timestampMicros,
    phase: phase,
    scrollOffset: scrollOffset,
    viewportHeight: 1000,
    dragging: dragging,
    isScrolling: isScrolling,
    restoreLocked: restoreLocked,
    initialRestoreCompleted: initialRestoreCompleted,
    pendingChapterJumpTarget: pendingChapterJumpTarget,
    epoch: epoch,
    layoutGeneration: layoutGeneration,
    documentIndexRevision: documentIndexRevision,
    resetGeneration: resetGeneration,
    indexBindingResetGeneration: indexBindingResetGeneration,
    indexCenter: _center,
    visibleKeys: visibleKeys,
    visibleChapters: visibleChapters,
    missingParagraphCount: missingParagraphCount,
    unloadedChapterCount: unloadedChapterCount,
    dominantVisibleChapter: dominantVisibleChapter,
    displayedProgressChapter: displayedProgressChapter,
    pumpQueueDepth: pumpQueueDepth,
    scrollPixels: scrollPixels,
    minScrollExtent: minScrollExtent,
    maxScrollExtent: maxScrollExtent,
    scrollActivity: scrollActivity,
    scrollVelocity: scrollVelocity,
    operationTokenId: operationTokenId,
    operationIsCurrent: operationIsCurrent,
    chapterCount: chapterCount,
    errorPresent: errorPresent,
  );
}

Set<String> _invariants(List<HybridFrameInvariantViolation> violations) {
  return violations.map((violation) => violation.invariant).toSet();
}

void _expectOnlyInvariant(
  List<HybridFrameInvariantViolation> violations,
  String invariant,
) {
  expect(_invariants(violations), contains(invariant));
}

List<BookChapter> _harnessChapters() {
  final fixture = ReaderCorrectnessFixture.generate();
  return [
    for (final chapter in fixture.chapters)
      BookChapter(
        url: 'fixture://${chapter.index}',
        title: chapter.title,
        bookUrl: 'correctness://reader-v2',
        index: chapter.index,
        content: chapter.content,
      ),
  ];
}

void main() {
  setUp(() {
    HybridReaderScreen.debugFrameInvariantsEnabled = false;
  });

  tearDown(() {
    HybridReaderScreen.debugFrameInvariantsEnabled = false;
  });

  group('C2 runtime oracle injection proofs', () {
    test('I9 positive: ready frame with no visible keys is rejected', () {
      final violations = evaluateHybridFrameInvariants(
        current: _record(visibleKeys: const <BlockKey>[]),
      );
      _expectOnlyInvariant(violations, 'I9');
    });

    test('I9 negative: ready frame with one visible key is accepted', () {
      final violations = evaluateHybridFrameInvariants(current: _record());
      expect(_invariants(violations), isNot(contains('I9')));
    });

    test('I11 positive: unsolicited ballistic transition is rejected', () {
      final violations = evaluateHybridFrameInvariants(
        current: _record(
          scrollActivity: 'ballistic',
          isScrolling: true,
          scrollVelocity: 600,
        ),
        previous: _record(),
      );
      _expectOnlyInvariant(violations, 'I11');
    });

    test('I11 negative: ballistic continuing from a user drag is accepted', () {
      final violations = evaluateHybridFrameInvariants(
        current: _record(
          scrollActivity: 'ballistic',
          isScrolling: true,
          scrollVelocity: 600,
        ),
        previous: _record(
          dragging: true,
          isScrolling: true,
          scrollActivity: 'drag',
          scrollVelocity: 0,
        ),
      );
      expect(_invariants(violations), isNot(contains('I11')));
    });

    test("I12' positive: ballistic velocity reversal is rejected", () {
      final violations = evaluateHybridFrameInvariants(
        current: _record(
          timestampMicros: 2,
          scrollActivity: 'ballistic',
          isScrolling: true,
          scrollVelocity: -50,
        ),
        previous: _record(
          scrollActivity: 'ballistic',
          isScrolling: true,
          scrollVelocity: 100,
        ),
      );
      _expectOnlyInvariant(violations, 'I8');
      expect(violations.single.reason, contains("I12'"));
    });

    test("I12' negative: same-direction ballistic velocity is accepted", () {
      final violations = evaluateHybridFrameInvariants(
        current: _record(
          timestampMicros: 2,
          scrollActivity: 'ballistic',
          isScrolling: true,
          scrollVelocity: 50,
        ),
        previous: _record(
          scrollActivity: 'ballistic',
          isScrolling: true,
          scrollVelocity: 100,
        ),
      );
      expect(
        violations.where((violation) => violation.reason.contains("I12'")),
        isEmpty,
      );
    });

    test("I13 positive: ballistic velocity growth beyond bounded jitter is rejected", () {
      final violations = evaluateHybridFrameInvariants(
        current: _record(
          timestampMicros: 2,
          scrollActivity: 'ballistic',
          isScrolling: true,
          scrollVelocity: 700,
        ),
        previous: _record(
          scrollActivity: 'ballistic',
          isScrolling: true,
          scrollVelocity: 100,
        ),
      );
      _expectOnlyInvariant(violations, 'I8');
      expect(violations.single.reason, contains("I13'"));
    });

    test(
      "I13 negative: ballistic velocity within 5% sampling jitter is accepted",
      () {
        final violations = evaluateHybridFrameInvariants(
          current: _record(
            timestampMicros: 2,
            scrollActivity: 'ballistic',
            isScrolling: true,
            scrollVelocity: 104,
          ),
          previous: _record(
            scrollActivity: 'ballistic',
            isScrolling: true,
            scrollVelocity: 100,
          ),
        );
        expect(
          violations.where((violation) => violation.reason.contains("I13'")),
          isEmpty,
        );
      },
    );

    test("I14' positive: same-owner cross-viewport teleport is rejected", () {
      final violations = evaluateHybridFrameInvariants(
        current: _record(
          timestampMicros: 2,
          scrollPixels: 1101,
          maxScrollExtent: 2000,
        ),
        previous: _record(maxScrollExtent: 2000),
      );
      _expectOnlyInvariant(violations, 'I8');
      expect(violations.single.reason, contains("I14'"));
    });

    test("I14' negative: high-speed ballistic displacement within one viewport is accepted", () {
      final violations = evaluateHybridFrameInvariants(
        current: _record(
          timestampMicros: 2,
          scrollPixels: 900,
          scrollActivity: 'ballistic',
          isScrolling: true,
          scrollVelocity: 9000,
        ),
        previous: _record(
          scrollActivity: 'ballistic',
          isScrolling: true,
          scrollVelocity: 9500,
        ),
      );
      expect(
        violations.where((violation) => violation.reason.contains("I14'")),
        isEmpty,
      );
    });

    test(
      'I15 positive: non-finite or out-of-range scroll geometry is rejected',
      () {
        final violations = evaluateHybridFrameInvariants(
          current: _record(scrollPixels: 1001),
        );
        _expectOnlyInvariant(violations, 'I15');
      },
    );

    test(
      'I15 negative: finite scroll geometry inside both extents is accepted',
      () {
        final violations = evaluateHybridFrameInvariants(
          current: _record(scrollPixels: 500),
        );
        expect(_invariants(violations), isNot(contains('I15')));
      },
    );

    test('I16 positive: first chapter crossing document top is rejected', () {
      final violations = evaluateHybridFrameInvariants(
        current: _record(scrollPixels: -1),
      );
      _expectOnlyInvariant(violations, 'I16');
    });

    test('I16 negative: first chapter exactly at document top is accepted', () {
      final violations = evaluateHybridFrameInvariants(current: _record());
      expect(_invariants(violations), isNot(contains('I16')));
    });

    test(
      'I17 positive: final chapter crossing document bottom is rejected',
      () {
        final violations = evaluateHybridFrameInvariants(
          current: _record(
            scrollPixels: 1001,
            visibleChapters: const <int>[1],
            dominantVisibleChapter: 1,
            displayedProgressChapter: 1,
          ),
        );
        _expectOnlyInvariant(violations, 'I17');
      },
    );

    test(
      'I17 negative: final chapter exactly at document bottom is accepted',
      () {
        final violations = evaluateHybridFrameInvariants(
          current: _record(
            scrollPixels: 1000,
            visibleChapters: const <int>[1],
            dominantVisibleChapter: 1,
            displayedProgressChapter: 1,
          ),
        );
        expect(_invariants(violations), isNot(contains('I17')));
      },
    );

    test('I18 positive: pending operation without an owner is rejected', () {
      final violations = evaluateHybridFrameInvariants(
        current: _record(
          phase: 'layingOut',
          pendingChapterJumpTarget: const ReaderV2Location(
            chapterIndex: 4,
            charOffset: 0,
          ),
          operationTokenId: null,
        ),
      );
      _expectOnlyInvariant(violations, 'I18');
    });

    test(
      'I18 negative: pending operation with one token owner is accepted',
      () {
        final violations = evaluateHybridFrameInvariants(
          current: _record(
            phase: 'layingOut',
            pendingChapterJumpTarget: const ReaderV2Location(
              chapterIndex: 4,
              charOffset: 0,
            ),
            operationTokenId: 8,
          ),
        );
        expect(_invariants(violations), isNot(contains('I18')));
      },
    );

    test(
      'I19 positive: a lower token cannot remain current after a newer request',
      () {
        final violations = evaluateHybridFrameInvariants(
          current: _record(operationTokenId: 4, operationIsCurrent: true),
          previous: _record(operationTokenId: 5),
        );
        _expectOnlyInvariant(violations, 'I19');
      },
    );

    test(
      'I19 negative: a newer monotonically increasing token is accepted',
      () {
        final violations = evaluateHybridFrameInvariants(
          current: _record(operationTokenId: 6, operationIsCurrent: true),
          previous: _record(operationTokenId: 5),
        );
        expect(_invariants(violations), isNot(contains('I19')));
      },
    );

    test('I20 positive: stale token changing scroll pixels is rejected', () {
      final violations = evaluateHybridFrameInvariants(
        current: _record(
          operationTokenId: 5,
          operationIsCurrent: false,
          scrollPixels: 20,
        ),
        previous: _record(operationTokenId: 5, scrollPixels: 10),
      );
      _expectOnlyInvariant(violations, 'I20');
    });

    test(
      'I20 negative: stale token with unchanged scroll pixels is accepted',
      () {
        final violations = evaluateHybridFrameInvariants(
          current: _record(operationTokenId: 5, operationIsCurrent: false),
          previous: _record(operationTokenId: 5),
        );
        expect(_invariants(violations), isNot(contains('I20')));
      },
    );

    test('I21 positive: a generation or revision decrease is rejected', () {
      final violations = evaluateHybridFrameInvariants(
        current: _record(documentIndexRevision: 0),
        previous: _record(documentIndexRevision: 1),
      );
      _expectOnlyInvariant(violations, 'I21');
    });

    test(
      'I21 negative: background admission revision increase is accepted',
      () {
        final violations = evaluateHybridFrameInvariants(
          current: _record(documentIndexRevision: 2),
          previous: _record(documentIndexRevision: 1),
        );
        expect(_invariants(violations), isNot(contains('I21')));
      },
    );

    test(
      'I24 positive: ready frame retaining an error after recovery is rejected',
      () {
        final violations = evaluateHybridFrameInvariants(
          current: _record(errorPresent: true),
          previous: _record(phase: 'error', errorPresent: true),
        );
        _expectOnlyInvariant(violations, 'I24');
      },
    );

    test('I24 negative: ready frame explicitly clears the recovered error', () {
      final violations = evaluateHybridFrameInvariants(
        current: _record(errorPresent: false),
        previous: _record(phase: 'error', errorPresent: true),
      );
      expect(_invariants(violations), isNot(contains('I24')));
    });

    test('I26 positive: progress chapter jump without explicit navigation is rejected', () {
      final violations = evaluateHybridFrameInvariants(
        current: _record(
          displayedProgressChapter: 1,
          dominantVisibleChapter: 1,
        ),
        previous: _record(),
      );
      _expectOnlyInvariant(violations, 'I26');
    });

    test(
      'I26 negative: progress chapter change with a pending jump is accepted',
      () {
        final violations = evaluateHybridFrameInvariants(
          current: _record(
            operationTokenId: 2,
            displayedProgressChapter: 1,
            dominantVisibleChapter: 1,
          ),
          previous: _record(
            operationTokenId: 1,
            pendingChapterJumpTarget: const ReaderV2Location(
              chapterIndex: 1,
              charOffset: 0,
            ),
          ),
        );
        expect(_invariants(violations), isNot(contains('I26')));
      },
    );

    test('record JSON exposes the ten C2 scalar fields', () {
      final json = _record(
        pumpQueueDepth: 3,
        scrollPixels: 10,
        minScrollExtent: 0,
        maxScrollExtent: 100,
        scrollActivity: 'ballistic',
        scrollVelocity: 42,
        operationTokenId: 7,
        operationIsCurrent: true,
        chapterCount: 121,
        errorPresent: false,
      ).toJson();
      expect(json['pumpQueueDepth'], 3);
      expect(json['scrollPixels'], 10);
      expect(json['minScrollExtent'], 0);
      expect(json['maxScrollExtent'], 100);
      expect(json['scrollActivity'], 'ballistic');
      expect(json['scrollVelocity'], 42);
      expect(json['operationTokenId'], 7);
      expect(json['operationIsCurrent'], true);
      expect(json['chapterCount'], 121);
      expect(json['errorPresent'], false);
    });
  });

  testWidgets(
    'C1 host harness captures drag-ballistic-idle, velocity, queue, and token transitions',
    (tester) async {
      HybridReaderScreen.debugFrameInvariantsEnabled = true;
      final releaseChapter62 = Completer<String?>();
      var holdChapter62 = true;
      final chapters = _harnessChapters();
      final harness = ReaderCorrectnessHostHarness(
        tester,
        chapters: chapters,
        contentLoader: (chapterIndex, chapter) {
          if (holdChapter62 && chapterIndex == 62) {
            return releaseChapter62.future;
          }
          return Future<String?>.value(chapter.content);
        },
      );
      addTearDown(harness.dispose);

      await harness.mount();
      await harness.open();
      harness.resetFrameInvariantHistory();
      final reader = find.byType(HybridReaderScreen).last;
      final gesture = await tester.startGesture(tester.getCenter(reader));
      // Give the real ScrollPosition one post-frame sample while the pointer
      // is down. This is the earliest observable DragScrollActivity sample;
      // the shared C1 fling helper otherwise reaches ballistic before the
      // hook's post-frame callback reads activity.
      await tester.pump();
      await moveVsyncPaced(
        tester,
        gesture,
        const Offset(0, -620),
        duration: const Duration(milliseconds: 180),
      );
      await gesture.up();
      await harness.waitUntil(
        () => harness.frameInvariantRecords().any(
          (record) => record['scrollActivity'] == 'ballistic',
        ),
        label: 'real ballistic activity',
      );
      await harness.settle();

      final beforeJumpRecords = harness.frameInvariantRecords();
      final activities = beforeJumpRecords
          .map((record) => record['scrollActivity'])
          .whereType<String>()
          .toSet();
      final ballisticVelocities = beforeJumpRecords
          .where((record) => record['scrollActivity'] == 'ballistic')
          .map((record) => (record['scrollVelocity'] as num?)?.toDouble())
          .whereType<double>()
          .toList();
      final queueDepths = beforeJumpRecords
          .map((record) => record['pumpQueueDepth'] as int)
          .toSet();
      final flingToken = beforeJumpRecords.last['operationTokenId'] as int?;

      debugPrint(
        'C2_HOST_FLING_RECORDS frames=${beforeJumpRecords.length} '
        'activities=${activities.toList()..sort()} '
        'activityDragging=${beforeJumpRecords.map((record) => '${record['scrollActivity']}/${record['dragging']}').toSet().toList()} '
        'velocityFirstLast=${ballisticVelocities.isEmpty ? null : '${ballisticVelocities.first}->${ballisticVelocities.last}'} '
        'velocityNonZero=${ballisticVelocities.any((value) => value.abs() > 0)} '
        'queueDepths=${queueDepths.toList()..sort()} '
        'operationTokenId=$flingToken',
      );
      expect(activities, contains('drag'));
      expect(activities, contains('ballistic'));
      expect(activities, contains('idle'));
      expect(ballisticVelocities, isNotEmpty);
      expect(ballisticVelocities.any((value) => value.abs() > 0), isTrue);

      final tokenBeforeJump =
          beforeJumpRecords.last['operationTokenId'] as int?;
      final jump = harness.runtime.jumpToChapter(60);
      // The target chapter is available immediately, but chapter 62 is held
      // after the restore window starts. This keeps the jump-owned layout
      // queue observable for at least one shared-vsync sample instead of
      // racing a complete bounded restore before the post-frame hook runs.
      for (var i = 0; i < 64; i += 1) {
        await pumpVsyncPaced(tester, readerVsyncStep);
        final records = harness.frameInvariantRecords();
        final observedNewToken = records.any(
          (record) =>
              tokenBeforeJump != null &&
              (record['operationTokenId'] as int?) != null &&
              (record['operationTokenId'] as int) > tokenBeforeJump,
        );
        final observedQueue = records.any(
          (record) => (record['pumpQueueDepth'] as int) > 0,
        );
        if (observedNewToken && observedQueue) break;
      }
      final duringJumpRecords = harness.frameInvariantRecords();
      final duringJumpTokenObserved = duringJumpRecords.any(
        (record) =>
            tokenBeforeJump != null &&
            (record['operationTokenId'] as int?) != null &&
            (record['operationTokenId'] as int) > tokenBeforeJump,
      );
      final duringJumpQueueDepths = duringJumpRecords
          .map((record) => record['pumpQueueDepth'] as int)
          .toSet();
      debugPrint(
        'C2_HOST_JUMP_DURING tokenBefore=$tokenBeforeJump '
        'tokenObserved=$duringJumpTokenObserved '
        'queueDepths=${duringJumpQueueDepths.toList()..sort()}',
      );
      expect(tokenBeforeJump, isNotNull);
      expect(duringJumpTokenObserved, isTrue);
      expect(duringJumpQueueDepths.any((depth) => depth > 0), isTrue);

      holdChapter62 = false;
      releaseChapter62.complete(chapters[62].content);
      await jump;
      await harness.settle();
      final afterJumpRecords = harness.frameInvariantRecords();
      final tokenAfterJump = afterJumpRecords
          .map((record) => record['operationTokenId'] as int?)
          .whereType<int>()
          .fold<int?>(
            null,
            (max, value) => max == null || value > max ? value : max,
          );
      final allQueueDepths = afterJumpRecords
          .map((record) => record['pumpQueueDepth'] as int)
          .toSet();
      debugPrint(
        'C2_HOST_JUMP_RECORD tokenBefore=$tokenBeforeJump '
        'tokenAfter=$tokenAfterJump chapterCount='
        '${afterJumpRecords.last['chapterCount']} '
        'queueDepths=${allQueueDepths.toList()..sort()}',
      );
      expect(tokenAfterJump, greaterThan(tokenBeforeJump!));
      expect(allQueueDepths, contains(0));
      expect(harness.frameInvariantViolations(), isEmpty);
    },
  );
}
