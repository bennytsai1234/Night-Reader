import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
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
import 'package:night_reader/features/reader_v2/screen/reader_v2_chapters_drawer.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_state.dart';
import 'package:night_reader/features/welcome/main_page.dart';
import 'package:night_reader/main.dart' as app;

Future<void> pumpUntil(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  }
  expect(ready(), isTrue, reason: 'Reader did not reach the requested state');
}

/// A small on-device journey. Fixture setup uses the normal TXT importer;
/// navigation and scrolling use real widgets, not a generated operation matrix.
class ReaderTestHarness {
  ReaderTestHarness(this.tester);
  final WidgetTester tester;
  late Book book;
  late List<BookChapter> chapters;

  ReaderV2Runtime get runtime => tester
      .widget<HybridReaderScreen>(find.byType(HybridReaderScreen))
      .runtime;

  Future<void> startAndProvision() async {
    app.main();
    FlutterNativeSplash.remove();
    await pumpUntil(tester, () => find.byType(MainPage).evaluate().isNotEmpty);
    final directory = await getApplicationSupportDirectory();
    final file = File('${directory.path}/reader_journey.txt');
    final text = StringBuffer('前言\n這是閱讀器驗證用的短序言。\n\n');
    const numbers = ['一', '二', '三'];
    for (final number in numbers) {
      text.writeln('第$number章 測試章節');
      for (var paragraph = 0; paragraph < 32; paragraph++) {
        text.writeln(
          '段落 $number-$paragraph。沿著山路向前走，遠方的城市逐漸亮起燈火。'
          '閱讀位置必須在捲動、跳章與重開後保持一致。\n',
        );
      }
    }
    await file.writeAsString(text.toString());
    final shelf = Provider.of<BookshelfProvider>(
      tester.element(find.byType(MainPage)),
      listen: false,
    );
    expect(await shelf.importLocalBookPath(file.path), isTrue);
    await shelf.loadBooks();
    final url = 'local://${file.path}';
    book = (await getIt<BookDao>().getByUrl(url))!;
    chapters = await getIt<ChapterDao>().getByBook(url);
    // Body lines must not match the importer's chapter-heading pattern.
    expect(chapters.length, 4);
    expect(chapters.first.title, '前言');
    for (var i = 1; i < chapters.length; i++) {
      expect(chapters[i].title, '第${numbers[i - 1]}章 測試章節');
      expect(chapters[i].end! - chapters[i].start!, greaterThan(1000));
    }
    await getIt<BookDao>().updateProgress(
      url,
      0,
      chapters.first.title,
      0,
      visualOffsetPx: 0,
      readerAnchorJson: null,
    );
    await shelf.loadBooks();
    await tester.pumpAndSettle();
  }

  Future<void> openBook() async {
    await tester.tap(find.text(book.name).first);
    await pumpUntil(
      tester,
      () => find.byType(HybridReaderScreen).evaluate().isNotEmpty,
    );
    await settled();
  }

  Future<void> settled() async {
    await pumpUntil(tester, () {
      expect(
        runtime.state.phase,
        isNot(ReaderV2Phase.error),
        reason: runtime.state.errorMessage,
      );
      return runtime.state.phase == ReaderV2Phase.ready &&
          find.byType(HybridScrollView).evaluate().isNotEmpty;
    });
    await tester.pumpAndSettle();
    final dynamic screen = tester.state(find.byType(HybridReaderScreen));
    final snapshot = screen.debugSnapshot() as Map;
    expect(snapshot['visibleKeys'], isNotEmpty);
    expect(snapshot['missingParagraphKeys'], isEmpty);
    expect(snapshot['visibleKeysContiguous'], true);
    expect(tester.takeException(), isNull);
  }

  Future<void> showControls() async {
    final menus = find.byType(ReaderV2BottomMenu);
    if (menus.evaluate().isNotEmpty &&
        tester.widget<ReaderV2BottomMenu>(menus.last).controlsVisible)
      return;
    final size = tester.binding.renderViews.single.size;
    await tester.tapAt(Offset(size.width / 2, 5));
    await tester.pumpAndSettle();
  }

  Future<void> jumpFromDirectory(int index) async {
    await showControls();
    await tester.tap(
      find
          .descendant(
            of: find.byType(ReaderV2BottomMenu),
            matching: find.text('目錄'),
          )
          .hitTestable(),
    );
    await tester.pumpAndSettle();
    final tile = find.descendant(
      of: find.byType(ReaderV2ChaptersDrawer),
      matching: find.text(chapters[index].title),
    );
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await settled();
    expect(runtime.state.visibleLocation.chapterIndex, index);
    expect(runtime.state.visibleLocation.charOffset, 0);
  }

  Future<ReaderV2Location> scrollAndSave() async {
    final menus = find.byType(ReaderV2BottomMenu);
    if (tester.widget<ReaderV2BottomMenu>(menus.last).controlsVisible) {
      await tester.tapAt(tester.getCenter(find.byType(HybridScrollView)));
      await tester.pumpAndSettle();
    }
    final before = runtime.captureVisibleLocation()!;
    await tester.drag(find.byType(HybridScrollView), const Offset(0, -220));
    await settled();
    final after = runtime.captureVisibleLocation()!;
    expect(after, isNot(before));
    await runtime.flushProgress();
    final saved = (await getIt<BookDao>().getByUrl(book.bookUrl))!;
    expect(saved.chapterIndex, after.chapterIndex);
    expect(saved.charOffset, after.charOffset);
    return after;
  }

  Future<void> reopen(ReaderV2Location expected) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await showControls();
    await tester.tap(find.byIcon(Icons.arrow_back).hitTestable());
    await pumpUntil(tester, () => find.byType(ReaderV2Page).evaluate().isEmpty);
    expect(find.byType(BookshelfPage), findsOneWidget);
    await openBook();
    final restored = runtime.captureVisibleLocation()!;
    expect(restored.chapterIndex, expected.chapterIndex);
    expect(restored.charOffset, expected.charOffset);
    expect(restored.visualOffsetPx, closeTo(expected.visualOffsetPx, 0.1));
  }
}
