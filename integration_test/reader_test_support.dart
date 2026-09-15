import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_bottom_menu.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/hybrid/view/hybrid_scroll_view.dart';
import 'package:night_reader/features/reader_v2/correctness/reader_correctness_visual_oracle.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_chapters_drawer.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page.dart';
import 'package:night_reader/features/welcome/main_page.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_open_target.dart';
import 'package:night_reader/shared/navigation/book_open_route.dart';
import 'package:provider/provider.dart';

import 'package:night_reader/main.dart' as app;

import '../test/reader_correctness/reader_correctness_operations.dart';
import '../test/reader_correctness/reader_correctness_case_generation.dart';

export '../test/reader_correctness/reader_correctness_operations.dart';

const String readerFixturePath = String.fromEnvironment(
  'NIGHT_READER_FIXTURE_PATH',
  defaultValue: '/sdcard/Android/data/com.inkpage.reader.debug/files/NightReader/reader_correctness_book.txt',
);

const String readerFixtureHostPath = String.fromEnvironment(
  'NIGHT_READER_FIXTURE_HOST_PATH',
  defaultValue: 'test/fixtures/reader_correctness_book.txt',
);

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  Duration step = const Duration(milliseconds: 100),
  String? reason,
  String Function()? reasonBuilder,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(step);
  }
  if (!condition()) {
    fail(reasonBuilder?.call() ?? reason ?? '條件在 $timeout 內沒有成立');
  }
}

bool _isReaderSettledSnapshot(Map<String, Object?> snapshot) {
  return snapshot['phase'] == 'ready' &&
      snapshot['initialRestoreCompleted'] == true &&
      snapshot['isScrolling'] == false &&
      snapshot['pumpQueueDepth'] == 0 &&
      snapshot['visibleKeysContiguous'] == true &&
      ((snapshot['missingParagraphKeys'] as List<dynamic>?)?.isEmpty ??
          false) &&
      snapshot['pendingChapterJumpTarget'] == null;
}

/// C6's gesture target is valid only when the real scroll view is mounted at
/// the same observation as the runtime's ready state.  Keep this policy in a
/// small test-only seam so the target-count negative case cannot be weakened
/// accidentally while changing the polling loop.
bool c6HybridScrollViewReadinessSatisfied({
  required int targetCount,
  required Map<String, Object?>? snapshot,
}) {
  return targetCount == 1 &&
      snapshot?['phase'] == 'ready' &&
      snapshot?['initialRestoreCompleted'] == true &&
      snapshot?['pendingChapterJumpTarget'] == null;
}

/// Tracks the bounded consecutive-frame requirement for the C6 gesture target.
/// A transient unmounted/not-ready frame always resets the streak.
final class C6HybridScrollViewReadinessTracker {
  int _readyFrameStreak = 0;

  bool observe({
    required int targetCount,
    required Map<String, Object?>? snapshot,
  }) {
    if (c6HybridScrollViewReadinessSatisfied(
      targetCount: targetCount,
      snapshot: snapshot,
    )) {
      _readyFrameStreak += 1;
    } else {
      _readyFrameStreak = 0;
    }
    return _readyFrameStreak >= 2;
  }
}

/// The C6 watchdog observes independent progress dimensions rather than using
/// a single action marker.  It is intentionally a test-harness class: no
/// production render/runtime path depends on wall-clock test policy.
final class ReaderSixDimensionWatchdogAbort extends StateError {
  ReaderSixDimensionWatchdogAbort(this.evidence)
    : super('C6 six-dimension watchdog aborted: ${evidence['reason']}');

  final Map<String, Object?> evidence;
}

final class ReaderSixDimensionWatchdog {
  ReaderSixDimensionWatchdog({
    this.limit = const Duration(seconds: 15),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration limit;
  final DateTime Function() _clock;
  DateTime? _lastProgressAt;
  Map<String, Object?>? _lastSignature;

  /// Observe one bounded sample.  [operationActive] marks a real operation or
  /// settle wait.  [waitingForLoad] is an explicit legal exception for a
  /// known asynchronous chapter load; it prevents an expected quiet window
  /// from being reported as a deadlock while the caller still has its own
  /// bounded future/timeout.
  bool observe({
    required Map<String, Object?> snapshot,
    required bool operationActive,
    required String operationState,
    double? visualDy,
    int invariantEvaluationCount = 0,
    bool waitingForLoad = false,
    DateTime? now,
  }) {
    final currentTime = now ?? _clock();
    final phase = snapshot['phase']?.toString() ?? 'unknown';
    final queue = (snapshot['pumpQueueDepth'] as num?)?.toInt() ?? 0;
    final scrolling = snapshot['isScrolling'] == true;
    final restoring =
        snapshot['restoreLocked'] == true ||
        snapshot['pendingChapterJumpTarget'] != null ||
        snapshot['initialRestoreCompleted'] != true;
    final active =
        operationActive ||
        phase != 'ready' ||
        scrolling ||
        restoring ||
        queue > 0;

    // A settled idle frame and an explicitly bounded load wait are legal
    // quiet states. Reset the episode so a later operation starts fresh.
    if (!active || waitingForLoad) {
      reset();
      return false;
    }

    final location = snapshot['capturedLocation'];
    final runtime = <String, Object?>{
      'phase': phase,
      'operationTokenId': snapshot['operationTokenId'],
      'runtimeLocationRevision': snapshot['runtimeLocationRevision'],
      'layoutGeneration': snapshot['layoutGeneration'],
      'epoch': snapshot['epoch'],
      'invariantEvaluationCount': invariantEvaluationCount,
    };
    final viewport = <String, Object?>{
      'scrollPixels': snapshot['scrollPixels'] ?? snapshot['scrollOffset'],
      'scrollOffset': snapshot['scrollOffset'],
    };
    final rendered = <String, Object?>{'visualDy': visualDy};
    final state = <String, Object?>{'operationState': operationState};
    final queueProgression = <String, Object?>{
      'pumpQueueDepth': queue,
      'enqueuedCount': snapshot['enqueuedCount'],
    };
    final chapter = <String, Object?>{
      'dominantVisibleChapter': snapshot['dominantVisibleChapter'],
      'displayedProgressChapter': snapshot['displayedProgressChapter'],
      'capturedChapter': location is Map ? location['chapterIndex'] : null,
    };
    final signature = <String, Object?>{
      'runtimeProgress': runtime,
      'viewportMovement': viewport,
      'renderedMovement': rendered,
      'operationState': state,
      'queueProgression': queueProgression,
      'chapterProgression': chapter,
    };
    if (_lastSignature == null || !_mapsEqual(_lastSignature!, signature)) {
      _lastSignature = signature;
      _lastProgressAt = currentTime;
      return true;
    }
    final started = _lastProgressAt ?? currentTime;
    final stagnantFor = currentTime.difference(started);
    if (stagnantFor < limit) return false;
    final evidence = <String, Object?>{
      'reason': 'all six progress dimensions unchanged',
      'limitMillis': limit.inMilliseconds,
      'stagnantMillis': stagnantFor.inMilliseconds,
      'operationState': operationState,
      'snapshot': Map<String, Object?>.from(snapshot),
      'dimensions': signature,
    };
    throw ReaderSixDimensionWatchdogAbort(evidence);
  }

  void reset() {
    _lastProgressAt = null;
    _lastSignature = null;
  }

  static bool _mapsEqual(
    Map<String, Object?> left,
    Map<String, Object?> right,
  ) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      final other = right[entry.key];
      if (entry.value is Map && other is Map) {
        if (!_mapsEqual(
          Map<String, Object?>.from(entry.value as Map),
          Map<String, Object?>.from(other),
        )) {
          return false;
        }
      } else if (entry.value is List && other is List) {
        if (entry.value.toString() != other.toString()) return false;
      } else if (entry.value != other) {
        return false;
      }
    }
    return true;
  }
}

