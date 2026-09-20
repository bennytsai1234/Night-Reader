import 'dart:ui' as ui;

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
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/features/reader_v2/hybrid/layout/reader_paragraph_layout.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_controller_host.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reader_v2_state_transition_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const viewport = Size(360, 640);
  const owner = Object();
  final cases =
      <
        ({
          String name,
          void Function(ReaderV2SettingsController settings) update,
          ReaderV2Style Function(ReaderV2Style style) styleUpdate,
        })
      >[
        (
          name: 'fontSize',
          update: (settings) => settings.setFontSize(22),
          styleUpdate: (style) => style.copyWith(fontSize: 22),
        ),
        (
          name: 'lineHeight',
          update: (settings) => settings.setLineHeight(1.8),
          styleUpdate: (style) => style.copyWith(lineHeight: 1.8),
        ),
        (
          name: 'letterSpacing',
          update: (settings) => settings.setLetterSpacing(0.8),
          styleUpdate: (style) => style.copyWith(letterSpacing: 0.8),
        ),
        (
          name: 'paragraphSpacing',
          update: (settings) => settings.setParagraphSpacing(2.0),
          styleUpdate: (style) => style.copyWith(paragraphSpacing: 2.0),
        ),
        (
          name: 'textIndent',
          update: (settings) => settings.setTextIndent(4),
          styleUpdate: (style) => style.copyWith(textIndent: 4),
        ),
        (
          name: 'paddingLeft/right',
          update: (_) {},
          styleUpdate: (style) =>
              style.copyWith(paddingLeft: 24, paddingRight: 12),
        ),
        (
          name: 'lastLineSpacingCompensation',
          update: (settings) => settings.setLastLineSpacingCompensation(true),
          styleUpdate: (style) =>
              style.copyWith(lastLineSpacingCompensation: true),
        ),
      ];

  late AppDatabase database;
  late Book book;
  late List<BookChapter> chapters;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    database = AppDatabase.forTesting(NativeDatabase.memory());
    final getIt = GetIt.instance;
    await getIt.reset();
    getIt.registerSingleton<BookDao>(database.bookDao);
    getIt.registerSingleton<BookSourceDao>(database.bookSourceDao);
    getIt.registerSingleton<ChapterDao>(database.chapterDao);

    book = Book(
      bookUrl: 'https://style.example/book/1',
      name: '樣式測試書',
      author: '作者',
      origin: 'https://style.example',
      originName: '樣式測試源',
    );
    chapters = <BookChapter>[
      BookChapter(
        url: 'https://style.example/chapter/0',
        title: '第一章',
        bookUrl: book.bookUrl,
        index: 0,
        content:
            '第一句錨定文字保留。第二句是在尚未 settle 時使用的語意位置。'
            '第三句用來確認位置沒有跳到別的句子。'
            '\n\n'
            '第二段有足夠內容讓字級、行高、字距與段距真的參與排版。',
      ),
      BookChapter(
        url: 'https://style.example/chapter/1',
        title: '第二章',
        bookUrl: book.bookUrl,
        index: 1,
        content: '第二章內容用於鄰接章節的有限排版驗證。',
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
    final runtime = host.ensureRuntime(viewport, initialStyle);
    runtime.registerViewportRestore(host, (_) async => true);
    await runtime.openBook();
    await tester.pump();
    await tester.pump();
    expect(runtime.state.hasStableWorld, isTrue);
    return (host: host, runtime: runtime);
  }

  Future<void> applyStyle(
    WidgetTester tester, {
    required ReaderV2ControllerHost host,
    required ReaderV2Runtime runtime,
    required ReaderV2Style style,
  }) async {
    host.syncRuntimeConfiguration(runtime, viewport, style);
    WidgetsBinding.instance.ensureVisualUpdate();
    await tester.pump();
    await pumpUntilReady(tester, runtime);
  }

  ReaderV2Style settingsStyle(ReaderV2SettingsController settings) {
    return settings.readStyleFor(
      EdgeInsets.zero,
      topInfoReservedExternally: true,
      bottomInfoReservedExternally: true,
    );
  }

  for (final testCase in cases) {
    testWidgets(
      '逐維矩陣 ${testCase.name}：anchor、generation/epoch、metrics',
      (tester) async {

        final harness = await makeHarness(tester);
        final beforeLocation = harness.runtime.state.visibleLocation;
        final beforeContent = await harness.runtime.loadContentAt(0);
        final beforeGeneration = harness.runtime.state.layoutGeneration;
        final beforeContentGeneration =
            harness.runtime.state.contentGeneration;
        final beforeSignature =
            harness.runtime.state.layoutSpec.layoutSignature;

        testCase.update(harness.host.settings);
        final nextStyle = testCase.name == 'paddingLeft/right'
            ? testCase.styleUpdate(settingsStyle(harness.host.settings))
            : settingsStyle(harness.host.settings);
        await applyStyle(
          tester,
          host: harness.host,
          runtime: harness.runtime,
          style: nextStyle,
        );

        final afterState = harness.runtime.state;
        final afterContent = await harness.runtime.loadContentAt(0);
        expect(afterState.layoutSpec.layoutSignature, isNot(beforeSignature));
        expectReaderLayoutGenerationAdvanced(
          beforeGeneration,
          afterState.layoutGeneration,
        );
        expect(afterState.contentGeneration, beforeContentGeneration);
        expectReaderAnchorPreserved(
          ReaderAnchorProbe.capture(
            location: beforeLocation,
            sourceText: beforeContent.displayText,
          ),
          ReaderAnchorProbe.capture(
            location: afterState.visibleLocation,
            sourceText: afterContent.displayText,
          ),
        );
      },
    );
  }

  testWidgets('lineHeight clamp：等價正規化輸入不重複重排', (tester) async {
    final harness = await makeHarness(tester);
    final settings = harness.host.settings;

    settings.setLineHeight(0.5);
    expect(settings.lineHeight, ReaderV2Style.minReadableLineHeight);
    await applyStyle(
      tester,
      host: harness.host,
      runtime: harness.runtime,
      style: settingsStyle(settings),
    );
    final clampedLowSignature =
        harness.runtime.state.layoutSpec.layoutSignature;
    final clampedLowGeneration = harness.runtime.state.layoutGeneration;

    settings.setLineHeight(1.0);
    expect(settings.lineHeight, ReaderV2Style.minReadableLineHeight);
    await applyStyle(
      tester,
      host: harness.host,
      runtime: harness.runtime,
      style: settingsStyle(settings),
    );
    expect(
      harness.runtime.state.layoutSpec.layoutSignature,
      clampedLowSignature,
    );
    expect(harness.runtime.state.layoutGeneration, clampedLowGeneration);

    settings.setLineHeight(4.0);
    expect(settings.lineHeight, 3.0);
    await applyStyle(
      tester,
      host: harness.host,
      runtime: harness.runtime,
      style: settingsStyle(settings),
    );
    final clampedHighSignature =
        harness.runtime.state.layoutSpec.layoutSignature;
    expect(clampedHighSignature, isNot(clampedLowSignature));

    settings.setLineHeight(3.5);
    expect(settings.lineHeight, 3.0);
    await applyStyle(
      tester,
      host: harness.host,
      runtime: harness.runtime,
      style: settingsStyle(settings),
    );
    expect(
      harness.runtime.state.layoutSpec.layoutSignature,
      clampedHighSignature,
    );
    expect(harness.runtime.state.layoutGeneration, clampedLowGeneration + 1);
  });

  test(
    'cellWidth remains typography-only and never changes viewport content width',
    () {
      const style = ReaderV2LayoutStyle(
        fontSize: 20,
        lineHeight: 1.5,
        letterSpacing: 0,
        paragraphSpacing: 1,
        paddingTop: 8,
        paddingBottom: 8,
        paddingLeft: 16,
        paddingRight: 16,
      );
      const paragraphLayout = ReaderParagraphLayout();
      final measuredCell = paragraphLayout.measureCellWidth(
        fontSize: style.fontSize,
        letterSpacing: style.letterSpacing,
        bold: style.bold,
      );
      expect(measuredCell, isNotNull);
      final measured = ReaderV2LayoutSpec.fromViewport(
        viewportSize: const ui.Size(413, 800),
        style: style,
        cellWidth: measuredCell,
      );
      final unmeasured = ReaderV2LayoutSpec.fromViewport(
        viewportSize: const ui.Size(413, 800),
        style: style,
      );
      expect(measured.cellWidth, measuredCell);
      expect(unmeasured.cellWidth, isNull);
      expect(measured.contentWidth, 381);
      expect(unmeasured.contentWidth, 381);
      expect(measured.contentWidth, unmeasured.contentWidth);
      expect(
        measured.style.paddingLeft +
            measured.contentWidth +
            measured.style.paddingRight,
        closeTo(413, 0.001),
      );
      expect(
        paragraphLayout.measureCellWidth(
          fontSize: 0,
          letterSpacing: 0,
          bold: false,
        ),
        isNull,
      );
      final invalidMeasurementSpec = ReaderV2LayoutSpec.fromViewport(
        viewportSize: const ui.Size(413, 800),
        style: style,
        cellWidth: null,
      );
      expect(invalidMeasurementSpec.contentWidth, unmeasured.contentWidth);
    },
  );

  test(
    'ReaderV2LayoutSpec direct lineHeight input also uses the clamp contract',
    () {
      ReaderV2LayoutStyle style(double lineHeight) => ReaderV2LayoutStyle(
        fontSize: 20,
        lineHeight: lineHeight,
        letterSpacing: 0,
        paragraphSpacing: 1,
        paddingTop: 8,
        paddingBottom: 8,
        paddingLeft: 16,
        paddingRight: 16,
      );

      final belowMinimum = ReaderV2LayoutSpec.fromViewport(
        viewportSize: viewport,
        style: style(0.5),
      );
      final minimum = ReaderV2LayoutSpec.fromViewport(
        viewportSize: viewport,
        style: style(ReaderV2LayoutStyle.minReadableLineHeight),
      );
      final aboveMaximum = ReaderV2LayoutSpec.fromViewport(
        viewportSize: viewport,
        style: style(4.0),
      );
      final maximum = ReaderV2LayoutSpec.fromViewport(
        viewportSize: viewport,
        style: style(ReaderV2LayoutStyle.maxReadableLineHeight),
      );

      expect(belowMinimum.style.lineHeight, minimum.style.lineHeight);
      expect(belowMinimum.layoutSignature, minimum.layoutSignature);
      expect(aboveMaximum.style.lineHeight, maximum.style.lineHeight);
      expect(aboveMaximum.layoutSignature, maximum.layoutSignature);
    },
  );

  test('bold 與 fontFamily 明確列為 T2 skip 的死輸入', () {
    final settings = ReaderV2SettingsController();
    addTearDown(settings.dispose);
    final style = settings.readStyleFor(
      EdgeInsets.zero,
      topInfoReservedExternally: true,
      bottomInfoReservedExternally: true,
    );

    // readStyleFor hard-codes bold=false. ReaderV2Style has no fontFamily
    // field, so neither input is a user-changeable T2 style dimension.
    expect(style.bold, isFalse);
  });

  testWidgets('兩維同時變更只觸發一次重排並保留 anchor', (tester) async {
    final harness = await makeHarness(tester);
    final before = harness.runtime.state.visibleLocation;
    final beforeContent = await harness.runtime.loadContentAt(0);
    final beforeGeneration = harness.runtime.state.layoutGeneration;
    final beforeContentGeneration = harness.runtime.state.contentGeneration;

    harness.host.settings.setTypography(fontSize: 22, lineHeight: 1.8);
    await applyStyle(
      tester,
      host: harness.host,
      runtime: harness.runtime,
      style: settingsStyle(harness.host.settings),
    );
    expectReaderLayoutGenerationAdvanced(
      beforeGeneration,
      harness.runtime.state.layoutGeneration,
    );
    expect(harness.runtime.state.contentGeneration, beforeContentGeneration);
    expectReaderAnchorPreserved(
      ReaderAnchorProbe.capture(
        location: before,
        sourceText: beforeContent.displayText,
      ),
      ReaderAnchorProbe.capture(
        location: harness.runtime.state.visibleLocation,
        sourceText: (await harness.runtime.loadContentAt(0)).displayText,
      ),
    );
  });

  testWidgets('連續快速 style 變更只留下最後 signature 與世代', (tester) async {
    final harness = await makeHarness(tester);
    final initialGeneration = harness.runtime.state.layoutGeneration;
    final initialStyle = settingsStyle(harness.host.settings);
    final styles = <ReaderV2Style>[
      initialStyle.copyWith(fontSize: 19),
      initialStyle.copyWith(fontSize: 20),
      initialStyle.copyWith(fontSize: 22),
    ];

    for (final style in styles) {
      harness.host.syncRuntimeConfiguration(harness.runtime, viewport, style);
    }
    WidgetsBinding.instance.ensureVisualUpdate();
    await tester.pump();
    await pumpUntilReady(tester, harness.runtime);
    expect(harness.runtime.state.layoutSpec.style.fontSize, 22);
    expect(harness.runtime.state.layoutGeneration, initialGeneration + 1);
  });

  testWidgets('scroll 尚未 settle 時 style 變更仍以當下 semantic anchor restore', (
    tester,
  ) async {
    final harness = await makeHarness(tester);
    final content = await harness.runtime.loadContentAt(0);
    final movingOffset = content.displayText.indexOf('第二句');
    expect(movingOffset, greaterThan(0));
    final movingLocation = ReaderV2Location(
      chapterIndex: 0,
      charOffset: movingOffset,
    );
    harness.runtime.updateVisibleLocation(movingLocation);
    var settled = false;
    harness.runtime.registerVisibleLocationCapture(owner, () {
      return settled ? harness.runtime.state.visibleLocation : movingLocation;
    });
    addTearDown(() => harness.runtime.unregisterVisibleLocationCapture(owner));

    await applyStyle(
      tester,
      host: harness.host,
      runtime: harness.runtime,
      style: harness.host.settings
          .readStyleFor(
            EdgeInsets.zero,
            topInfoReservedExternally: true,
            bottomInfoReservedExternally: true,
          )
          .copyWith(fontSize: 22),
    );
    expect(settled, isFalse);
    expectReaderAnchorPreserved(
      ReaderAnchorProbe.capture(
        location: movingLocation,
        sourceText: content.displayText,
      ),
      ReaderAnchorProbe.capture(
        location: harness.runtime.state.visibleLocation,
        sourceText: (await harness.runtime.loadContentAt(0)).displayText,
      ),
    );
    settled = true;
  });
}
