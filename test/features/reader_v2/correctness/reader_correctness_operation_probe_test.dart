import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/correctness/reader_correctness_foundation.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';

import '../../../reader_correctness/reader_correctness_case_generation.dart';
import 'reader_correctness_host_harness.dart';

List<BookChapter> _fixtureChapters() {
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
    HybridReaderScreen.debugFrameInvariantsEnabled = true;
    HybridReaderScreen.debugVisualOracleEnabled = false;
  });

  tearDown(() {
    HybridReaderScreen.debugFrameInvariantsEnabled = false;
    HybridReaderScreen.debugVisualOracleEnabled = false;
  });

  testWidgets(
    'C5 every atomic operation runs once and records its C2 transition',
    (tester) async {
      final harness = ReaderCorrectnessHostHarness(
        tester,
        chapters: _fixtureChapters(),
      );
      addTearDown(harness.dispose);
      await harness.mount();
      await harness.open();

      for (
        var index = 0;
        index < readerCorrectnessOperationCatalog.length;
        index += 1
      ) {
        final operation = readerCorrectnessOperationCatalog[index];
        final anchor = _probeAnchor(operation, index);
        await harness.positionAt(anchor);
        if (operation.category == 'fling' ||
            operation.category == 'ballistic_interrupt') {
          await harness.primeOrdinaryPrefetchFor(operation);
        }
        harness.resetFrameInvariantHistory();
        final beforeEvidenceCount = harness.operationEvidence.length;
        await harness.applyReaderOperation(operation);
        final evidence = harness.operationEvidence.last;
        expect(harness.operationEvidence.length, beforeEvidenceCount + 1);
        expect(evidence['operation'], operation.id);
        expect(evidence['after'], isNotNull);
        expect(evidence['observedPhase'], isNotEmpty);
        expect(evidence['observedActivity'], isNotEmpty);
        final snapshot = harness.snapshot();
        expect(snapshot['phase'], 'ready');
        expect(snapshot['pumpQueueDepth'], 0);
        expect(snapshot['pendingChapterJumpTarget'], isNull);
        expect(harness.frameInvariantViolations(), isEmpty);
        debugPrint(
          'C5_OPERATION_EVIDENCE operation=${operation.id} '
          'anchor=${anchor.name} expected=${operation.transition} '
          'activity=${evidence['observedActivity']} '
          'phase=${evidence['observedPhase']} '
          'violations=${harness.frameInvariantViolations().length}',
        );
      }
      expect(harness.operationEvidence, hasLength(36));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

ReaderTopologyAnchor _probeAnchor(
  ReaderOperationDefinition operation,
  int index,
) {
  final positions = switch (operation.direction) {
    ReaderOperationDirection.backward => const <ReaderTopologyAnchor>[
      ReaderTopologyAnchor.finalChapterBottom,
      ReaderTopologyAnchor.penultimateChapterTail,
      ReaderTopologyAnchor.veryLongChapter,
      ReaderTopologyAnchor.distantChapter,
    ],
    ReaderOperationDirection.forward => const <ReaderTopologyAnchor>[
      ReaderTopologyAnchor.bookStart,
      ReaderTopologyAnchor.veryShortChapterOne,
      ReaderTopologyAnchor.veryLongChapter,
      ReaderTopologyAnchor.distantChapter,
    ],
    ReaderOperationDirection.none => const <ReaderTopologyAnchor>[
      ReaderTopologyAnchor.firstRegularChapter,
      ReaderTopologyAnchor.exactBoundaryChapter,
      ReaderTopologyAnchor.veryLongChapter,
      ReaderTopologyAnchor.shortPreface,
    ],
  };
  return positions[index % positions.length];
}