class ReaderTestHarness implements ReaderCorrectnessOperationHarness {
  ReaderTestHarness(this.tester);

  final WidgetTester tester;

  late Book book;
  late List<BookChapter> chapters;

  /// Read the runtime through the test-only seam on ReaderV2Page. Keeping the
  /// lookup here lets the continuous workload exercise the same runtime jump
  /// path as the chapter drawer without making the old Drawer harness its
  /// dependency.
  ReaderV2Runtime get runtimeForTesting {
    final dynamic pageState = tester.state(find.byType(ReaderV2Page).last);
    final runtime = pageState.debugRuntime as ReaderV2Runtime?;
    if (runtime == null) fail('Reader runtime 尚未建立');
    return runtime;
  }

  /// Read the semantic Reader snapshot exposed by HybridReaderScreen for the
  /// continuous layout/scroll race workload.
  Map<String, Object?> debugSnapshot() {
    final dynamic screenState = tester.state(
      find.byType(HybridReaderScreen).last,
    );
    final snapshot = screenState.debugSnapshot();
    return Map<String, Object?>.from(snapshot as Map);
  }

  Map<String, Object?> debugPerformanceSummary() {
    final dynamic screenState = tester.state(
      find.byType(HybridReaderScreen).last,
    );
    final summary = screenState.debugPerformanceSummary();
    return Map<String, Object?>.from(summary as Map);
  }

  List<Map<String, Object?>> debugFrameInvariantViolations({
    bool clear = false,
  }) {
    final dynamic screenState = tester.state(
      find.byType(HybridReaderScreen).last,
    );
    final violations = screenState.debugFrameInvariantViolations(clear: clear);
    return [
      for (final violation in (violations as List))
        Map<String, Object?>.from(violation as Map),
    ];
  }

  List<Map<String, Object?>> debugFrameInvariantRecords() {
    final dynamic screenState = tester.state(
      find.byType(HybridReaderScreen).last,
    );
    return [
      for (final record in (screenState.debugFrameInvariantRecords() as List))
        Map<String, Object?>.from(record as Map),
    ];
  }

  void resetFrameInvariantHistory() {
    final dynamic screenState = tester.state(
      find.byType(HybridReaderScreen).last,
    );
    screenState.debugResetFrameInvariantHistory();
  }

  Map<String, Object?> debugVisualOracleSummary() {
    final dynamic screenState = tester.state(
      find.byType(HybridReaderScreen).last,
    );
    return Map<String, Object?>.from(
      screenState.debugVisualOracleSummary() as Map,
    );
  }

  List<Map<String, Object?>> debugVisualOracleFrames() {
    final dynamic screenState = tester.state(
      find.byType(HybridReaderScreen).last,
    );
    return [
      for (final frame in (screenState.debugVisualOracleFrames() as List))
        Map<String, Object?>.from(frame as Map),
    ];
  }

  List<ReaderVisualRawFrame> debugVisualOracleRetainedRawFrames() {
    final dynamic screenState = tester.state(
      find.byType(HybridReaderScreen).last,
    );
    return [
      for (final frame
          in (screenState.debugVisualOracleRetainedRawFrames() as List))
        frame as ReaderVisualRawFrame,
    ];
  }

  List<Map<String, Object?>> debugVisualOracleViolations() {
    final dynamic screenState = tester.state(
      find.byType(HybridReaderScreen).last,
    );
    return [
      for (final violation
          in (screenState.debugVisualOracleViolations() as List))
        Map<String, Object?>.from(violation as Map),
    ];
  }

  void resetVisualOracle() {
    final dynamic screenState = tester.state(
      find.byType(HybridReaderScreen).last,
    );
    screenState.debugResetVisualOracle();
  }

  void setVisualInjection(ReaderVisualInjection injection) {
    final dynamic screenState = tester.state(
      find.byType(HybridReaderScreen).last,
    );
    screenState.debugSetVisualInjection(injection);
  }

  void stopVisualMotionForTesting() {
    final dynamic screenState = tester.state(
      find.byType(HybridReaderScreen).last,
    );
    screenState.debugStopVisualMotionForTesting();
  }

