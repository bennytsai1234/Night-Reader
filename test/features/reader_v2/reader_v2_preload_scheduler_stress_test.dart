import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_engine.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_chapter_view.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_preload_scheduler.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_resolver.dart';

class _FakeBookDao extends Fake implements BookDao {}

class _FakeChapterDao extends Fake implements ChapterDao {}

class _FakeSourceDao extends Fake implements BookSourceDao {}

/// 記錄背景排版步進的併發度，驗證排程器的併發上限沒有失守。
class _CountingResolver extends ReaderV2Resolver {
  _CountingResolver({
    required super.repository,
    required super.layoutEngine,
    required super.layoutSpec,
  });

  int _active = 0;
  int maxActive = 0;

  @override
  Future<ReaderV2ChapterView> continueLayoutStep(int chapterIndex) async {
    _active += 1;
    maxActive = math.max(maxActive, _active);
    try {
      return await super.continueLayoutStep(chapterIndex);
    } finally {
      _active -= 1;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ReaderV2LayoutSpec spec() {
    return ReaderV2LayoutSpec.fromViewport(
      viewportSize: const Size(220, 180),
      style: const ReaderV2LayoutStyle(
        fontSize: 18,
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

  BookChapter chapter(int index, {int paragraphCount = 12}) {
    final body = List<String>.filled(
      paragraphCount,
      '這是一段用於壓力測試的中文內容，帶有標點符號與足夠的長度，讓排版需要多個步進才能完成。',
    ).join('\n\n');
    return BookChapter(
      url: 'chapter_$index',
      title: '第 $index 章',
      bookUrl: 'http://book.test',
      index: index,
      content: body,
    );
  }

  ReaderV2ChapterRepository makeRepository(List<BookChapter> chapters) {
    final book = Book(
      bookUrl: 'http://book.test',
      name: '測試書',
      author: '作者',
      origin: 'local',
      originName: '本地',
    );
    return ReaderV2ChapterRepository(
      book: book,
      initialChapters: chapters,
      bookDao: _FakeBookDao(),
      chapterDao: _FakeChapterDao(),
      sourceDao: _FakeSourceDao(),
    );
  }

  ReaderV2Resolver makeResolver(List<BookChapter> chapters) {
    return ReaderV2Resolver(
      repository: makeRepository(chapters),
      layoutEngine: ReaderV2LayoutEngine(),
      layoutSpec: spec(),
    );
  }

  group('ReaderV2PreloadScheduler 壓力測試', () {
    test('排隊中的任務被 open/jump 丟棄後，等待它的 Future 仍必須完成', () async {
      final resolver = makeResolver([
        for (var i = 0; i < 6; i++) chapter(i, paragraphCount: 40),
      ]);
      final scheduler = ReaderV2PreloadScheduler(resolver: resolver);
      addTearDown(scheduler.dispose);

      // 佔住唯一的背景排版併發位，讓後續任務停留在佇列中。
      final active = scheduler.scheduleLayout(0);
      final queued = scheduler.scheduleLayout(4);
      // scheduleOpen 走 replaceQueued: true，會把還在佇列中的章節 4 丟棄。
      final open = scheduler.scheduleOpen(1);

      // 修復前：章節 4 的 waiter 永遠 pending，這裡會 timeout。
      await queued.timeout(
        const Duration(seconds: 30),
        onTimeout: () => fail('被丟棄的排隊任務沒有完成它的 waiter（B1 回歸）'),
      );
      await open;
      await active;
    });

    test('隨機交錯 open/jump/directional/bumpGeneration，所有 Future 都要完成', () async {
      final resolver = makeResolver([
        for (var i = 0; i < 8; i++) chapter(i, paragraphCount: 8),
      ]);
      final scheduler = ReaderV2PreloadScheduler(resolver: resolver);
      addTearDown(scheduler.dispose);

      final random = math.Random(20260702);
      final futures = <Future<void>>[];
      for (var step = 0; step < 60; step++) {
        final chapterIndex = random.nextInt(8);
        switch (random.nextInt(5)) {
          case 0:
            futures.add(scheduler.scheduleOpen(chapterIndex));
          case 1:
            futures.add(scheduler.scheduleJump(chapterIndex));
          case 2:
            futures.add(
              scheduler.scheduleDirectional(
                fromChapterIndex: chapterIndex,
                forward: random.nextBool(),
                chapterSpan: 1 + random.nextInt(3),
              ),
            );
          case 3:
            futures.add(scheduler.scheduleLayout(chapterIndex));
          case 4:
            scheduler.bumpGeneration();
        }
        if (step % 7 == 0) {
          // 穿插事件迴圈讓背景任務有機會推進，模擬真實互動節奏。
          await Future<void>.delayed(Duration.zero);
        }
      }

      await Future.wait(futures).timeout(
        const Duration(seconds: 60),
        onTimeout: () => fail('交錯排程後仍有 Future 未完成（waiter 洩漏）'),
      );
    });

    test('bumpGeneration 轟炸下背景排版併發度不得超過上限', () async {
      final repository = makeRepository([
        for (var i = 0; i < 4; i++) chapter(i, paragraphCount: 30),
      ]);
      final resolver = _CountingResolver(
        repository: repository,
        layoutEngine: ReaderV2LayoutEngine(),
        layoutSpec: spec(),
      );
      final scheduler = ReaderV2PreloadScheduler(resolver: resolver);
      addTearDown(scheduler.dispose);

      final futures = <Future<void>>[];
      for (var round = 0; round < 10; round++) {
        futures.add(scheduler.scheduleLayout(round % 4));
        scheduler.bumpGeneration();
        futures.add(scheduler.scheduleLayout((round + 1) % 4));
        await Future<void>.delayed(Duration.zero);
      }
      await Future.wait(
        futures,
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () => fail('generation 交錯後仍有 Future 未完成（waiter 洩漏）'),
      );

      expect(
        resolver.maxActive,
        lessThanOrEqualTo(1),
        reason: 'bumpGeneration 不得讓新舊 generation 的排版任務同時執行（B2 回歸）',
      );
    });
  });
}
