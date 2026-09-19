import 'dart:io';
import 'dart:ui' show Size;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/engine/reader/chinese_text_converter.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_state.dart';

import 'reader_v2_state_transition_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(ChineseUtils.initialize);
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => database.close());

  const rawContent = '前文。騄後文。結尾。';

  Future<ReaderV2Runtime> makeRuntime({
    required int Function() convertType,
  }) async {
    final book = Book(
      bookUrl: 'http://convert.test',
      name: '簡繁切換測試',
      author: '作者',
      origin: 'local',
      originName: '本地',
    );
    final bookDao = database.bookDao;
    final chapterDao = database.chapterDao;
    final sourceDao = database.bookSourceDao;
    final contentDao = database.readerChapterContentDao;
    await contentDao.saveContent(
      contentKey: ReaderChapterContentDao.contentKey(
        origin: book.origin,
        bookUrl: book.bookUrl,
        chapterUrl: 'chapter_0',
      ),
      origin: book.origin,
      bookUrl: book.bookUrl,
      chapterUrl: 'chapter_0',
      chapterIndex: 0,
      content: rawContent,
      updatedAt: 1,
    );
    final repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: <BookChapter>[
        BookChapter(
          url: 'chapter_0',
          title: '第一章',
          bookUrl: book.bookUrl,
          index: 0,
          content: rawContent,
        ),
      ],
      bookDao: bookDao,
      chapterDao: chapterDao,
      sourceDao: sourceDao,
      contentDao: contentDao,
      currentChineseConvert: convertType,
    );
    final runtime = ReaderV2Runtime(
      book: book,
      repository: repository,
      progressController: ReaderV2ProgressController(
        book: book,
        repository: repository,
        bookDao: bookDao,
      ),
      initialLayoutSpec: ReaderV2LayoutSpec.fromViewport(
        viewportSize: const Size(240, 320),
        style: const ReaderV2LayoutStyle(
          fontSize: 18,
          lineHeight: 1.5,
          letterSpacing: 0,
          paragraphSpacing: 0.8,
          paddingTop: 12,
          paddingBottom: 12,
          paddingLeft: 12,
          paddingRight: 12,
          textIndent: 0,
        ),
      ),
      initialLocation: const ReaderV2Location(chapterIndex: 0, charOffset: 0),
    );
    runtime.registerViewportRestore(Object(), (_) async => true);
    return runtime;
  }

  test('semantic mapper maps an expanded code point after the mapped rune', () {
    final before = ReaderV2Content.fromRaw(
      chapterIndex: 0,
      title: '第一章',
      rawText: rawContent,
    );
    final after = ReaderV2Content.fromRaw(
      chapterIndex: 0,
      title: '第一章',
      rawText: '前文。𫘧後文。結尾。',
    );
    final oldOffset = before.displayText.indexOf('騄') + 1;
    final mapped = ReaderV2ContentLocationMapper.remap(
      location: ReaderV2Location(chapterIndex: 0, charOffset: oldOffset),
      before: before,
      after: after,
    );

    expect(mapped.charOffset, oldOffset + 1);
    expect(
      after.displayText.substring(mapped.charOffset - 2, mapped.charOffset),
      '𫘧',
    );
  });

  test('semantic mapper remaps an actual samples fixture offset', () async {
    final sample = await File('samples/西游记.txt').readAsString();
    final convertedSample = const ChineseTextConverter().convert(
      sample,
      convertType: 2,
    );
    final before = ReaderV2Content.fromRaw(
      chapterIndex: 0,
      title: '西游记',
      rawText: sample,
    );
    final after = ReaderV2Content.fromRaw(
      chapterIndex: 0,
      title: '西游记',
      rawText: convertedSample,
    );
    final oldOffset = before.displayText.indexOf('騄') + 1;
    expect(oldOffset, greaterThan(0));
    final mapped = ReaderV2ContentLocationMapper.remap(
      location: ReaderV2Location(chapterIndex: 0, charOffset: oldOffset),
      before: before,
      after: after,
    );
    expect(mapped.charOffset, oldOffset + 1);
    expectReaderAnchorPreserved(
      ReaderAnchorProbe.capture(
        location: ReaderV2Location(chapterIndex: 0, charOffset: oldOffset),
        sourceText: before.displayText,
      ),
      ReaderAnchorProbe.capture(
        location: mapped,
        sourceText: after.displayText,
      ),
      mode: ReaderAnchorComparisonMode.equivalentText,
      equivalentConversionType: 2,
    );
  });

  test('0 to 1 preserves the equivalent sentence anchor', () async {
    var convertType = 0;
    final runtime = await makeRuntime(convertType: () => convertType);
    addTearDown(runtime.dispose);
    await runtime.openBook();
    final beforeContent = await runtime.loadContentAt(0);
    final beforeLocation = ReaderV2Location(
      chapterIndex: 0,
      charOffset: beforeContent.displayText.indexOf('騄') + 1,
    );
    runtime.updateVisibleLocation(beforeLocation);
    final beforeProbe = ReaderAnchorProbe.capture(
      location: beforeLocation,
      sourceText: beforeContent.displayText,
    );

    convertType = 1;
    await runtime.reloadContentPreservingLocation();
    final afterContent = await runtime.loadContentAt(0);
    final after = runtime.state.visibleLocation;
    expectReaderAnchorPreserved(
      beforeProbe,
      ReaderAnchorProbe.capture(
        location: after,
        sourceText: afterContent.displayText,
      ),
      mode: ReaderAnchorComparisonMode.equivalentText,
      equivalentConversionType: 1,
    );
    expect(after.charOffset, beforeLocation.charOffset);
  });

  test('1 to 2 remaps the expanded code-point offset', () async {
    var convertType = 1;
    final runtime = await makeRuntime(convertType: () => convertType);
    addTearDown(runtime.dispose);
    await runtime.openBook();
    final beforeContent = await runtime.loadContentAt(0);
    final oldOffset = beforeContent.displayText.indexOf('騄') + 1;
    final beforeLocation = ReaderV2Location(
      chapterIndex: 0,
      charOffset: oldOffset,
    );
    runtime.updateVisibleLocation(beforeLocation);
    final beforeProbe = ReaderAnchorProbe.capture(
      location: beforeLocation,
      sourceText: beforeContent.displayText,
    );

    convertType = 2;
    await runtime.reloadContentPreservingLocation();
    final afterContent = await runtime.loadContentAt(0);
    final after = runtime.state.visibleLocation;
    expect(afterContent.displayText, contains('𫘧'));
    expect(afterContent.contentHash, isNot(beforeContent.contentHash));
    expect(runtime.repository.cachedContent(0), same(afterContent));
    expectReaderAnchorPreserved(
      beforeProbe,
      ReaderAnchorProbe.capture(
        location: after,
        sourceText: afterContent.displayText,
      ),
      mode: ReaderAnchorComparisonMode.equivalentText,
      equivalentConversionType: 2,
    );
    expect(after.charOffset, oldOffset + 1);
  });

  test('2 to 0 remaps back from the supplementary code point', () async {
    var convertType = 2;
    final runtime = await makeRuntime(convertType: () => convertType);
    addTearDown(runtime.dispose);
    await runtime.openBook();
    final beforeContent = await runtime.loadContentAt(0);
    final oldOffset = beforeContent.displayText.indexOf('𫘧') + 2;
    final beforeLocation = ReaderV2Location(
      chapterIndex: 0,
      charOffset: oldOffset,
    );
    runtime.updateVisibleLocation(beforeLocation);
    final beforeProbe = ReaderAnchorProbe.capture(
      location: beforeLocation,
      sourceText: beforeContent.displayText,
    );

    convertType = 0;
    await runtime.reloadContentPreservingLocation();
    final afterContent = await runtime.loadContentAt(0);
    final after = runtime.state.visibleLocation;
    expectReaderAnchorPreserved(
      beforeProbe,
      ReaderAnchorProbe.capture(
        location: after,
        sourceText: afterContent.displayText,
      ),
      mode: ReaderAnchorComparisonMode.equivalentText,
      equivalentConversionType: 2,
    );
    expect(after.charOffset, oldOffset - 1);
  });

  test(
    'chapter-end conversion moves to the new end instead of clamping',
    () async {
      var convertType = 1;
      final runtime = await makeRuntime(convertType: () => convertType);
      addTearDown(runtime.dispose);
      await runtime.openBook();
      final beforeContent = await runtime.loadContentAt(0);
      final beforeLocation = ReaderV2Location(
        chapterIndex: 0,
        charOffset: beforeContent.displayText.length,
      );
      runtime.updateVisibleLocation(beforeLocation);
      final beforeProbe = ReaderAnchorProbe.capture(
        location: beforeLocation,
        sourceText: beforeContent.displayText,
      );

      convertType = 2;
      await runtime.reloadContentPreservingLocation();
      final afterContent = await runtime.loadContentAt(0);
      final after = runtime.state.visibleLocation;
      expectReaderAnchorPreserved(
        beforeProbe,
        ReaderAnchorProbe.capture(
          location: after,
          sourceText: afterContent.displayText,
        ),
        mode: ReaderAnchorComparisonMode.equivalentText,
        equivalentConversionType: 2,
      );
      expect(after.charOffset, afterContent.displayText.length);
      expect(after.charOffset, beforeLocation.charOffset + 1);
    },
  );

  test('repeated round trips do not accumulate offset drift', () async {
    var convertType = 0;
    final runtime = await makeRuntime(convertType: () => convertType);
    addTearDown(runtime.dispose);
    await runtime.openBook();
    final initialContent = await runtime.loadContentAt(0);
    final initial = ReaderV2Location(
      chapterIndex: 0,
      charOffset: initialContent.displayText.indexOf('騄') + 1,
    );
    runtime.updateVisibleLocation(initial);
    var previousContent = initialContent;
    var previous = initial;
    for (final nextType in <int>[1, 2, 0, 1, 2, 0]) {
      final beforeProbe = ReaderAnchorProbe.capture(
        location: previous,
        sourceText: previousContent.displayText,
      );
      convertType = nextType;
      await runtime.reloadContentPreservingLocation().timeout(
        const Duration(seconds: 60),
      );
      final nextContent = await runtime.loadContentAt(0);
      final next = runtime.state.visibleLocation;
      expectReaderAnchorPreserved(
        beforeProbe,
        ReaderAnchorProbe.capture(
          location: next,
          sourceText: nextContent.displayText,
        ),
        mode: ReaderAnchorComparisonMode.equivalentText,
        equivalentConversionType: nextType == 0 ? 2 : nextType,
      );
      previousContent = nextContent;
      previous = next;
    }
    expect(previous.charOffset, initial.charOffset);
  });

  test('unsettled capture keeps semantic anchor and visual offset', () async {
    var convertType = 1;
    final runtime = await makeRuntime(convertType: () => convertType);
    addTearDown(runtime.dispose);
    await runtime.openBook();
    final beforeContent = await runtime.loadContentAt(0);
    final before = ReaderV2Location(
      chapterIndex: 0,
      charOffset: beforeContent.displayText.indexOf('騄') + 1,
      visualOffsetPx: 36,
    );
    runtime.updateVisibleLocation(before);
    final beforeProbe = ReaderAnchorProbe.capture(
      location: before,
      sourceText: beforeContent.displayText,
    );
    final owner = Object();
    runtime.registerVisibleLocationCapture(owner, () => before);
    addTearDown(() => runtime.unregisterVisibleLocationCapture(owner));

    convertType = 2;
    await runtime.reloadContentPreservingLocation();
    final afterContent = await runtime.loadContentAt(0);
    final after = runtime.state.visibleLocation;
    expectReaderAnchorPreserved(
      beforeProbe,
      ReaderAnchorProbe.capture(
        location: after,
        sourceText: afterContent.displayText,
      ),
      mode: ReaderAnchorComparisonMode.equivalentText,
      equivalentConversionType: 2,
    );
    expect(after.charOffset, before.charOffset + 1);
    expect(after.visualOffsetPx, before.visualOffsetPx);
  });

  test(
    'reload passes the remapped semantic location to the viewport owner',
    () async {
      var convertType = 1;
      final runtime = await makeRuntime(convertType: () => convertType);
      addTearDown(runtime.dispose);
      await runtime.openBook();
      final beforeContent = await runtime.loadContentAt(0);
      final oldOffset = beforeContent.displayText.indexOf('騄') + 1;
      final before = ReaderV2Location(
        chapterIndex: 0,
        charOffset: oldOffset,
        visualOffsetPx: 20,
      );
      runtime.updateVisibleLocation(before);

      final owner = Object();
      ReaderV2Location? restored;
      runtime.registerViewportRestore(owner, (location) async {
        restored = location;
        return true;
      });
      addTearDown(() {
        runtime.unregisterViewportRestore(owner);
      });

      convertType = 2;
      await runtime.reloadContentPreservingLocation();
      final afterContent = await runtime.loadContentAt(0);

      expect(restored?.charOffset, oldOffset + 1);
      expect(restored?.visualOffsetPx, before.visualOffsetPx);
      expect(runtime.state.visibleLocation.charOffset, oldOffset + 1);
      expect(
        runtime.state.visibleLocation.charOffset,
        lessThanOrEqualTo(afterContent.displayText.length),
      );
      expect(runtime.state.phase, ReaderV2Phase.ready);
    },
  );
}