  void resetPerformanceWindow() {
    final dynamic screenState = tester.state(
      find.byType(HybridReaderScreen).last,
    );
    screenState.debugResetPerformanceWindow();
  }

  @override
  Future<void> drag(Offset delta, {Duration duration = readerVsyncStep}) async {
    await dismissControls();
    final reader = find.byType(HybridReaderScreen).last;
    await runVsyncScrollForTesting(delta, duration: duration);
    expect(reader, findsOneWidget);
  }

  @override
  Future<void> fling(
    Offset delta, {
    Duration duration = readerVsyncStep,
  }) async {
    await dismissControls();
    final reader = find.byType(HybridReaderScreen).last;
    final velocity = delta.distance / (duration.inMilliseconds / 1000.0);
    await tester.fling(reader, delta, velocity);
    await pumpVsyncPaced(tester, const Duration(milliseconds: 80));
  }

  Future<void> startAndProvision() async {
    app.main();
    // IntegrationTestWidgetsFlutterBinding owns first-frame scheduling.  The
    // production splash is released explicitly so the test can observe the
    // real widget tree while startup providers settle.
    FlutterNativeSplash.remove();

    await pumpUntil(
      tester,
      () => find.byType(MainPage).evaluate().isNotEmpty,
      reason: 'MainPage 未在預期時間內出現',
    );

    final shelf = Provider.of<BookshelfProvider>(
      tester.element(find.byType(MainPage)),
      listen: false,
    );
    // Ask Android for the app-owned external root before accessing the pushed
    // file. On API 37, an adb-created Android/data child can be visible to
    // shell but still fail dart:io File.exists until path_provider initializes
    // the owning app's external-files subtree.
    final externalRoot = await getExternalStorageDirectory();
    debugPrint('READER_E2E_EXTERNAL_ROOT path=${externalRoot?.path}');
    if (externalRoot != null) {
      await Directory('${externalRoot.path}/NightReader')
          .create(recursive: true);
    }
    expect(
      await File(readerFixturePath).exists(),
      isTrue,
      reason: 'emulator fixture 不存在：$readerFixturePath',
    );
    final imported = await shelf.importLocalBookPath(readerFixturePath);
    expect(imported, isTrue, reason: '正式 local-book import 回傳失敗');
    await shelf.loadBooks();
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    final bookUrl = 'local://$readerFixturePath';
    final importedBook = await getIt<BookDao>().getByUrl(bookUrl);
    expect(importedBook, isNotNull, reason: '正式 local-book import 沒有寫入書架');
    final storedBook = await getIt<BookDao>().getByUrl(bookUrl);
    expect(storedBook, isNotNull, reason: '正式 local-book import 沒有寫入書架');
    book = storedBook!;
    chapters = await getIt<ChapterDao>().getByBook(bookUrl);
    expect(
      chapters,
      hasLength(readerCorrectnessChapterCount),
      reason: 'Reader correctness fixture 的章節索引數量不正確',
    );
    expect(chapters.first.title, '前言');
    expect(chapters[1].title, startsWith('第一章'));
    expect(chapters[120].index, 120);
    expect(chapters.last.index, chapters.length - 1);

    // The runner clears app data, but keep the fixture setup deterministic even
    // when a device/package manager leaves a previous local-book row behind.
    // The journey intentionally starts at the preface before exercising next
    // chapter and random jumps.
    await getIt<BookDao>().updateProgress(
      bookUrl,
      0,
      chapters.first.title,
      0,
      visualOffsetPx: 0,
      readerAnchorJson: null,
    );
    book = (await getIt<BookDao>().getByUrl(bookUrl))!;

    debugPrint(
      'READER_E2E_PROVISION '
      'fixtureHost=$readerFixtureHostPath '
      'fixtureDevice=$readerFixturePath '
      'method=adb_push_plus_BookshelfProvider.importLocalBookPath+resetProgress '
      'import=success chapters=${chapters.length}',
    );
  }

