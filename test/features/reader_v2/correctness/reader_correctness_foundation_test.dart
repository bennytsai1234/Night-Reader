import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/text/text_preprocessor.dart';

import '../../../reader_correctness/reader_correctness_operations.dart';
import '../../../reader_correctness/reader_correctness_raster.dart';
import 'controlled_chapter_content_source.dart';
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
  test('ink profile encode/decode round-trip and case id are pure', () {
    for (final coordinate in <(int, int)>[
      (0, 0),
      (1, 0),
      (18, 41),
      (60, 41),
      (120, 4),
    ]) {
      final profile = encodeReaderInkProfile(
        chapterIndex: coordinate.$1,
        paragraphIndex: coordinate.$2,
      );
      expect(decodeReaderInkProfile(profile.expectedInkWidths), (
        chapterIndex: coordinate.$1,
        paragraphIndex: coordinate.$2,
      ));
    }
    expect(
      readerCaseId(
        layer: 'pair',
        opSequence: 'flingDownHigh',
        position: 'jumpFar-shortChapterBottom',
        state: 'ballisticTail',
        seed: 9131001,
      ),
      'C-pair-flingDownHigh-jumpFar-shortChapterBottom-ballisticTail-9131001',
    );
  });

  test('ink profile uniqueness checks all fixture paragraphs and rejects collision', () {
    final fixture = ReaderCorrectnessFixture.generate();
    final coordinates = fixture.chapters.expand(
      (chapter) => [
        for (
          var paragraph = 0;
          paragraph < chapter.paragraphs.length;
          paragraph += 1
        )
          (chapterIndex: chapter.index, paragraphIndex: paragraph),
      ],
    );
    expect(() => assertUniqueReaderInkProfiles(coordinates), returnsNormally);
    expect(
      () => assertUniqueReaderInkProfiles([
        (chapterIndex: 3, paragraphIndex: 2),
        (chapterIndex: 3, paragraphIndex: 2),
      ]),
      throwsA(isA<StateError>()),
    );
  });

  testWidgets('S-18 host font distinguishes ink and no-ink rows', (
    tester,
  ) async {
    final profile = encodeReaderInkProfile(
      chapterIndex: 18,
      paragraphIndex: 41,
    );
    final widths = await captureReaderInkWidths(tester, profile);
    expect(widths.map((width) => width > 0).toList(), profile.bits);
    expect(decodeReaderInkProfile(widths), (
      chapterIndex: 18,
      paragraphIndex: 41,
    ));
  });

  testWidgets(
    'host raster decoder round-trips 50 deterministic fixture profiles',
    (tester) async {
      final fixture = ReaderCorrectnessFixture.generate();
      final coordinates = [
        for (final chapter in fixture.chapters)
          for (
            var paragraph = 0;
            paragraph < chapter.paragraphs.length;
            paragraph += 1
          )
            (chapterIndex: chapter.index, paragraphIndex: paragraph),
      ];
      for (var sample = 0; sample < 50; sample += 1) {
        final coordinate =
            coordinates[(sample * 137 + 29) % coordinates.length];
        final profile = encodeReaderInkProfile(
          chapterIndex: coordinate.chapterIndex,
          paragraphIndex: coordinate.paragraphIndex,
        );
        final widths = await captureReaderInkWidths(tester, profile);
        expect(decodeReaderInkProfile(widths), (
          chapterIndex: coordinate.chapterIndex,
          paragraphIndex: coordinate.paragraphIndex,
        ));
      }
      debugPrint(
        'C1_HOST_DECODE decoded=50 totalFixtureParagraphs=${coordinates.length} '
        'seed=$readerCorrectnessFixtureSeed',
      );
    },
  );

  test(
    'S-19 newline ink band survives content and text preprocessing',
    () async {
      final profile = encodeReaderInkProfile(
        chapterIndex: 7,
        paragraphIndex: 3,
      );
      final content = ReaderV2Content.fromRaw(
        chapterIndex: 7,
        title: '第七章',
        rawText: 'P007-003：正文 ${profile.renderBand}\n\n下一段',
      );
      expect(content.displayText, contains('\u2060'));
      expect(content.paragraphs, contains('墨'));
      expect(content.paragraphs, contains('\u2060'));
      final blocks = await const TextPreprocessor(useIsolate: false).process(
        ChapterText(
          id: 7,
          title: content.title,
          paragraphs: content.paragraphs,
          displayText: content.displayText,
          contentHash: content.contentHash,
        ),
      );
      expect(
        blocks.blocks.any((block) => block.text.contains('\u2060')),
        isTrue,
      );
    },
  );

  testWidgets('host topology uses measured real viewport and exposes ten anchors', (
    tester,
  ) async {
    final chapters = _fixtureChapters();
    final harness = ReaderCorrectnessHostHarness(tester, chapters: chapters);
    addTearDown(harness.dispose);
    await harness.mount();
    final measuredIndices = <int>[0, 1, 2, 3, 4, 5, 60, 61, 90, 119, 120];
    final measuredHeights = <int, double>{};
    for (final index in measuredIndices) {
      measuredHeights[index] = (await tester.runAsync(
        () => harness.measureChapterLayout(index),
      ))!.contentHeight;
    }
    debugPrint(
      'C1_TOPOLOGY viewport=${readerCorrectnessViewportWidth}x$readerCorrectnessViewportHeight '
      'heights[0]=${measuredHeights[0]} heights[1]=${measuredHeights[1]} '
      'heights[2]=${measuredHeights[2]} heights[3]=${measuredHeights[3]} '
      'heights[60]=${measuredHeights[60]} heights[61]=${measuredHeights[61]} '
      'heights[119]=${measuredHeights[119]} heights[120]=${measuredHeights[120]}',
    );
    expect(measuredHeights[0], lessThan(readerCorrectnessViewportHeight));
    expect(measuredHeights[1], lessThan(readerCorrectnessViewportHeight));
    expect(measuredHeights[2], lessThan(readerCorrectnessViewportHeight));
    expect(
      measuredHeights[60],
      greaterThanOrEqualTo(readerCorrectnessViewportHeight * 20),
    );
    final regular =
        [
          for (final index in [3, 4, 5, 90, 119, 120]) measuredHeights[index]!,
        ].where(
          (height) =>
              height >= readerCorrectnessViewportHeight * 3 &&
              height <= readerCorrectnessViewportHeight * 6,
        );
    expect(regular.length, greaterThanOrEqualTo(5));
    final boundaryRemainder =
        measuredHeights[61]! % readerCorrectnessViewportHeight;
    final boundaryDistance = [
      boundaryRemainder,
      readerCorrectnessViewportHeight - boundaryRemainder,
    ].reduce((a, b) => a < b ? a : b);
    expect(boundaryDistance, lessThanOrEqualTo(2.1));
    for (final anchor in ReaderTopologyAnchor.values) {
      final location = ReaderCorrectnessFixture.generate().topologyAnchor(
        anchor,
      );
      expect(location.chapterIndex, inInclusiveRange(0, chapters.length - 1));
      expect(
        location.paragraphIndex,
        lessThan(chapters[location.chapterIndex].content!.split('\n\n').length),
      );
    }
  });

  testWidgets(
    'controlled content seam holds, waitUntil observes pending, then releases',
    (tester) async {
      final source = ControlledChapterContentSource();
      final chapters = _fixtureChapters();
      final harness = ReaderCorrectnessHostHarness(
        tester,
        chapters: chapters,
        contentLoader: source.load,
      );
      addTearDown(harness.dispose);
      await harness.mount();
      await harness.open();
      source.hold(3);
      var completed = false;
      final pendingLoad = harness.runtime.loadContentAt(3).then((_) {
        completed = true;
      });
      await harness.waitUntil(
        () => source.isPending(3),
        label: 'chapter 3 pending',
      );
      expect(completed, isFalse);
      source.release(3);
      await pendingLoad;
      expect(completed, isTrue);
    },
  );

  testWidgets('waitUntil timeout fails with the current snapshot', (
    tester,
  ) async {
    final harness = ReaderCorrectnessHostHarness(
      tester,
      chapters: _fixtureChapters(),
    );
    addTearDown(harness.dispose);
    await harness.mount();
    Object? error;
    try {
      await harness.waitUntil(
        () => false,
        timeout: const Duration(milliseconds: 16),
        label: 'intentional timeout',
      );
    } catch (caught) {
      error = caught;
    }
    expect(error, isNotNull);
    expect(error.toString(), contains('intentional timeout'));
    expect(error.toString(), contains('phase'));
  });

  testWidgets('shared drag and fling operations run on the real host harness', (
    tester,
  ) async {
    final harness = ReaderCorrectnessHostHarness(
      tester,
      chapters: _fixtureChapters(),
    );
    addTearDown(harness.dispose);
    final setupStopwatch = Stopwatch()..start();
    await harness.mount();
    await harness.open();
    setupStopwatch.stop();
    debugPrint(
      'C1_CASE_COST single_case_setup_open_settle_ms=${setupStopwatch.elapsedMicroseconds / 1000}',
    );
    final stopwatch = Stopwatch()..start();
    for (final operation in readerCorrectnessTemplateOperations) {
      final caseId = readerCaseId(
        layer: 'host',
        opSequence: operation.id,
        position: 'bookStart',
        state: 'ready',
        seed: readerCorrectnessFixtureSeed,
      );
      expect(caseId, startsWith('C-host-${operation.id}-'));
      await operation.apply(harness);
      await harness.settle();
    }
    stopwatch.stop();
    debugPrint(
      'C1_CASE_COST operations=${readerCorrectnessTemplateOperations.length} '
      'setup_open_settle_elapsed_ms=${stopwatch.elapsedMilliseconds}',
    );
  });
}
