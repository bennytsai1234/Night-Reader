import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_state.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ReaderV2LayoutSpec specWithFontSize(double fontSize) {
    return ReaderV2LayoutSpec.fromViewport(
      viewportSize: const Size(220, 180),
      style: ReaderV2LayoutStyle(
        fontSize: fontSize,
        lineHeight: 1.5,
        letterSpacing: 0,
        paragraphSpacing: 0.8,
        paddingTop: 12,
        paddingBottom: 12,
        paddingLeft: 12,
        paddingRight: 12,
        textIndent: 2,
      ),
    );
  }

  BookChapter chapter(int index) => BookChapter(
    url: 'chapter_$index',
    title: '第 $index 章',
    bookUrl: 'http://book.test',
    index: index,
    content: '第 $index 章內容。',
  );

  ReaderV2Runtime makeRuntime(
    List<BookChapter> chapters, {
    ReaderV2TestContentLoader? contentLoader,
  }) {
    final book = Book(
      bookUrl: 'http://book.test',
      name: '測試書',
      author: '作者',
      origin: 'local',
      originName: '本地',
    );
    final bookDao = _FakeBookDao();
    final repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: chapters,
      contentLoader: contentLoader,
      bookDao: bookDao,
      chapterDao: _FakeChapterDao(),
      sourceDao: _FakeSourceDao(),
    );
    return ReaderV2Runtime(
      book: book,
      repository: repository,
      progressController: ReaderV2ProgressController(
        book: book,
        repository: repository,
        bookDao: bookDao,
      ),
      initialLayoutSpec: specWithFontSize(18),
      initialLocation: const ReaderV2Location(chapterIndex: 0, charOffset: 0),
    );
  }

  test('latest operation owns the semantic target', () async {
    final content = Completer<String?>();
    final chapters = List.generate(4, chapter);
    final runtime = makeRuntime(
      chapters,
      contentLoader: (index, chapter) =>
          index == 3 ? content.future : Future.value(chapter.content),
    );
    addTearDown(runtime.dispose);
    final restores = <ReaderV2Location>[];
    runtime.registerViewportRestore(Object(), (location) async {
      restores.add(location);
      return true;
    });
    await runtime.openBook();

    const target = ReaderV2Location(chapterIndex: 3, charOffset: 4);
    final jump = runtime.jumpToLocation(target);
    final presentation = runtime.applyPresentation(spec: specWithFontSize(22));

    expect(runtime.pendingLocation, target);
    expect(runtime.state.hasStableWorld, isTrue);
    content.complete(chapters[3].content);
    await Future.wait([jump, presentation]);

    expect(runtime.state.lifecycle, ReaderV2Lifecycle.ready);
    expect(runtime.state.visibleLocation, target);
    expect(runtime.state.layoutSpec.layoutSignature, specWithFontSize(22).layoutSignature);
    expect(restores.last, target);
    expect(runtime.pendingLocation, isNull);
  });

  test('target content unavailable leaves the existing Reader world intact', () async {
    final runtime = makeRuntime(
      [chapter(0), chapter(1)],
      contentLoader: (index, chapter) async {
        if (index == 1) {
          throw ReaderV2ContentUnavailableException('目標章節暫時無法取得');
        }
        return chapter.content;
      },
    );
    addTearDown(runtime.dispose);
    final owner = Object();
    runtime.registerViewportRestore(owner, (_) async => true);
    await runtime.openBook();
    final before = runtime.state.visibleLocation;
    final generation = runtime.state.layoutGeneration;

    await runtime.jumpToChapter(1);

    expect(runtime.state.lifecycle, ReaderV2Lifecycle.ready);
    expect(runtime.state.hasStableWorld, isTrue);
    expect(runtime.state.visibleLocation, before);
    expect(runtime.state.layoutGeneration, generation);
    expect(runtime.pendingLocation, isNull);
    expect(runtime.takeUserNotice(), '目標章節暫時無法取得');
  });

  test('failed content reload rolls back to the committed content identity', () async {
    var failRefresh = false;
    final runtime = makeRuntime(
      [chapter(0)],
      contentLoader: (_, chapter) async {
        if (failRefresh) {
          throw ReaderV2ContentUnavailableException('重新載入正文失敗');
        }
        return chapter.content;
      },
    );
    addTearDown(runtime.dispose);
    runtime.registerViewportRestore(Object(), (_) async => true);
    await runtime.openBook();

    final before = runtime.repository.cachedContent(0);
    final generationBefore = runtime.repository.contentGeneration;
    expect(before, isNotNull);
    failRefresh = true;

    await runtime.reloadContentPreservingLocation();

    expect(runtime.state.lifecycle, ReaderV2Lifecycle.ready);
    expect(runtime.state.hasStableWorld, isTrue);
    expect(runtime.repository.cachedContent(0), same(before));
    expect(runtime.repository.contentGeneration, greaterThan(generationBefore));
    expect(runtime.takeUserNotice(), '重新載入正文失敗');
  });

  test('unknown content failure is exposed without replacing the stable world', () async {
    final runtime = makeRuntime(
      [chapter(0), chapter(1)],
      contentLoader: (index, chapter) async {
        if (index == 1) throw StateError('layout/content invariant broke');
        return chapter.content;
      },
    );
    addTearDown(runtime.dispose);
    runtime.registerViewportRestore(Object(), (_) async => true);
    await runtime.openBook();
    final before = runtime.state.visibleLocation;

    await expectLater(
      runtime.jumpToChapter(1),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'layout/content invariant broke',
        ),
      ),
    );

    expect(runtime.state.lifecycle, ReaderV2Lifecycle.ready);
    expect(runtime.state.hasStableWorld, isTrue);
    expect(runtime.state.visibleLocation, before);
    expect(runtime.pendingLocation, isNull);
    expect(runtime.takeUserNotice(), isNull);
  });

  test('first readable world unavailable marks the Reader unavailable', () async {
    final runtime = makeRuntime(
      [chapter(0)],
      contentLoader: (_, __) async {
        throw ReaderV2ContentUnavailableException('正文暫時無法取得');
      },
    );
    addTearDown(runtime.dispose);
    runtime.registerViewportRestore(Object(), (_) async => true);

    await runtime.openBook();

    expect(runtime.state.lifecycle, ReaderV2Lifecycle.unavailable);
    expect(runtime.state.hasStableWorld, isFalse);
    expect(runtime.pendingLocation, isNull);
    expect(runtime.state.unavailableMessage, contains('正文暫時無法取得'));
    expect(runtime.takeUserNotice(), isNull);
  });

  test('internal viewport ownership violation is exposed as a bug', () async {
    final runtime = makeRuntime([chapter(0), chapter(1)]);
    addTearDown(runtime.dispose);
    final owner = Object();
    runtime.registerViewportRestore(owner, (_) async => true);
    await runtime.openBook();
    runtime.unregisterViewportRestore(owner);

    await expectLater(runtime.jumpToChapter(1), throwsStateError);

    expect(runtime.state.lifecycle, ReaderV2Lifecycle.ready);
    expect(runtime.state.hasStableWorld, isTrue);
    expect(runtime.pendingLocation, isNull);
  });

  test('detaching the active viewport owner cancels its current operation', () async {
    final runtime = makeRuntime([chapter(0), chapter(1)]);
    addTearDown(runtime.dispose);
    final owner = Object();
    runtime.registerViewportRestore(owner, (_) async => true);
    await runtime.openBook();

    final operation = runtime.beginJumpOperation(
      location: const ReaderV2Location(chapterIndex: 1, charOffset: 0),
    );
    expect(runtime.stateMachine.currentOperation, same(operation));
    expect(runtime.state.hasStableWorld, isTrue);

    runtime.unregisterViewportRestore(owner);

    expect(runtime.stateMachine.currentOperation, isNull);
    expect(runtime.state.lifecycle, ReaderV2Lifecycle.ready);
    expect(runtime.state.hasStableWorld, isTrue);
  });

  test('detaching a stale viewport owner does not cancel the active operation', () async {
    final runtime = makeRuntime([chapter(0), chapter(1)]);
    addTearDown(runtime.dispose);
    final staleOwner = Object();
    final activeOwner = Object();
    runtime.registerViewportRestore(staleOwner, (_) async => true);
    runtime.registerViewportRestore(activeOwner, (_) async => true);
    await runtime.openBook();

    final operation = runtime.beginJumpOperation(
      location: const ReaderV2Location(chapterIndex: 1, charOffset: 0),
    );
    runtime.unregisterViewportRestore(staleOwner);

    expect(runtime.stateMachine.currentOperation, same(operation));
    expect(runtime.state.hasStableWorld, isTrue);
  });

  test('disposing runtime expires an awaiting viewport operation', () async {
    final runtime = makeRuntime([chapter(0)]);
    final entered = Completer<void>();
    final restore = Completer<bool>();
    runtime.registerViewportRestore(Object(), (_) {
      entered.complete();
      return restore.future;
    });

    final opening = runtime.openBook();
    await entered.future;
    runtime.dispose();
    restore.complete(true);
    await opening;

    expect(runtime.state.hasStableWorld, isFalse);
  });

  test('presentation and reload converge through the same viewport owner', () async {
    final runtime = makeRuntime(List.generate(3, chapter));
    addTearDown(runtime.dispose);
    final restores = <ReaderV2Location>[];
    runtime.registerViewportRestore(Object(), (location) async {
      restores.add(location);
      return true;
    });

    await runtime.openBook();
    await runtime.jumpToChapter(1);
    await runtime.applyPresentation(spec: specWithFontSize(22));
    await runtime.reloadContentPreservingLocation();

    expect(runtime.state.lifecycle, ReaderV2Lifecycle.ready);
    expect(runtime.state.visibleLocation.chapterIndex, 1);
    expect(runtime.pendingLocation, isNull);
    expect(restores, isNotEmpty);
  });
}