  Future<void> openBook() async {
    await pumpUntil(
      tester,
      () => find.byType(BookshelfPage).evaluate().isNotEmpty,
      reason: 'BookshelfPage 未出現',
    );
    final bookTile = find.text(book.name).first;
    await tester.tap(bookTile);
    await tester.pump();
    await pumpUntil(
      tester,
      () => find.byType(ReaderV2Page).evaluate().isNotEmpty,
      reason: 'ReaderV2Page 未出現',
    );
    await pumpUntil(
      tester,
      () => find.byType(HybridReaderScreen).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 60),
      reason: 'HybridReaderScreen 未出現',
    );
    await tester.pump(const Duration(seconds: 1));
    expectNoFlutterException();
  }

  /// Leave the Reader through its real back control. This is the entry
  /// measurement precondition: the app process remains alive, but the Reader
  /// route is absent and the book is opened again from the bookshelf.
  Future<void> closeReaderToBookshelf() async {
    await closeChapterDrawerIfOpen();
    await showControls();
    final backButton = find.byIcon(Icons.arrow_back).hitTestable();
    expect(backButton, findsOneWidget, reason: 'Reader 返回按鈕未顯示');
    await tester.tap(backButton);
    await tester.pump(const Duration(milliseconds: 500));
    await pumpUntil(
      tester,
      () => find.byType(BookshelfPage).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 60),
      reason: 'Reader 返回後沒有回到書架',
    );
  }

  /// Reopen the same book while the app is already inside a Reader route.
  /// This is the available hot-entry proxy for the one-book fixture; it is
  /// deliberately reported as same-book hot re-entry, not as a true
  /// cross-book switch.
  Future<void> hotReopenCurrentBook() async {
    final context = tester.element(find.byType(ReaderV2Page).last);
    Navigator.of(context).push(
      BookOpenRoute(book: book, openTarget: ReaderV2OpenTarget.resume(book)),
    );
    await pumpUntil(
      tester,
      () => find.byType(ReaderV2Page).evaluate().length >= 2,
      timeout: const Duration(seconds: 60),
      reason: 'hot re-entry 沒有建立第二個 Reader route',
    );
    await pumpUntil(
      tester,
      () => find.byType(HybridReaderScreen).evaluate().length >= 2,
      timeout: const Duration(seconds: 60),
      reason: 'hot re-entry 沒有建立第二個 HybridReaderScreen',
    );
    await tester.pump(const Duration(seconds: 1));
    expectNoFlutterException();
  }

  Future<void> closeHotReentry() async {
    if (find.byType(ReaderV2Page).evaluate().length < 2) return;
    Navigator.of(tester.element(find.byType(ReaderV2Page).last)).pop();
    await pumpUntil(
      tester,
      () => find.byType(ReaderV2Page).evaluate().length == 1,
      timeout: const Duration(seconds: 30),
      reason: 'hot re-entry route 沒有關閉',
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  void setTapAction(int gridIndex, int actionCode) {
    final dynamic pageState = tester.state(find.byType(ReaderV2Page).last);
    pageState.debugSettings.setClickAction(gridIndex, actionCode);
  }

  /// Test-only settings seam for settled Android screenshot checkpoints. The
  /// workload deliberately calls the existing settings controller rather than
  /// adding a production runtime switch or a fake presentation path.
  void setTypographyForTesting() {
    final dynamic pageState = tester.state(find.byType(ReaderV2Page).last);
    pageState.debugSettings.setTypography(
      fontSize: 21.0,
      lineHeight: 1.75,
      letterSpacing: 0.35,
    );
    // textIndent is an existing settings seam and participates in the same
    // presentation/layout invalidation path. There is no font-family seam in
    // the current product, so the monkey reports that route as skipped.
    pageState.debugSettings.setTextIndent(2);
  }

  void setThemeForTesting() {
    final dynamic pageState = tester.state(find.byType(ReaderV2Page).last);
    pageState.debugSettings.setTheme(1);
  }

  void setChineseConversionForTesting() {
    final dynamic pageState = tester.state(find.byType(ReaderV2Page).last);
    pageState.debugSettings.setChineseConvert(1);
  }

  void setPaddingForTesting() {
    final dynamic pageState = tester.state(find.byType(ReaderV2Page).last);
    pageState.debugSettings.textPadding = 28.0;
    pageState.debugSettings.notifyListeners();
  }

  Future<void> reloadContentForTesting() async {
    await runtimeForTesting.reloadContentPreservingLocation();
  }

  /// Wait for the same semantic settled boundary used by the continuous
  /// workload. This is intentionally a test-only helper; it does not add a
  /// production settling state or alter the Reader UI.
  Future<Map<String, Object?>> settleReaderForTesting(
    String label, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    Map<String, Object?>? latest;
    Map<String, Object?>? settled;
    var settledFrameStreak = 0;
    final deadline = DateTime.now().add(timeout);
    while (settled == null && DateTime.now().isBefore(deadline)) {
      final snapshot = debugSnapshot();
      latest = snapshot;
      if (_isReaderSettledSnapshot(snapshot)) {
        settledFrameStreak += 1;
        if (settledFrameStreak >= 4) {
          // A chapter jump can enqueue cache work one or two real vsyncs
          // after its first apparently settled snapshot.  Keep the existing
          // _settle assertions, but require a short stable window before
          // returning so that this scheduling race is not reported as a
          // spurious C6 setup failure.
          await pumpVsyncPaced(tester, readerVsyncStep * 2);
          final finalSnapshot = debugSnapshot();
          if (_isReaderSettledSnapshot(finalSnapshot)) {
            settled = finalSnapshot;
            break;
          }
          settledFrameStreak = 0;
        }
      } else {
        settledFrameStreak = 0;
      }
      await tester.pump(readerVsyncStep);
    }
    if (settled == null) {
      fail('Reader 在 $label 後沒有 settled：$latest');
    }
    final stableSettled = settled;
    expect(stableSettled['phase'], 'ready');
    expect(stableSettled['initialRestoreCompleted'], isTrue);
    expect(stableSettled['pumpQueueDepth'], 0);
    expect(stableSettled['visibleKeysContiguous'], isTrue);
    expect((stableSettled['visibleKeys'] as List<dynamic>), isNotEmpty);
    expect((stableSettled['missingParagraphKeys'] as List<dynamic>), isEmpty);
    expect(stableSettled['pendingChapterJumpTarget'], isNull);
    return stableSettled;
  }

  Future<void> runVsyncScrollForTesting(
    Offset delta, {
    Duration duration = const Duration(milliseconds: 240),
    bool requireUserDrag = false,
  }) async {
    await dismissControls();
    // Gesture the actual scrollable.  The outer HybridReaderScreen can be
    // hit-testable while a child overlay/tap layer owns the center point;
    // that would let a C6 operation become a no-op and then pass the settled
    // predicate without ever observing user scroll ownership.
    final reader = await _waitForMountedHybridScrollView();
    final gesture = await tester.startGesture(tester.getCenter(reader));
    var observedUserDrag = false;
    void observeUserDrag() {
      final snapshot = debugSnapshot();
      observedUserDrag =
          observedUserDrag ||
          snapshot['dragging'] == true ||
          snapshot['restoreUserScrollObserved'] == true;
    }

    await moveVsyncPaced(tester, gesture, delta, duration: duration);
    if (requireUserDrag) observeUserDrag();
    await gesture.up();
    await pumpVsyncPaced(tester, const Duration(milliseconds: 80));
    if (requireUserDrag && !observedUserDrag) {
      throw StateError(
        'C6_HARNESS_NO_USER_DRAG: paced operation produced no observed '
        'dragging/user-scroll ownership; refusing a no-op settle pass',
      );
    }
  }

  /// A runtime restore publishes its semantic ready snapshot before the
  /// post-frame rebuild that swaps the loading surface for [HybridScrollView]
  /// is committed.  C6 must wait for the actual gesture target, not infer it
  /// from the snapshot alone.  Keep this wait bounded and require two
  /// consecutive ready frames so a single transient mount cannot race the
  /// subsequent getCenter call.
  Future<Finder> _waitForMountedHybridScrollView() async {
    final readiness = C6HybridScrollViewReadinessTracker();
    final observations = <String>[];
    String? previousObservation;
    // The original 2-second bound was shorter than the observed Android
    // frame/tree hand-off: runtime was already ready, but the mounted target
    // appeared only at the end of that window. Keep the retry finite and
    // separate from the 20-second semantic settle watchdog.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final targets = find.byType(HybridScrollView);
      final targetMounted = targets.evaluate().length == 1;
      final snapshot = targetMounted ? debugSnapshot() : null;
      final observation = [
        'targetCount=${targets.evaluate().length}',
        'phase=${snapshot?['phase']}',
        'initialRestoreCompleted=${snapshot?['initialRestoreCompleted']}',
        'pendingChapterJumpTarget=${snapshot?['pendingChapterJumpTarget']}',
      ].join(',');
      if (observation != previousObservation) {
        observations.add(observation);
        if (observations.length > 12) observations.removeAt(0);
        previousObservation = observation;
      }
      if (readiness.observe(
        targetCount: targets.evaluate().length,
        snapshot: snapshot,
      )) {
        // Re-read after the second frame and return this checked finder
        // directly. There is no .last/.first lookup before getCenter.
        final confirmed = find.byType(HybridScrollView);
        if (confirmed.evaluate().length == 1) return confirmed;
      }
      await tester.pump(readerVsyncStep);
    }

    final targets = find.byType(HybridScrollView);
    final snapshot = debugSnapshot();
    throw StateError(
      'C6_HARNESS_SCROLLABLE_NOT_READY: expected one mounted '
      'HybridScrollView for a ready case; '
      'targetCount=${targets.evaluate().length} snapshot=$snapshot '
      'observations=${observations.join(' | ')}',
    );
  }

  /// Apply one C5 catalog definition on the real mounted Reader.  The case
  /// generator remains data-only; this is the single Android gesture bridge
  /// used by C6 and deliberately does not copy case-selection semantics.
  @override
  Future<void> applyReaderOperation(ReaderOperationDefinition operation) async {
    final sign = operation.direction == ReaderOperationDirection.backward
        ? 1.0
        : -1.0;
    final reader = find.byType(HybridReaderScreen).last;
    switch (operation.id) {
      case 'drag_reverse_mid':
        await dismissControls();
        final gesture = await tester.startGesture(tester.getCenter(reader));
        await moveVsyncPaced(
          tester,
          gesture,
          const Offset(0, -110),
          duration: const Duration(milliseconds: 140),
        );
        await moveVsyncPaced(
          tester,
          gesture,
          const Offset(0, 70),
          duration: const Duration(milliseconds: 120),
        );
        await gesture.up();
      case 'drag_pause_then_release':
        await dismissControls();
        final gesture = await tester.startGesture(tester.getCenter(reader));
        await gesture.moveBy(Offset(0, sign * 120));
        await pumpVsyncPaced(tester, const Duration(milliseconds: 160));
        await pumpVsyncPaced(tester, const Duration(milliseconds: 140));
        await gesture.up();
      case 'ballistic_interrupt_early' ||
          'ballistic_interrupt_middle' ||
          'ballistic_interrupt_tail':
        await dismissControls();
        await tester.fling(
          reader,
          Offset(0, sign * operation.distancePx),
          operation.flingSpeed,
        );
        final wait = switch (operation.interruptPhase) {
          'early' => const Duration(milliseconds: 55),
          'middle' => const Duration(milliseconds: 120),
          'tail' => const Duration(milliseconds: 260),
          _ => const Duration(milliseconds: 120),
        };
        await pumpVsyncPaced(tester, wait);
        final current = runtimeForTesting.state.visibleLocation.chapterIndex;
        final target = (current + operation.chapterDelta)
            .clamp(0, chapters.length - 1)
            .toInt();
        await runtimeForTesting.jumpToChapter(target);
      case 'navigation_jump_first':
        await runtimeForTesting.jumpToChapter(0);
      case 'navigation_jump_last':
        await runtimeForTesting.jumpToChapter(chapters.length - 1);
      case 'navigation_jump_current':
        await runtimeForTesting.jumpToChapter(
          runtimeForTesting.state.visibleLocation.chapterIndex,
        );
      case 'navigation_next' ||
          'navigation_previous' ||
          'navigation_forward_n' ||
          'navigation_backward_n' ||
          'navigation_jump_loaded_target' ||
          'navigation_jump_unloaded_target' ||
          'navigation_far_location':
        final current = runtimeForTesting.state.visibleLocation.chapterIndex;
        final target = (current + operation.chapterDelta)
            .clamp(0, chapters.length - 1)
            .toInt();
        await runtimeForTesting.jumpToChapter(target);
      default:
        if (operation.category == 'fling') {
          await dismissControls();
          await tester.fling(
            reader,
            Offset(0, sign * operation.distancePx),
            operation.flingSpeed,
          );
        } else if (operation.category == 'natural_cross_chapter' &&
            operation.flingSpeed > 0) {
          await dismissControls();
          await tester.fling(
            reader,
            Offset(0, sign * operation.distancePx),
            operation.flingSpeed,
          );
        } else {
          await runVsyncScrollForTesting(
            Offset(0, sign * operation.distancePx),
            duration: Duration(
              milliseconds: operation.durationMillis.clamp(80, 900).toInt(),
            ),
            requireUserDrag: true,
          );
        }
    }
    expectNoFlutterException();
  }

  /// Move the real Reader to the chapter represented by a C5 topology anchor.
  /// C5's paragraph coordinate remains in the case id/metadata; the current
  /// production runtime exposes chapter jumps, so this method records the
  /// strongest real precondition available without adding a product API.
  Future<Map<String, Object?>> positionAtTopologyAnchor(
    ReaderTopologyAnchor anchor, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final location = ReaderCorrectnessFixture.generate().topologyAnchor(anchor);
    await runtimeForTesting.jumpToChapter(location.chapterIndex);
    return settleReaderForTesting('C6 anchor ${anchor.name}', timeout: timeout);
  }

  /// Exercise many distant chapters with finite, vsync-paced reading input.
  /// The fixture has 121 chapters, so this is the available route for
  /// putting pressure on the existing ParagraphCache(512) without inventing
  /// a cache-control product feature.
  Future<void> exerciseLongChapterCachePressureForTesting() async {
    final targets = <int>[5, 15, 25, 35, 45, 55, 65, 75, 85, 95];
    for (final target in targets) {
      await runtimeForTesting.jumpToChapter(target);
    }
    // Keep the pressure action as one operation boundary. Settling every
    // internal jump would make the invariant hook compare an old idle frame
    // with the next deliberately started jump. The outer monkey action then
    // performs the single settled checkpoint for this bounded sequence.
    await runVsyncScrollForTesting(
      const Offset(0, -720),
      duration: const Duration(milliseconds: 280),
    );
  }

  Future<void> exerciseShortChapterChainForTesting() async {
    // The fixture's preface and first chapters are the shortest stable
    // boundary route available to this one-book workload.
    for (final target in <int>[0, 1, 0, 2, 1, 0]) {
      await runtimeForTesting.jumpToChapter(target);
    }
  }

  Future<void> exerciseBookBoundariesForTesting() async {
    await runtimeForTesting.jumpToChapter(0);
    await runVsyncScrollForTesting(
      const Offset(0, 800),
      duration: const Duration(milliseconds: 260),
    );
    await runtimeForTesting.jumpToChapter(chapters.length - 1);
    await runVsyncScrollForTesting(
      const Offset(0, -800),
      duration: const Duration(milliseconds: 260),
    );
  }

  Future<void> exerciseScrollDuringPresentationForTesting() async {
    await dismissControls();
    final reader = find.byType(HybridReaderScreen).last;
    // A real settings control cannot be tapped while the same pointer is
    // dragging the content. Use the existing fling route instead: it keeps
    // the viewport in ballistic motion while the presentation invalidation
    // is applied, which is the reachable scroll-not-settled race.
    await tester.fling(reader, const Offset(0, -1650), 3800);
    await pumpVsyncPaced(tester, const Duration(milliseconds: 90));
    final dynamic pageState = tester.state(find.byType(ReaderV2Page).last);
    pageState.debugSettings.setTypography(fontSize: 20.0, lineHeight: 1.65);
    await pumpVsyncPaced(tester, const Duration(milliseconds: 120));
  }

  Future<void> exerciseRapidDrawerJumpCompetitionForTesting() async {
    // First take the real Drawer -> runtime path, then immediately issue
    // multiple runtime jumps. The latter is the deterministic way to create
    // the existing operation-token race without tapping a disappearing tile.
    final middle = chapters.length ~/ 2;
    await jumpToChapterFromDirectory(middle);
    final runtime = runtimeForTesting;
    final targets = <int>[middle + 7, middle - 9, middle + 13]
        .map((value) => value.clamp(0, chapters.length - 1).toInt())
        .toList(growable: false);
    await Future.wait(<Future<void>>[
      for (final target in targets) runtime.jumpToChapter(target),
    ]);
  }

  Future<void> exerciseBallisticChapterSwitchForTesting() async {
    await dismissControls();
    final reader = find.byType(HybridReaderScreen).last;
    await tester.fling(reader, const Offset(0, -1650), 3800);
    await pumpVsyncPaced(tester, const Duration(milliseconds: 90));
    final current = runtimeForTesting.state.visibleLocation.chapterIndex;
    final target = (current + 7).clamp(0, chapters.length - 1).toInt();
    await runtimeForTesting.jumpToChapter(target);
  }

  /// Close any modal sheet left by a platform-limited integration route before
  /// an Android pixel checkpoint. This only cleans the test surface; it does
  /// not add a production route or change the TTS implementation.
  Future<void> dismissTransientSheetsForTesting() async {
    for (var attempt = 0; attempt < 3; attempt += 1) {
      final sheets = find.byType(BottomSheet);
      if (sheets.evaluate().isEmpty) break;
      Navigator.of(tester.element(sheets.last)).pop();
      await tester.pump(const Duration(milliseconds: 120));
    }
    await dismissControls();
  }

  Future<void> showControls() async {
    final scaffoldState = _readerScaffoldState();
    if (scaffoldState.isDrawerOpen) {
      scaffoldState.closeDrawer();
      await pumpUntil(
        tester,
        () => !scaffoldState.isDrawerOpen,
        reason: 'Reader 章節 Drawer 沒有關閉',
      );
    }
    if (_readerControlsVisible()) {
      return;
    }
    // The top safe-area info bar calls onShowControls directly.  It is a more
    // deterministic control entry point than a content-zone tap because the
    // Reader's persisted 3x3 tap grid is user configurable.
    final viewport = tester.binding.renderViews.single.size;
    await tester.tapAt(Offset(viewport.width / 2, 5));
    await tester.pump(const Duration(milliseconds: 250));
    await pumpUntil(
      tester,
      _readerControlsVisible,
      reason: 'Reader controls 未顯示',
    );
  }

  /// The chapter drawer has its own hit-testable `目錄` title. Limit the
  /// selector to the actual bottom menu so a still-open drawer cannot be
  /// mistaken for the Reader controls during a repeated reopen action.
  bool _readerControlsVisible() {
    final menus = find.byType(ReaderV2BottomMenu);
    if (menus.evaluate().isEmpty) return false;
    final menu = tester.widget<ReaderV2BottomMenu>(menus.last);
    if (!menu.controlsVisible) return false;
    return find
        .descendant(of: menus.last, matching: find.text('目錄'))
        .hitTestable()
        .evaluate()
        .isNotEmpty;
  }

  Future<void> closeChapterDrawerIfOpen() async {
    final scaffoldState = _readerScaffoldState();
    if (!scaffoldState.isDrawerOpen) return;
    scaffoldState.closeDrawer();
    await _waitForChapterDrawerToClose(scaffoldState);
  }

  bool _chapterDrawerIsHitTestable() {
    return find
        .byType(ReaderV2ChaptersDrawer)
        .hitTestable()
        .evaluate()
        .isNotEmpty;
  }

  Future<void> _waitForChapterDrawerToClose(ScaffoldState scaffoldState) async {
    // ScaffoldState.isDrawerOpen flips as soon as the route starts popping;
    // under the 120Hz integration renderer the visual drawer/route barrier
    // can remain hit-testable for a few frames. Do not send the next Reader
    // gesture until both the logical and visual close conditions are true.
    await pumpUntil(
      tester,
      () => !scaffoldState.isDrawerOpen,
      reason: 'Reader 章節 Drawer 沒有關閉',
    );
    await pumpUntil(
      tester,
      () => !_chapterDrawerIsHitTestable(),
      timeout: const Duration(seconds: 2),
      step: readerVsyncStep,
      reason: 'Reader 章節 Drawer 關閉 transition 沒有完成',
    );
  }

  /// Exercise a real directory selection without depending on the controls
  /// overlay. This keeps the continuous workload focused on Reader content
  /// races while still covering the production Drawer -> runtime jump path.
  Future<void> jumpToChapterFromDirectory(int index) async {
    if (index < 0 || index >= chapters.length) {
      throw ArgumentError.value(index, 'index');
    }
    await dismissControls();
    final scaffoldState = _readerScaffoldState();
    scaffoldState.openDrawer();
    await pumpUntil(
      tester,
      () => scaffoldState.isDrawerOpen,
      reason: '章節 Drawer 未開啟',
    );
    await tester.pump(const Duration(milliseconds: 250));

    final drawer = find.byType(ReaderV2ChaptersDrawer);
    final drawerScrollables = find.descendant(
      of: drawer,
      matching: find.byType(Scrollable),
    );
    expect(drawerScrollables, findsOneWidget);
    final scrollableState = tester.state<ScrollableState>(
      drawerScrollables.last,
    );
    final targetOffset = (index * 56.0)
        .clamp(
          scrollableState.position.minScrollExtent,
          scrollableState.position.maxScrollExtent,
        )
        .toDouble();
    final title = chapters[index].title;
    final tile = find.descendant(of: drawer, matching: find.text(title));
    for (var attempt = 0; attempt < 4; attempt += 1) {
      scrollableState.position.jumpTo(targetOffset);
      await pumpVsyncPaced(tester, const Duration(milliseconds: 100));
      if (tile.evaluate().isNotEmpty) break;
    }
    expect(tile, findsOneWidget, reason: 'Drawer 找不到章節 $index：$title');
    await tester.ensureVisible(tile);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 120));
    await _waitForChapterDrawerToClose(scaffoldState);
    expectNoFlutterException();
  }

  Future<void> tapNextChapter() async {
    await showControls();
    final button = find.text('下一章').hitTestable().last;
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 250));
    await pumpUntil(
      tester,
      () => find.text(chapters[1].title).hitTestable().evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
      reason: '下一章沒有抵達 ${chapters[1].title}',
    );
    expectNoFlutterException();
  }

  Future<void> moveRelativeChapter({required bool forward}) async {
    await showControls();
    final label = forward ? '下一章' : '上一章';
    final buttons = find.text(label).hitTestable();
    if (buttons.evaluate().isNotEmpty) {
      await tester.tap(buttons.last);
      await tester.pump(const Duration(milliseconds: 350));
    }
    expectNoFlutterException();
  }

  Future<void> jumpToChapter(int index) async {
    if (index < 0 || index >= chapters.length) {
      throw ArgumentError.value(index, 'index');
    }
    await showControls();
    final scaffoldState = _readerScaffoldState();
    await tester.tap(find.text('目錄').hitTestable().last);
    await tester.pump(const Duration(milliseconds: 250));
    final drawer = find.byType(ReaderV2ChaptersDrawer);
    await pumpUntil(
      tester,
      () => scaffoldState.isDrawerOpen,
      reason: '章節 Drawer 未開啟',
    );
    // Wait for the drawer route and its current-chapter auto-scroll to attach
    // before asking the lazy ListView to materialize a distant tile.
    await tester.pump(const Duration(milliseconds: 350));

    final title = chapters[index].title;
    final tile = find.descendant(of: drawer, matching: find.text(title));
    final drawerScrollables = find.descendant(
      of: drawer,
      matching: find.byType(Scrollable),
    );
    expect(drawerScrollables, findsOneWidget);
    final scrollableState = tester.state<ScrollableState>(
      drawerScrollables.last,
    );
    final targetOffset = (index * 56.0)
        .clamp(
          scrollableState.position.minScrollExtent,
          scrollableState.position.maxScrollExtent,
        )
        .toDouble();
    scrollableState.position.jumpTo(targetOffset);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tile, findsOneWidget, reason: 'Drawer 找不到章節 $index：$title');
    await tester.ensureVisible(tile);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 250));

    // The title is rendered in the top menu only while controls are visible.
    // Reopen them after the drawer closes before asserting the actual runtime
    // chapter title.
    await _waitForChapterDrawerToClose(scaffoldState);
    await showControls();
    await pumpUntil(
      tester,
      () => find.text(title).hitTestable().evaluate().isNotEmpty,
      timeout: const Duration(seconds: 60),
      reason: '跳章後沒有顯示 ${index + 1}：$title',
    );
    debugPrint('READER_E2E_CHAPTER index=$index title=$title');
    expectNoFlutterException();
  }

  ScaffoldState _readerScaffoldState() {
    for (final element in find.byType(Scaffold).evaluate()) {
      if (element is! StatefulElement) continue;
      final state = element.state;
      if (state is ScaffoldState &&
          state.widget.drawer is ReaderV2ChaptersDrawer) {
        return state;
      }
    }
    fail('找不到 ReaderV2Page 的 ScaffoldState');
  }

  Future<void> runScrollMatrix() async {
    await dismissControls();
    final reader = find.byType(HybridReaderScreen).first;
    // Slow reading: small moves with a pause between directions.
    await tester.drag(reader, const Offset(0, -180));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.drag(reader, const Offset(0, -260));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.drag(reader, const Offset(0, 220));
    await tester.pump(const Duration(milliseconds: 400));

    // Manual-like drag: multiple pointer moves, a pause, then a reversal.
    final center = tester.getCenter(reader);
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.moveBy(const Offset(0, -360));
    await tester.pump(const Duration(milliseconds: 180));
    await gesture.moveBy(const Offset(0, 160));
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 600));

    // Aggressive fling and immediate direction reversal.
    await tester.fling(reader, const Offset(0, -1800), 4200);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.fling(reader, const Offset(0, 1700), 3800);
    await tester.pump(const Duration(milliseconds: 900));
    expectNoFlutterException();
  }

  Future<void> dismissControls() async {
    final controls = find.text('目錄').hitTestable().evaluate().isNotEmpty;
    if (!controls) return;
    final viewport = tester.binding.renderViews.single.size;
    await tester.tapAt(Offset(viewport.width / 2, viewport.height / 2));
    await tester.pump(const Duration(milliseconds: 250));
    await pumpUntil(
      tester,
      () => find.text('目錄').hitTestable().evaluate().isEmpty,
      reason: 'Reader controls 未關閉',
    );
  }

  Future<void> toggleTtsWhileScrolling() async {
    await showControls();
    await tester.tap(find.text('朗讀').last);
    await tester.pump(const Duration(milliseconds: 250));
    final start = find.text('從目前位置朗讀');
    if (start.evaluate().isNotEmpty) {
      await tester.tap(start);
      await tester.pump(const Duration(milliseconds: 350));
    }

    // The TTS sheet owns the controls surface, so close only the sheet after
    // starting playback.  This leaves the real Reader/TTS controller active
    // while the viewport receives slow, large, and reverse scroll input.
    if (find.text('朗讀').evaluate().length > 1) {
      final sheetTitle = find.text('朗讀').last;
      Navigator.of(tester.element(sheetTitle)).pop();
      await tester.pump(const Duration(milliseconds: 250));
    }
    await dismissControls();
    final reader = find.byType(HybridReaderScreen).first;
    final gesture = await tester.startGesture(tester.getCenter(reader));
    await moveVsyncPaced(
      tester,
      gesture,
      const Offset(0, -260),
      duration: const Duration(milliseconds: 180),
    );
    await gesture.up();
    await pumpVsyncPaced(tester, const Duration(milliseconds: 450));
    await tester.fling(reader, const Offset(0, 1500), 3600);
    // Let the bounded ballistic tail finish before opening the stop sheet;
    // otherwise a late physics tick can look like an idle-frame I7 change.
    await pumpVsyncPaced(tester, const Duration(milliseconds: 2500));

    // Reopen the sheet and stop after the scroll work.  The stop tap is
    // intentionally exercised even when the platform test engine cannot
    // provide audio_service; that exception is logged by the existing
    // harness and is not treated as production Android TTS evidence.
    await showControls();
    await tester.tap(find.text('朗讀').last);
    await tester.pump(const Duration(milliseconds: 250));
    final stop = find.text('停止');
    if (stop.evaluate().isNotEmpty) {
      await tester.tap(stop);
      await tester.pump(const Duration(milliseconds: 350));
    }
    // Close the TTS sheet if the platform TTS implementation kept it open.
    if (find.text('朗讀').evaluate().length > 1) {
      final sheetTitle = find.text('朗讀').last;
      Navigator.of(tester.element(sheetTitle)).pop();
      await tester.pump(const Duration(milliseconds: 250));
    }
    expectNoFlutterException();
  }

  /// Pure TTS control transition used by the operation attribution workload.
  /// It deliberately excludes the scroll portion covered by the monkey test.
  Future<void> toggleTts() async {
    await showControls();
    await tester.tap(find.text('朗讀').last);
    await tester.pump(const Duration(milliseconds: 250));
    final start = find.text('從目前位置朗讀');
    if (start.evaluate().isNotEmpty) {
      await tester.tap(start);
      await tester.pump(const Duration(milliseconds: 350));
    }
    if (find.text('朗讀').evaluate().length > 1) {
      Navigator.of(tester.element(find.text('朗讀').last)).pop();
      await tester.pump(const Duration(milliseconds: 250));
    }
    await showControls();
    await tester.tap(find.text('朗讀').last);
    await tester.pump(const Duration(milliseconds: 250));
    final stop = find.text('停止');
    if (stop.evaluate().isNotEmpty) {
      await tester.tap(stop);
      await tester.pump(const Duration(milliseconds: 350));
    }
    if (find.text('朗讀').evaluate().length > 1) {
      Navigator.of(tester.element(find.text('朗讀').last)).pop();
      await tester.pump(const Duration(milliseconds: 250));
    }
    await dismissControls();
    expectNoFlutterException();
  }

  Future<void> exerciseLifecycleAndReopen() async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ReaderV2Page), findsOneWidget);
    expectNoFlutterException();

    await showControls();
    final backButton = find.byIcon(Icons.arrow_back).hitTestable();
    expect(backButton, findsOneWidget, reason: 'Reader 返回按鈕未顯示');
    await tester.tap(backButton);
    await tester.pump(const Duration(milliseconds: 500));
    await pumpUntil(
      tester,
      () => find.byType(BookshelfPage).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 60),
      reason: 'Reader 返回後沒有回到書架',
    );
    await openBook();
    expect(find.byType(ReaderV2Page), findsOneWidget);
    debugPrint('READER_E2E_REOPEN status=success');
  }

  void expectNoFlutterException() {
    final exception = tester.takeException();
    expect(exception, isNull, reason: 'Reader workload 遇到 Flutter exception');
  }
}
