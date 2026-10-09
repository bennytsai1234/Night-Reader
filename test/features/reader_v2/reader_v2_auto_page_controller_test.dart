import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/features/auto_page/reader_v2_auto_page_controller.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';

class _FakeBookDao extends Fake implements BookDao {}

class _FakeChapterDao extends Fake implements ChapterDao {}

class _FakeSourceDao extends Fake implements BookSourceDao {}

class _FakeTimer implements Timer {
  _FakeTimer(this.onTick);

  final void Function(Timer timer) onTick;
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

void main() {
  late ReaderV2Runtime runtime;
  late ReaderV2ViewportController viewport;
  late ReaderV2AutoPageController autoPage;
  late List<_FakeTimer> timers;

  setUp(() {
    final book = Book(
      bookUrl: 'http://auto-page.test',
      name: '自動捲動測試書',
      author: '作者',
      origin: 'local',
      originName: '本地',
    );
    final bookDao = _FakeBookDao();
    final repository = ReaderV2ChapterRepository(
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
    runtime = ReaderV2Runtime(
      book: book,
      repository: repository,
      progressController: ReaderV2ProgressController(
        book: book,
        repository: repository,
        bookDao: bookDao,
      ),
      initialLayoutSpec: ReaderV2LayoutSpec.fromViewport(
        viewportSize: const Size(400, 600),
        style: const ReaderV2LayoutStyle(
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
      initialLocation: const ReaderV2Location(chapterIndex: 0, charOffset: 0),
    );
    viewport = ReaderV2ViewportController()..settleScroll = () async {};
    timers = <_FakeTimer>[];
    autoPage = ReaderV2AutoPageController(
      runtime: runtime,
      viewportController: viewport,
      viewportExtent: () => 600,
      timerFactory: (_, onTick) {
        final timer = _FakeTimer(onTick);
        timers.add(timer);
        return timer;
      },
    );
  });

  tearDown(() {
    autoPage.dispose();
    runtime.dispose();
  });

  void tick() => timers.last.onTick(timers.last);

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
}
