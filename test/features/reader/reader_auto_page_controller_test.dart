import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/features/reader/chapter/reader_chapter_repository.dart';
import 'package:night_reader/features/reader/features/auto_page/reader_auto_page_controller.dart';
import 'package:night_reader/features/reader/features/settings/reader_prefs_repository.dart';
import 'package:night_reader/features/reader/layout/reader_layout_spec.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';
import 'package:night_reader/features/reader/session/reader_operation_token.dart';
import 'package:night_reader/features/reader/session/reader_progress_controller.dart';
import 'package:night_reader/features/reader/session/reader_runtime.dart';
import 'package:night_reader/features/reader/viewport/reader_viewport_controller.dart';

class _FakeBookDao extends Fake implements BookDao {
  @override
  Future<int?> updateProgress(
    String bookUrl,
    int chapterIndex,
    String chapterTitle,
    int pos, {
    double visualOffsetPx = 0.0,
    String? readerAnchorJson,
  }) async => null;
}

class _FakeChapterDao extends Fake implements ChapterDao {
  @override
  Future<int?> indexOfUrl(String bookUrl, String url) async => null;

  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) => action();
}

class _FakeSourceDao extends Fake implements BookSourceDao {}

void main() {
  late ReaderRuntime runtime;
  late ReaderViewportController viewport;
  late ReaderAutoPageController autoPage;
  ReaderFrameCallback? onFrame;
  var elapsed = Duration.zero;
  var primed = false;

  setUp(() {
    final book = Book(
      bookUrl: 'http://auto-page.test',
      name: '自動捲動測試書',
      author: '作者',
      origin: 'local',
      originName: '本地',
    );
    final bookDao = _FakeBookDao();
    final repository = ReaderChapterRepository(
      book: book,
      initialChapters: [
        BookChapter(
          url: 'chapter_0',
          title: '第 0 章',
          bookUrl: book.bookUrl,
          index: 0,
          content: '內容。',
        ),
      ],
      bookDao: bookDao,
      chapterDao: _FakeChapterDao(),
      sourceDao: _FakeSourceDao(),
    );
    runtime = ReaderRuntime(
      book: book,
      repository: repository,
      progressController: ReaderProgressController(
        book: book,
        repository: repository,
        bookDao: bookDao,
      ),
      initialLayoutSpec: ReaderLayoutSpec.fromViewport(
        viewportSize: const Size(400, 600),
        style: const ReaderLayoutStyle(
          fontSize: 18,
          lineHeight: 1.5,
          letterSpacing: 0,
          paragraphSpacing: 0.8,
          paddingTop: 12,
          paddingBottom: 12,
          paddingLeft: 12,
          paddingRight: 12,
        ),
      ),
      initialLocation: const ReaderLocation(chapterIndex: 0, charOffset: 0),
    );
    viewport = ReaderViewportController()..settleScroll = () async {};
    onFrame = null;
    elapsed = Duration.zero;
    autoPage = ReaderAutoPageController(
      runtime: runtime,
      viewportController: viewport,
      viewportExtent: () => 600,
      frameSource: (callback) {
        onFrame = callback;
        primed = false;
        return () {
          if (identical(onFrame, callback)) onFrame = null;
        };
      },
    );
  });

  tearDown(() {
    autoPage.dispose();
    runtime.dispose();
  });

  /// 推進一幀（120Hz）；幀來源剛開始時先送一幀建立時鐘。
  void tick() {
    final callback = onFrame;
    if (callback == null) return;
    if (!primed) {
      primed = true;
      callback(elapsed);
    }
    elapsed += const Duration(microseconds: 8333);
    callback(elapsed);
  }

  test(
    'a step still waiting when auto-scroll stops cannot move later',
    () async {
      final pending = Completer<bool>();
      var fallbackMoves = 0;
      viewport
        ..continuousScrollBy = ((_) => pending.future)
        ..scrollBy = (_) async {
          fallbackMoves += 1;
          return true;
        }
        ..moveToNextPage = () async {
          fallbackMoves += 1;
          return true;
        };
      autoPage.start();
      tick();
      autoPage.stop();

      pending.complete(false);
      await pumpEventQueue();

      expect(fallbackMoves, 0);
      expect(autoPage.isRunning, isFalse);
    },
  );

  test('a step still waiting when the reader closes leaves it alone', () async {
    final pending = Completer<bool>();
    viewport
      ..continuousScrollBy = ((_) => pending.future)
      ..scrollBy = ((_) async => false)
      ..moveToNextPage = (() async => false);
    // 另開一個，拆掉它不影響 tearDown 拆共用的那個。
    final closing = ReaderAutoPageController(
      runtime: runtime,
      viewportController: viewport,
      viewportExtent: () => 600,
      frameSource: (callback) {
        onFrame = callback;
        primed = false;
        return () {
          if (identical(onFrame, callback)) onFrame = null;
        };
      },
    )..start();
    tick();
    closing.dispose();

    // 拆掉後那一步才做完：不能再回頭停下（通知）已經拆掉的控制器。
    pending.complete(false);
    await pumpEventQueue();

    expect(closing.isRunning, isFalse);
  });

  test('an old step cannot stop a run started after it', () async {
    final pending = Completer<bool>();
    viewport
      ..continuousScrollBy = ((_) => pending.future)
      ..scrollBy = ((_) async => false)
      ..moveToNextPage = (() async => false);
    autoPage.start();
    tick();
    autoPage
      ..stop()
      ..start();

    pending.complete(false);
    await pumpEventQueue();

    expect(autoPage.isRunning, isTrue);
  });

  test('pausing holds the position and resuming continues', () async {
    var moves = 0;
    viewport.continuousScrollBy = (_) async {
      moves += 1;
      return true;
    };
    autoPage
      ..start()
      ..setPaused(true);
    expect(onFrame, isNull, reason: '暫停時不要求新的幀');
    tick();
    await pumpEventQueue();
    expect(moves, 0);
    expect(autoPage.isRunning, isTrue);

    autoPage.setPaused(false);
    tick();
    await pumpEventQueue();
    expect(moves, 1);
  });

  test('a step interrupted by pausing does not end auto-scroll', () async {
    final pending = Completer<bool>();
    viewport
      ..continuousScrollBy = ((_) => pending.future)
      ..scrollBy = ((_) async => false)
      ..moveToNextPage = (() async => false);
    autoPage.start();
    tick();
    autoPage.setPaused(true);

    pending.complete(false);
    await pumpEventQueue();

    expect(autoPage.isRunning, isTrue);
  });

  test('a jump waiting for its text pauses steps without ending', () async {
    Completer<bool>? restoring;
    runtime.registerViewportRestore(
      Object(),
      (_) => restoring?.future ?? Future.value(true),
    );
    await runtime.openBook();
    var moves = 0;
    // 跟閱讀畫面一樣：跳章進行中時正文不給捲。
    viewport
      ..continuousScrollBy = (_) async {
        if (runtime.stateMachine.currentOperation != null) return false;
        moves += 1;
        return true;
      }
      ..scrollBy = ((_) async => false)
      ..moveToNextPage = (() async => false);

    restoring = Completer<bool>();
    final jump = runtime.jumpToLocation(
      const ReaderLocation(chapterIndex: 0, charOffset: 1),
    );
    await pumpEventQueue();
    expect(
      runtime.stateMachine.currentOperation?.kind,
      ReaderOperationKind.jump,
    );
    autoPage.start();
    tick();
    await pumpEventQueue();
    expect(moves, 0);
    expect(autoPage.isRunning, isTrue, reason: '跳章中不當成到了書尾');

    restoring.complete(true);
    await jump;
    tick();
    await pumpEventQueue();
    expect(moves, 1);
    expect(autoPage.isRunning, isTrue);
  });

  test('each display frame moves by the time that frame took', () async {
    final deltas = <double>[];
    viewport.continuousScrollBy = (delta) async {
      deltas.add(delta);
      return true;
    };
    autoPage.start();
    for (var frame = 0; frame < 3; frame++) {
      tick();
      await pumpEventQueue();
    }

    // 預設速度是每秒捲幾個視窗高：120Hz 每幀 600 × 速度 × 8.333ms。
    const speed = ReaderPrefsRepository.defaultAutoPageSpeed;
    expect(deltas, hasLength(3));
    for (final delta in deltas) {
      expect(delta, closeTo(600 * speed * 0.008333, 1e-6));
    }
  });

  test('stopping releases the frame source', () {
    autoPage.start();
    expect(onFrame, isNotNull);
    autoPage.stop();
    expect(onFrame, isNull);
  });
}
