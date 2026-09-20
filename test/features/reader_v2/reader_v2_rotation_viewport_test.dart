import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_controller_host.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reader_v2_state_transition_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late Book book;
  late List<BookChapter> chapters;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    database = AppDatabase.forTesting(NativeDatabase.memory());
    final getIt = GetIt.instance;
    await getIt.reset();
    getIt.registerSingleton<BookDao>(database.bookDao);
    getIt.registerSingleton<BookSourceDao>(database.bookSourceDao);
    getIt.registerSingleton<ChapterDao>(database.chapterDao);

    book = Book(
      bookUrl: 'https://rotation.example/book/1',
      name: '旋轉測量書',
      author: '作者',
      origin: 'https://rotation.example',
      originName: '旋轉測量源',
    );
    final longChapter = List<String>.generate(
      80,
      (index) => '第${index + 1}句旋轉錨定文字，用於確認 exact anchor 不會漂移。',
    ).join();
    chapters = <BookChapter>[
      BookChapter(
        url: 'https://rotation.example/chapter/0',
        title: '第一章',
        bookUrl: book.bookUrl,
        index: 0,
        content: longChapter,
      ),
      BookChapter(
        url: 'https://rotation.example/chapter/1',
        title: '極短章節',
        bookUrl: book.bookUrl,
        index: 1,
        content: '極短章唯一錨定文字。',
      ),
      BookChapter(
        url: 'https://rotation.example/chapter/2',
        title: '章末測試章節',
        bookUrl: book.bookUrl,
        index: 2,
        content: List<String>.generate(
          60,
          (index) => '章末第${index + 1}句語意位置，用於邊界旋轉驗證。',
        ).join(),
      ),
    ];
  });

  tearDown(() async {
    await GetIt.instance.reset();
    await database.close();
  });

  Future<void> pumpUntilReady(
    WidgetTester tester,
    ReaderV2Runtime runtime, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!runtime.state.hasStableWorld ||
        runtime.stateMachine.currentOperation != null) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Reader runtime did not settle: lifecycle=${runtime.state.lifecycle}, operation=${runtime.stateMachine.currentOperation?.kind}');
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump();
  }

  Future<({ReaderV2ControllerHost host, ReaderV2Runtime runtime})> makeHarness(
    WidgetTester tester,
  ) async {
    var mounted = true;
    final host = ReaderV2ControllerHost(
      book: book,
      initialChapters: chapters,
      openTarget: null,
      onChanged: () {},
      isMounted: () => mounted,
    );
    addTearDown(() {
      mounted = false;
      host.dispose();
    });
    final initialStyle = host.settings.readStyleFor(
      EdgeInsets.zero,
      topInfoReservedExternally: true,
      bottomInfoReservedExternally: true,
    );
    final runtime = host.ensureRuntime(const Size(360, 640), initialStyle);
    runtime.registerViewportRestore(host, (_) async => true);
    // This harness exercises Runtime's viewport seam without mounting the
    // production Hybrid viewport. The fake owner acknowledges semantic
    // positioning; Runtime remains the sole operation/state owner.
    // ensureRuntime owns the first-frame open. Start a frame explicitly, then
    // wait on the real runtime phase so a later open cannot race a jump.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpUntilReady(tester, runtime);
    expect(runtime.state.hasStableWorld, isTrue);
    return (host: host, runtime: runtime);
  }

  Future<void> applyViewport(
    WidgetTester tester, {
    required ReaderV2ControllerHost host,
    required ReaderV2Runtime runtime,
    required Size size,
    required EdgeInsets padding,
  }) async {
    final style = host.settings.readStyleFor(
      padding,
      topInfoReservedExternally: true,
      bottomInfoReservedExternally: true,
    );
    host.syncRuntimeConfiguration(runtime, size, style);
    WidgetsBinding.instance.ensureVisualUpdate();
    await tester.pump();
    await pumpUntilReady(tester, runtime);
  }

  Future<ReaderAnchorProbe> captureAnchor(
    ReaderV2Runtime runtime,
    ReaderV2Location location,
  ) async {
    final content = await runtime.loadContentAt(location.chapterIndex);
    return ReaderAnchorProbe.capture(
      location: location,
      sourceText: content.displayText,
    );
  }

  Future<void> jumpTo(
    WidgetTester tester,
    ReaderV2Runtime runtime,
    ReaderV2Location location,
  ) async {
    await runtime.jumpToLocation(location, immediateSave: false);
    await tester.pump();
    await pumpUntilReady(tester, runtime);
    expect(runtime.state.visibleLocation.chapterIndex, location.chapterIndex);
  }

  testWidgets('S1 continuous viewport/inset gradient measures each frame', (
    tester,
  ) async {

    var mounted = true;
    final host = ReaderV2ControllerHost(
      book: book,
      initialChapters: chapters,
      openTarget: null,
      onChanged: () {},
      isMounted: () => mounted,
    );
    addTearDown(() {
      mounted = false;
      host.dispose();
    });

    const initialSize = Size(360, 640);
    final initialStyle = host.settings.readStyleFor(
      EdgeInsets.zero,
      topInfoReservedExternally: true,
      bottomInfoReservedExternally: true,
    );
    final runtime = host.ensureRuntime(initialSize, initialStyle);
    runtime.registerViewportRestore(host, (_) async => true);
    await runtime.openBook();
    await tester.pump();
    await tester.pump();
    expect(runtime.state.hasStableWorld, isTrue);

    const frameCount = 12;
    for (var frame = 1; frame <= frameCount; frame += 1) {
      final progress = frame / frameCount;
      final size = Size(360 + (640 * progress), 640 - (280 * progress));
      final padding = EdgeInsets.only(
        top: 24 * progress,
        bottom: 18 * (1 - progress),
      );
      final style = host.settings.readStyleFor(
        padding,
        topInfoReservedExternally: true,
        bottomInfoReservedExternally: true,
      );
      host.syncRuntimeConfiguration(runtime, size, style);
      WidgetsBinding.instance.ensureVisualUpdate();
      await tester.pump(const Duration(milliseconds: 16));
    }

    // Allow the final transition to settle before recording the ending state.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!runtime.state.hasStableWorld ||
        runtime.stateMachine.currentOperation != null) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Reader runtime did not settle: lifecycle=${runtime.state.lifecycle}, operation=${runtime.stateMachine.currentOperation?.kind}');
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump();

    // Continuous viewport updates coalesce to one committed layout generation.
    expect(runtime.state.layoutSpec.viewportSize, const Size(1000, 360));
    expect(runtime.state.layoutGeneration, 1);
  });

  testWidgets(
    'S3 portrait-landscape-portrait repeated trips preserve exact anchor',
    (tester) async {
      final harness = await makeHarness(tester);
      final content = await harness.runtime.loadContentAt(0);
      final offset = content.displayText.indexOf('第41句');
      expect(offset, greaterThan(0));
      final location = ReaderV2Location(chapterIndex: 0, charOffset: offset);
      await jumpTo(tester, harness.runtime, location);
      final before = await captureAnchor(harness.runtime, location);
      final initialGeneration = harness.runtime.state.layoutGeneration;

      const trips = 5;
      for (var trip = 0; trip < trips; trip += 1) {
        await applyViewport(
          tester,
          host: harness.host,
          runtime: harness.runtime,
          size: const Size(800, 360),
          padding: EdgeInsets.only(top: 12 + trip.toDouble()),
        );
        final landscape = harness.runtime.state.visibleLocation;
        expectReaderAnchorPreserved(
          before,
          await captureAnchor(harness.runtime, landscape),
        );
        expect(landscape.charOffset, location.charOffset);

        await applyViewport(
          tester,
          host: harness.host,
          runtime: harness.runtime,
          size: const Size(360, 640),
          padding: EdgeInsets.only(bottom: 8 + trip.toDouble()),
        );
        final portrait = harness.runtime.state.visibleLocation;
        expectReaderAnchorPreserved(
          before,
          await captureAnchor(harness.runtime, portrait),
        );
        expect(portrait.charOffset, location.charOffset);
      }
      expect(
        harness.runtime.state.layoutGeneration,
        initialGeneration + (trips * 2),
      );
    },
  );

  testWidgets(
    'S3 rotation before scroll settle preserves moving exact anchor',
    (tester) async {
      final harness = await makeHarness(tester);
      final content = await harness.runtime.loadContentAt(0);
      final offset = content.displayText.indexOf('第57句');
      expect(offset, greaterThan(0));
      final movingLocation = ReaderV2Location(
        chapterIndex: 0,
        charOffset: offset,
        visualOffsetPx: 36,
      );
      harness.runtime.updateVisibleLocation(movingLocation);
      var settled = false;
      final owner = Object();
      harness.runtime.registerVisibleLocationCapture(owner, () {
        return settled ? harness.runtime.state.visibleLocation : movingLocation;
      });
      addTearDown(
        () => harness.runtime.unregisterVisibleLocationCapture(owner),
      );
      final before = await captureAnchor(harness.runtime, movingLocation);

      await applyViewport(
        tester,
        host: harness.host,
        runtime: harness.runtime,
        size: const Size(800, 360),
        padding: const EdgeInsets.only(top: 20, bottom: 6),
      );
      settled = true;

      final after = harness.runtime.state.visibleLocation;
      expectReaderAnchorPreserved(
        before,
        await captureAnchor(harness.runtime, after),
      );
      expect(after.charOffset, movingLocation.charOffset);
      expect(after.visualOffsetPx, movingLocation.visualOffsetPx);
      debugPrint(
        'S3 unsettled rotation evidence: before=$movingLocation, after=$after',
      );
    },
  );

  testWidgets('S3 chapter start, chapter end, and very short chapter anchors', (
    tester,
  ) async {
    final harness = await makeHarness(tester);
    final chapterEndContent = await harness.runtime.loadContentAt(2);
    final cases = <ReaderV2Location>[
      const ReaderV2Location(chapterIndex: 0, charOffset: 0),
      ReaderV2Location(
        chapterIndex: 2,
        charOffset: chapterEndContent.displayText.length - 1,
      ),
      const ReaderV2Location(chapterIndex: 1, charOffset: 0),
    ];

    for (final location in cases) {
      await jumpTo(tester, harness.runtime, location);
      final before = await captureAnchor(
        harness.runtime,
        harness.runtime.state.visibleLocation,
      );
      await applyViewport(
        tester,
        host: harness.host,
        runtime: harness.runtime,
        size: const Size(800, 360),
        padding: const EdgeInsets.symmetric(vertical: 10),
      );
      final afterLandscape = harness.runtime.state.visibleLocation;
      expectReaderAnchorPreserved(
        before,
        await captureAnchor(harness.runtime, afterLandscape),
      );
      await applyViewport(
        tester,
        host: harness.host,
        runtime: harness.runtime,
        size: const Size(360, 640),
        padding: EdgeInsets.zero,
      );
      final afterPortrait = harness.runtime.state.visibleLocation;
      expectReaderAnchorPreserved(
        before,
        await captureAnchor(harness.runtime, afterPortrait),
      );
      expect(afterPortrait.chapterIndex, location.chapterIndex);
      debugPrint(
        'S3 boundary evidence: requested=$location, '
        'final=$afterPortrait, anchor=${before.anchorText}',
      );
    }
  });
}
