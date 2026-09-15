import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/correctness/reader_correctness_visual_oracle.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/hybrid/text/text_preprocessor.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_engine.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';

import '../../../reader_correctness/reader_correctness_case_generation.dart';
import '../../../reader_correctness/reader_correctness_operations.dart';

class _FakeBookDao extends Fake implements BookDao {
  @override
  Future<void> updateProgress(
    String bookUrl,
    int chapterIndex,
    String chapterTitle,
    int pos, {
    double visualOffsetPx = 0.0,
    String? readerAnchorJson,
  }) async {}
}

class _FakeChapterDao extends Fake implements ChapterDao {}

class _FakeSourceDao extends Fake implements BookSourceDao {}

final class ReaderCorrectnessHostHarness
    implements ReaderCorrectnessOperationHarness {
  ReaderCorrectnessHostHarness(
    this.tester, {
    required this.chapters,
    ReaderV2TestContentLoader? contentLoader,
  }) : _contentLoader = contentLoader {
    book = Book(
      bookUrl: 'correctness://reader-v2',
      name: 'Reader correctness fixture',
      author: 'C1',
      origin: 'local',
      originName: 'test',
    );
    final bookDao = _FakeBookDao();
    final repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: chapters,
      bookDao: bookDao,
      chapterDao: _FakeChapterDao(),
      sourceDao: _FakeSourceDao(),
      contentLoader: _contentLoader,
    );
    runtime = ReaderV2Runtime(
      book: book,
      repository: repository,
      layoutEngine: ReaderV2LayoutEngine(),
      progressController: ReaderV2ProgressController(
        book: book,
        repository: repository,
        bookDao: bookDao,
      ),
      initialLayoutSpec: ReaderV2LayoutSpec.fromViewport(
        viewportSize: readerCorrectnessViewportSize,
        style: _layoutStyle,
      ),
    );
  }

  static const ReaderV2Style style = ReaderV2Style(
    fontSize: 18,
    lineHeight: 1.5,
    letterSpacing: 0,
    paragraphSpacing: 0.8,
    paddingTop: 12,
    paddingBottom: 0,
    paddingLeft: 12,
    paddingRight: 12,
    textIndent: 2,
  );

  static const ReaderV2LayoutStyle _layoutStyle = ReaderV2LayoutStyle(
    fontSize: 18,
    lineHeight: 1.5,
    letterSpacing: 0,
    paragraphSpacing: 0.8,
    paddingTop: 12,
    paddingBottom: 0,
    paddingLeft: 12,
    paddingRight: 12,
    textIndent: 2,
  );

  final WidgetTester tester;
  final List<BookChapter> chapters;
  final ReaderV2TestContentLoader? _contentLoader;
  late final Book book;
  late final ReaderV2Runtime runtime;
  final ReaderV2ViewportController viewportController =
      ReaderV2ViewportController();

  bool _mounted = true;
  bool _opened = false;

  /// A compact record of the real C2 state transition observed for each
  /// operation probe. It is intentionally kept outside production code and is
  /// emitted by the C5 fast-lane test as evidence, not as an assertion source.
  final List<Map<String, Object?>> operationEvidence = <Map<String, Object?>>[];

  Future<void> mount() async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: readerCorrectnessViewportSize.width,
            height: readerCorrectnessViewportSize.height,
            child: HybridReaderScreen(
              runtime: runtime,
              backgroundColor: const Color(0xFFFFFFFF),
              textColor: const Color(0xFF000000),
              style: style,
              viewportController: viewportController,
              preprocessor: const TextPreprocessor(useIsolate: false),
              enableDiskMetrics: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> open() async {
    if (!_opened) {
      _opened = true;
      unawaited(runtime.openBook());
    }
    await settle();
  }

  Future<void> settle({
    Duration timeout = const Duration(seconds: 30),
    String label = 'settle',
  }) async {
    await waitUntil(
      () {
        final current = snapshot();
        return current['phase'] == 'ready' &&
            current['initialRestoreCompleted'] == true &&
            current['isScrolling'] == false &&
            current['pumpQueueDepth'] == 0 &&
            current['visibleKeysContiguous'] == true &&
            (current['missingParagraphKeys'] as List<dynamic>).isEmpty &&
            current['pendingChapterJumpTarget'] == null;
      },
      timeout: timeout,
      label: label,
    );
  }

  Future<void> waitUntil(
    bool Function() predicate, {
    Duration timeout = const Duration(seconds: 5),
    String label = 'predicate',
  }) async {
    var elapsed = Duration.zero;
    while (elapsed <= timeout) {
      if (predicate()) return;
      await pumpVsyncPaced(tester, readerVsyncStep);
      elapsed += readerVsyncStep;
    }
    fail(
      'Reader correctness waitUntil timeout ($label, $timeout): ${snapshot()}',
    );
  }

  Map<String, Object?> snapshot() {
    final dynamic state = tester.state(find.byType(HybridReaderScreen).last);
    return Map<String, Object?>.from(state.debugSnapshot() as Map);
  }

  List<Map<String, Object?>> frameInvariantViolations() {
    final dynamic state = tester.state(find.byType(HybridReaderScreen).last);
    final records = state.debugFrameInvariantViolations() as List;
    return [
      for (final record in records) Map<String, Object?>.from(record as Map),
    ];
  }

  List<Map<String, Object?>> frameInvariantRecords() {
    final dynamic state = tester.state(find.byType(HybridReaderScreen).last);
    final records = state.debugFrameInvariantRecords() as List;
    return [
      for (final record in records) Map<String, Object?>.from(record as Map),
    ];
  }

  Map<String, Object?>? latestFrameInvariantRecord() {
    final records = frameInvariantRecords();
    return records.isEmpty ? null : records.last;
  }

  Future<void> waitForFrameRecord(
    bool Function(Map<String, Object?> record) predicate, {
    String label = 'frame record',
    Duration timeout = const Duration(seconds: 5),
  }) async {
    await waitUntil(
      () {
        final record = latestFrameInvariantRecord();
        return record != null && predicate(record);
      },
      timeout: timeout,
      label: label,
    );
  }

  void resetFrameInvariantHistory() {
    final dynamic state = tester.state(find.byType(HybridReaderScreen).last);
    state.debugResetFrameInvariantHistory();
  }

  void resetVisualOracle() {
    final dynamic state = tester.state(find.byType(HybridReaderScreen).last);
    state.debugResetVisualOracle();
  }

  void stopVisualMotionForTesting() {
    final dynamic state = tester.state(find.byType(HybridReaderScreen).last);
    state.debugStopVisualMotionForTesting();
  }

  void setVisualInjection(ReaderVisualInjection injection) {
    final dynamic state = tester.state(find.byType(HybridReaderScreen).last);
    state.debugSetVisualInjection(injection);
  }

  Future<List<ReaderV2ChapterLayout>> measureChapterLayouts() async {
    final engine = ReaderV2LayoutEngine();
    final spec = ReaderV2LayoutSpec.fromViewport(
      viewportSize: readerCorrectnessViewportSize,
      style: _layoutStyle,
    );
    final layouts = <ReaderV2ChapterLayout>[];
    for (final chapter in chapters) {
      final content = ReaderV2Content.fromRaw(
        chapterIndex: chapter.index,
        title: chapter.title,
        rawText: chapter.content ?? '',
      );
      layouts.add(await engine.layout(content, spec));
    }
    return layouts;
  }

  Future<ReaderV2ChapterLayout> measureChapterLayout(int chapterIndex) async {
    final engine = ReaderV2LayoutEngine();
    final spec = ReaderV2LayoutSpec.fromViewport(
      viewportSize: readerCorrectnessViewportSize,
      style: _layoutStyle,
    );
    final chapter = chapters[chapterIndex];
    final content = ReaderV2Content.fromRaw(
      chapterIndex: chapter.index,
      title: chapter.title,
      rawText: chapter.content ?? '',
    );
    return engine.layout(content, spec);
  }

  /// Position the real host fixture at an S2 topology anchor.  The chapter
  /// and paragraph coordinates come from C1's measured topology contract; the
  /// paragraph offset is deliberately conservative because the fast lane is
  /// proving operation transitions, not visual typography.
  Future<void> positionAt(ReaderTopologyAnchor anchor) async {
    final location = ReaderCorrectnessFixture.generate().topologyAnchor(anchor);
    final chapter = chapters[location.chapterIndex];
    final contentLength = (chapter.content ?? '').length;
    final content = chapter.content ?? '';
    final paragraphs = content.split('\n\n');
    final paragraphOffset = paragraphs
        .take(location.paragraphIndex.clamp(0, paragraphs.length))
        .fold<int>(0, (total, paragraph) => total + paragraph.length + 2);
    final atBottom =
        anchor == ReaderTopologyAnchor.penultimateChapterTail ||
        anchor == ReaderTopologyAnchor.finalChapterBottom;
    final charOffset = (atBottom ? contentLength : paragraphOffset)
        .clamp(0, contentLength)
        .toInt();
    final jump = runtime.jumpToLocation(
      ReaderV2Location(
        chapterIndex: location.chapterIndex,
        charOffset: charOffset,
      ),
    );
    await jump.timeout(const Duration(seconds: 30));
    await settle(label: 'position-${anchor.name}');
    // Runtime restore can publish `ready` before the post-frame observer has
    // recorded the rebuilt scroll position. Give the rebuilt viewport one
    // shared-vsync observation before the next pointer operation starts.
    await pumpVsyncPaced(tester, readerVsyncStep);
    await settle(label: 'position-${anchor.name} observed');
  }

  /// Release the restore-owned prefetch barrier before probing a fling.
  ///
  /// A programmatic position restore deliberately leaves the ordinary lead
  /// frontier closed.  That is correct for production, but it means a
  /// correctness probe that immediately sends a large fling can legitimately
  /// stop at the bounded restore frontier and never create a ballistic
  /// simulation.  Use a small real user-owned settle as the probe precondition,
  /// then wait for the state-driven lead required by the operation.  The
  /// operation test clears its frame history after this setup, so the setup
  /// gesture cannot masquerade as the operation under test.
  Future<void> primeOrdinaryPrefetchFor(
    ReaderOperationDefinition operation,
  ) async {
    if (operation.direction == ReaderOperationDirection.none) return;
    final sign = operation.direction == ReaderOperationDirection.backward
        ? 1.0
        : -1.0;
    final reader = find.byType(HybridReaderScreen).last;
    final gesture = await tester.startGesture(tester.getCenter(reader));
    await moveVsyncPaced(
      tester,
      gesture,
      Offset(0, sign * 24),
      duration: const Duration(milliseconds: 64),
    );
    await waitUntil(
      () => snapshot()['dragging'] == true,
      label: '${operation.id} preflight entered dragging',
    );
    await gesture.up();
    await settle(label: '${operation.id} preflight settle');

    final leadKey = operation.direction == ReaderOperationDirection.backward
        ? 'backwardLeadPx'
        : 'forwardLeadPx';
    await waitUntil(() {
      final current = snapshot();
      final lead = (current[leadKey] as num?)?.toDouble();
      return current['restorePrefetchBarrierActive'] != true &&
          current['pumpQueueDepth'] == 0 &&
          lead != null &&
          lead > operation.distancePx;
    }, label: '${operation.id} preflight admitted lead');
  }

  @override
  Future<void> applyReaderOperation(ReaderOperationDefinition operation) async {
    final before = latestFrameInvariantRecord();
    switch (operation.id) {
      case 'drag_forward_micro':
      case 'drag_forward_short':
      case 'drag_forward_long':
      case 'drag_backward_micro':
      case 'drag_backward_short':
      case 'drag_backward_long':
      case 'drag_forward_slow':
      case 'drag_backward_slow':
      case 'drag_forward_fast':
      case 'drag_backward_fast':
      case 'drag_release_immediate':
        await _applyDrag(operation);
      case 'drag_reverse_mid':
        await _applyDirectionChangeDrag(operation);
      case 'drag_pause_then_release':
        await _applyPausedDrag();
      case 'fling_forward_low':
      case 'fling_forward_medium':
      case 'fling_forward_high':
      case 'fling_backward_low':
      case 'fling_backward_medium':
      case 'fling_backward_high':
      case 'natural_forward_fling_cross':
      case 'natural_backward_fling_cross':
        await _applyFling(operation);
      case 'ballistic_interrupt_early':
      case 'ballistic_interrupt_middle':
      case 'ballistic_interrupt_tail':
        await _applyBallisticInterrupt(operation);
      case 'natural_forward_slow_cross':
      case 'natural_backward_slow_cross':
        await _applyDrag(operation);
      case 'navigation_next':
      case 'navigation_previous':
      case 'navigation_forward_n':
      case 'navigation_backward_n':
      case 'navigation_jump_first':
      case 'navigation_jump_last':
      case 'navigation_jump_current':
      case 'navigation_jump_loaded_target':
      case 'navigation_jump_unloaded_target':
      case 'navigation_far_location':
        await _applyNavigation(operation);
    }
    await settle(label: operation.id);
    if (latestFrameInvariantRecord() == null) {
      // A no-op navigation can satisfy the semantic settled predicate on the
      // same frame that completed the restore. Advance by one shared vsync
      // step to obtain a C2 observation, then re-check settled state; this is
      // a state-driven sample, not a wall-clock sleep.
      await pumpVsyncPaced(tester, readerVsyncStep);
      await settle(label: '${operation.id} post-record settle');
    }
    final after = latestFrameInvariantRecord();
    operationEvidence.add(<String, Object?>{
      'operation': operation.id,
      'category': operation.category,
      'expectedTransition': operation.transition,
      'before': before,
      'after': after,
      'observedActivity': _observedActivitiesSince(before),
      'observedPhase': _observedPhasesSince(before),
    });
  }

  List<String> _observedActivitiesSince(Map<String, Object?>? before) {
    final records = frameInvariantRecords();
    final beforeTimestamp = before?['timestampMicros'] as num?;
    return <String>{
      for (final record in records)
        if (beforeTimestamp == null ||
            record['timestampMicros'] is! num ||
            (record['timestampMicros'] as num) > beforeTimestamp)
          if (record['scrollActivity'] is String)
            record['scrollActivity'] as String,
    }.toList()..sort();
  }

  List<String> _observedPhasesSince(Map<String, Object?>? before) {
    final records = frameInvariantRecords();
    final beforeTimestamp = before?['timestampMicros'] as num?;
    return <String>{
      for (final record in records)
        if (beforeTimestamp == null ||
            record['timestampMicros'] is! num ||
            (record['timestampMicros'] as num) > beforeTimestamp)
          if (record['phase'] is String) record['phase'] as String,
    }.toList()..sort();
  }

  Future<void> _applyDrag(ReaderOperationDefinition operation) async {
    final sign = operation.direction == ReaderOperationDirection.backward
        ? 1.0
        : -1.0;
    final reader = find.byType(HybridReaderScreen).last;
    final gesture = await tester.startGesture(tester.getCenter(reader));
    await moveVsyncPaced(
      tester,
      gesture,
      Offset(0, sign * operation.distancePx),
      duration: Duration(milliseconds: operation.durationMillis),
    );
    await gesture.up();
  }

  Future<void> _applyDirectionChangeDrag(
    ReaderOperationDefinition operation,
  ) async {
    final reader = find.byType(HybridReaderScreen).last;
    final gesture = await tester.startGesture(tester.getCenter(reader));
    await moveVsyncPaced(
      tester,
      gesture,
      const Offset(0, -110),
      duration: const Duration(milliseconds: 160),
    );
    await waitUntil(
      () => snapshot()['dragging'] == true,
      label: 'drag_reverse_mid entered dragging',
    );
    await moveVsyncPaced(
      tester,
      gesture,
      const Offset(0, 110),
      duration: const Duration(milliseconds: 160),
    );
    await gesture.up();
  }

  Future<void> _applyPausedDrag() async {
    final reader = find.byType(HybridReaderScreen).last;
    final gesture = await tester.startGesture(tester.getCenter(reader));
    await moveVsyncPaced(
      tester,
      gesture,
      const Offset(0, -120),
      duration: const Duration(milliseconds: 180),
    );
    await waitUntil(
      () => snapshot()['dragging'] == true,
      label: 'drag_pause_then_release entered dragging',
    );
    // The pause is state-driven: pump until the active drag has published at
    // least one more C2 record, rather than sleeping for a guessed duration.
    final firstTimestamp =
        latestFrameInvariantRecord()?['timestampMicros'] as num?;
    await waitForFrameRecord(
      (record) =>
          firstTimestamp == null ||
          record['timestampMicros'] is! num ||
          (record['timestampMicros'] as num) > firstTimestamp,
      label: 'drag_pause_then_release published another drag frame',
    );
    await moveVsyncPaced(
      tester,
      gesture,
      const Offset(0, -120),
      duration: const Duration(milliseconds: 180),
    );
    await gesture.up();
  }

  Future<void> _applyFling(ReaderOperationDefinition operation) async {
    final sign = operation.direction == ReaderOperationDirection.backward
        ? 1.0
        : -1.0;
    final reader = find.byType(HybridReaderScreen).last;
    await tester.fling(
      reader,
      Offset(0, sign * operation.distancePx),
      operation.flingSpeed,
      frameInterval: readerVsyncStep,
    );
    await waitForFrameRecord(
      (record) =>
          record['scrollActivity'] == 'ballistic' &&
          record['scrollVelocity'] is num &&
          ((record['scrollVelocity'] as num).abs() > 0),
      label: '${operation.id} entered ballistic',
    );
  }

  Future<void> _applyBallisticInterrupt(
    ReaderOperationDefinition operation,
  ) async {
    await _applyFling(operation);
    final initial = operation.flingSpeed;
    final phase = operation.interruptPhase;
    await waitForFrameRecord(
      (record) {
        final velocity = (record['scrollVelocity'] as num?)?.abs();
        if (velocity == null) return false;
        return switch (phase) {
          'early' => velocity >= initial * 0.66,
          'middle' => velocity >= initial * 0.33 && velocity < initial * 0.66,
          'tail' => velocity > 0 && velocity < initial * 0.33,
          _ => false,
        };
      },
      label: '${operation.id} waitUntil ballistic ${phase ?? 'unknown'}',
      timeout: const Duration(seconds: 10),
    );
    final current = runtime.state.visibleLocation.chapterIndex;
    final target = (current + operation.chapterDelta)
        .clamp(0, chapters.length - 1)
        .toInt();
    final jump = runtime.jumpToChapter(target);
    // Observe the ownership/restore admission frame before awaiting the
    // completion. This is one shared vsync step, not a guessed wall-clock
    // pause, and makes the C2 transition evidence explicit.
    await pumpVsyncPaced(tester, readerVsyncStep);
    await jump.timeout(const Duration(seconds: 30));
  }

  Future<void> _applyNavigation(ReaderOperationDefinition operation) async {
    final current = runtime.state.visibleLocation.chapterIndex;
    final target = switch (operation.id) {
      'navigation_jump_first' => 0,
      'navigation_jump_last' => chapters.length - 1,
      'navigation_jump_current' => current,
      _ =>
        (current + operation.chapterDelta)
            .clamp(0, chapters.length - 1)
            .toInt(),
    };
    final jump = runtime.jumpToChapter(target);
    await pumpVsyncPaced(tester, readerVsyncStep);
    await jump.timeout(const Duration(seconds: 30));
  }

  @override
  Future<void> drag(
    Offset delta, {
    Duration duration = const Duration(milliseconds: 240),
  }) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HybridReaderScreen).last),
    );
    await moveVsyncPaced(tester, gesture, delta, duration: duration);
    await gesture.up();
  }

  @override
  Future<void> fling(
    Offset delta, {
    Duration duration = const Duration(milliseconds: 180),
  }) {
    return drag(delta, duration: duration);
  }

  Future<void> dispose() async {
    if (!_mounted) return;
    _mounted = false;
    runtime.dispose();
    await tester.pump();
  }
}
