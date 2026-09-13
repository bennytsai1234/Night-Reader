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
import 'package:night_reader/features/reader_v2/screen/reader_v2_chapters_drawer.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page.dart';
import 'package:night_reader/features/welcome/main_page.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:provider/provider.dart';

import 'package:night_reader/main.dart' as app;

const String readerFixturePath = String.fromEnvironment(
  'NIGHT_READER_FIXTURE_PATH',
  defaultValue: '/sdcard/Download/NightReader/西游记.txt',
);

const String readerFixtureHostPath = String.fromEnvironment(
  'NIGHT_READER_FIXTURE_HOST_PATH',
  defaultValue: 'samples/西游记.txt',
);

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  Duration step = const Duration(milliseconds: 100),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(step);
  }
  if (!condition()) {
    fail(reason ?? '條件在 $timeout 內沒有成立');
  }
}

class ReaderTestHarness {
  ReaderTestHarness(this.tester);

  final WidgetTester tester;

  late Book book;
  late List<BookChapter> chapters;

  /// Read the runtime through the test-only seam on ReaderV2Page. Keeping the
  /// lookup here lets the continuous workload exercise the same runtime jump
  /// path as the chapter drawer without making the old Drawer harness its
  /// dependency.
  ReaderV2Runtime get runtimeForTesting {
    final dynamic pageState = tester.state(find.byType(ReaderV2Page));
    final runtime = pageState.debugRuntime as ReaderV2Runtime?;
    if (runtime == null) fail('Reader runtime 尚未建立');
    return runtime;
  }

  /// Read the semantic Reader snapshot exposed by HybridReaderScreen for the
  /// continuous layout/scroll race workload.
  Map<String, Object?> debugSnapshot() {
    final dynamic screenState = tester.state(
      find.byType(HybridReaderScreen).first,
    );
    final snapshot = screenState.debugSnapshot();
    return Map<String, Object?>.from(snapshot as Map);
  }

  Map<String, Object?> debugPerformanceSummary() {
    final dynamic screenState = tester.state(
      find.byType(HybridReaderScreen).first,
    );
    final summary = screenState.debugPerformanceSummary();
    return Map<String, Object?>.from(summary as Map);
  }

  void resetPerformanceWindow() {
    final dynamic screenState = tester.state(
      find.byType(HybridReaderScreen).first,
    );
    screenState.debugResetPerformanceWindow();
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
    expect(chapters, hasLength(101), reason: '《西游记》fixture 的章節索引數量不正確');
    expect(chapters.first.title, '前言');
    expect(chapters[1].title, startsWith('第一回'));
    expect(chapters[50].index, 50);
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
    await pumpUntil(
      tester,
      () => !scaffoldState.isDrawerOpen,
      reason: 'Reader 章節 Drawer 沒有關閉',
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
    scrollableState.position.jumpTo(targetOffset);
    await tester.pump(const Duration(milliseconds: 100));

    final title = chapters[index].title;
    final tile = find.descendant(of: drawer, matching: find.text(title));
    expect(tile, findsOneWidget, reason: 'Drawer 找不到章節 $index：$title');
    await tester.ensureVisible(tile);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 120));
    await pumpUntil(
      tester,
      () => !scaffoldState.isDrawerOpen,
      timeout: const Duration(seconds: 60),
      reason: '章節 Drawer 沒有關閉',
    );
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
    await pumpUntil(
      tester,
      () => !scaffoldState.isDrawerOpen,
      reason: '章節 Drawer 沒有關閉',
    );
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
    await tester.drag(reader, const Offset(0, -260));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.fling(reader, const Offset(0, 1500), 3600);
    await tester.pump(const Duration(milliseconds: 750));

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
