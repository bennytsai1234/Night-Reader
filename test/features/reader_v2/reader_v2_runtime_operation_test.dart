import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_controller_host.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_operation_token.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  ReaderV2LayoutSpec specWithFontSize(
    double fontSize, {
    Size viewportSize = const Size(220, 180),
  }) {
    return ReaderV2LayoutSpec.fromViewport(
      viewportSize: viewportSize,
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
    ReaderV2LayoutSpec? initialLayoutSpec,
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
      initialLayoutSpec: initialLayoutSpec ?? specWithFontSize(18),
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

  test('progress flush can catch persistence up without notifying Reader UI', () async {
    final runtime = makeRuntime([chapter(0)]);
    addTearDown(runtime.dispose);
    runtime.registerViewportRestore(Object(), (_) async => true);
    await runtime.openBook();

    const captured = ReaderV2Location(
      chapterIndex: 0,
      charOffset: 2,
      visualOffsetPx: 12,
    );
    runtime.registerVisibleLocationCapture(Object(), () => captured);
    var notifications = 0;
    runtime.addListener(() => notifications += 1);

    await runtime.flushProgress();

    expect(runtime.state.visibleLocation, captured);
    expect(runtime.state.committedLocation, captured);
    expect(notifications, 0);
  });

  test('viewport height updates only the viewport listener', () async {
    final runtime = makeRuntime([chapter(0)]);
    addTearDown(runtime.dispose);
    var restores = 0;
    runtime.registerViewportRestore(Object(), (_) async {
      restores += 1;
      return true;
    });
    await runtime.openBook();

    var semanticNotifications = 0;
    var viewportNotifications = 0;
    runtime.addListener(() => semanticNotifications += 1);
    runtime.addViewportGeometryListener(() => viewportNotifications += 1);

    final generation = runtime.state.layoutGeneration;
    final restoresBeforeResize = restores;
    final resized = specWithFontSize(
      18,
      viewportSize: const Size(220, 160),
    );
    expect(
      resized.layoutSignature,
      runtime.state.layoutSpec.layoutSignature,
    );

    await runtime.applyPresentation(spec: resized);

    expect(runtime.state.layoutGeneration, generation);
    expect(runtime.state.layoutSpec.viewportSize.height, 160);
    expect(
      runtime.state.layoutSpec.presentationSignature,
      resized.presentationSignature,
    );
    expect(restores, restoresBeforeResize);
    expect(semanticNotifications, 0);
    expect(viewportNotifications, 1);
  });

  test('viewport change does not replace an in-flight jump operation', () async {
    final runtime = makeRuntime(List.generate(4, chapter));
    addTearDown(runtime.dispose);
    var restores = 0;
    runtime.registerViewportRestore(Object(), (_) async {
      restores += 1;
      return true;
    });
    await runtime.openBook();

    final staged = specWithFontSize(22);
    runtime.stateMachine.beginPresentation(
      spec: staged,
      layoutGeneration: runtime.state.layoutGeneration + 1,
    );
    const target = ReaderV2Location(chapterIndex: 3, charOffset: 4);
    final jump = runtime.beginJumpOperation(location: target);
    final restoresBeforeResize = restores;
    final resized = specWithFontSize(
      22,
      viewportSize: const Size(220, 160),
    );

    await runtime.applyPresentation(spec: resized);

    expect(runtime.stateMachine.currentOperation, same(jump));
    expect(runtime.stateMachine.currentOperation!.kind, ReaderV2OperationKind.jump);
    expect(runtime.pendingLocation, target);
    expect(
      runtime.stateMachine.stagedLayoutSpec!.presentationSignature,
      resized.presentationSignature,
    );
    expect(restores, restoresBeforeResize);
  });

  test(
    'content generation change re-resolves the same active operation token',
    () async {
      final chapters = List<BookChapter>.generate(21, chapter);
      final raw = <int, String>{
        for (var index = 0; index < chapters.length; index++)
          index: chapters[index].content ?? '',
      };
      final runtime = makeRuntime(
        chapters,
        contentLoader: (index, __) async => raw[index],
      );
      addTearDown(runtime.dispose);

      var simulateGenerationChange = false;
      var restoreAttempts = 0;
      final operationIds = <int>[];
      runtime.registerViewportRestore(Object(), (_) async {
        if (!simulateGenerationChange) return true;
        restoreAttempts += 1;
        operationIds.add(runtime.stateMachine.currentOperation!.id);
        if (restoreAttempts == 1) {
          await runtime.loadContentAt(0);
          return false;
        }
        return true;
      });

      await runtime.openBook();
      for (var index = 1; index < chapters.length; index += 1) {
        await runtime.loadContentAt(index);
      }
      expect(runtime.repository.cachedContent(0), isNull);
      final contentBefore = runtime.state.contentGeneration;

      raw[0] = '第一章由外部持久層更新';
      simulateGenerationChange = true;
      await runtime.jumpToChapter(1);

      expect(runtime.state.contentGeneration, contentBefore + 1);
      expect(runtime.state.visibleLocation.chapterIndex, 1);
      expect(restoreAttempts, 2);
      expect(operationIds.toSet(), hasLength(1));
      expect(runtime.pendingLocation, isNull);
    },
  );

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

  test(
    'content reload publishes semantic generation without changing layout generation',
    () async {
      var raw = '第一版正文。';
      final runtime = makeRuntime(
        [chapter(0)],
        contentLoader: (_, __) async => raw,
      );
      addTearDown(runtime.dispose);
      runtime.registerViewportRestore(Object(), (_) async => true);
      await runtime.openBook();

      final layoutBefore = runtime.state.layoutGeneration;
      final contentBefore = runtime.state.contentGeneration;
      raw = '第二版正文，內容已改變。';

      expect(await runtime.reloadContentPreservingLocation(), isTrue);

      expect(runtime.state.layoutGeneration, layoutBefore);
      expect(runtime.state.contentGeneration, contentBefore + 1);
      expect(
        runtime.state.contentGeneration,
        runtime.repository.contentGeneration,
      );
      expect(runtime.state.hasStableWorld, isTrue);
    },
  );

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
    final publishedBefore = runtime.state.contentGeneration;
    final layoutBefore = runtime.state.layoutGeneration;
    expect(before, isNotNull);
    failRefresh = true;

    expect(await runtime.reloadContentPreservingLocation(), isFalse);

    expect(runtime.state.lifecycle, ReaderV2Lifecycle.ready);
    expect(runtime.state.hasStableWorld, isTrue);
    expect(runtime.repository.cachedContent(0), same(before));
    expect(runtime.repository.contentGeneration, generationBefore);
    expect(runtime.state.contentGeneration, publishedBefore);
    expect(runtime.state.contentGeneration, runtime.repository.contentGeneration);
    expect(runtime.state.layoutGeneration, layoutBefore);
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

  test(
    'overlapping reload failure cannot hide a later semantic identity change',
    () async {
      var loadCount = 0;
      final firstReload = Completer<String?>();
      final secondReload = Completer<String?>();
      final runtime = makeRuntime(
        [chapter(0)],
        contentLoader: (_, __) {
          loadCount += 1;
          switch (loadCount) {
            case 1:
              return Future<String?>.value('第一版正文。');
            case 2:
              return firstReload.future;
            case 3:
              return secondReload.future;
            default:
              return Future<String?>.value('第三版正文。');
          }
        },
      );
      addTearDown(runtime.dispose);
      final repository = runtime.repository;

      final committed = await repository.loadContent(0);
      final generationBefore = repository.contentGeneration;

      final refresh1 = repository.reloadContent(0);
      await pumpEventQueue();
      expect(loadCount, 2);

      final refresh2 = repository.reloadContent(0);
      await pumpEventQueue();
      expect(
        loadCount,
        2,
        reason: '第二個 destructive reload 必須等第一個 transaction 結束。',
      );

      firstReload.complete('第二版正文。');
      final firstCommitted = await refresh1;
      await pumpEventQueue();
      expect(loadCount, 3);

      secondReload.completeError(
        const ReaderV2ContentUnavailableException('第二次重新載入失敗'),
      );
      await expectLater(
        refresh2,
        throwsA(isA<ReaderV2ContentUnavailableException>()),
      );

      final afterFailure = repository.cachedContent(0);
      expect(afterFailure?.contentHash, firstCommitted.contentHash);
      expect(firstCommitted.contentHash, isNot(committed.contentHash));
      expect(
        repository.contentGeneration,
        greaterThan(generationBefore),
        reason:
            '後繼 reload 失敗時必須保留前一個已提交 semantic identity；'
            'transaction 不得 rollback 到另一個 reload 的半成品快照。',
      );
    },
  );

  testWidgets(
    'host reconciles desired presentation after an in-flight request is abandoned',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final getIt = GetIt.instance;
      await getIt.reset();
      getIt.registerSingleton<BookDao>(_FakeBookDao());
      getIt.registerSingleton<ChapterDao>(_FakeChapterDao());
      getIt.registerSingleton<BookSourceDao>(_FakeSourceDao());

      final book = Book(
        bookUrl: 'http://host.test',
        name: 'Host 測試書',
        author: '作者',
        origin: 'local',
        originName: '本地',
      );
      final host = ReaderV2ControllerHost(
        book: book,
        initialChapters: [chapter(0), chapter(1)],
        openTarget: null,
        onChanged: () {},
        onProgressPersisted: () {},
        isMounted: () => true,
      );
      addTearDown(() async {
        host.dispose();
        await getIt.reset();
      });

      const size = Size(220, 180);
      const initialStyle = ReaderV2Style(
        fontSize: 18,
        lineHeight: 1.5,
        letterSpacing: 0,
        paragraphSpacing: 0.8,
        paddingTop: 12,
        paddingBottom: 12,
        paddingLeft: 12,
        paddingRight: 12,
        textIndent: 2,
      );
      final desiredStyle = initialStyle.copyWith(fontSize: 22);
      final initialSpec = host.specFromStyle(size, initialStyle);
      final desiredSignature = host
          .specFromStyle(size, desiredStyle)
          .presentationSignature;
      final targetContent = Completer<String?>();
      final runtime = makeRuntime(
        [chapter(0), chapter(1)],
        initialLayoutSpec: initialSpec,
        contentLoader: (index, chapter) =>
            index == 1 ? targetContent.future : Future.value(chapter.content),
      );
      addTearDown(runtime.dispose);

      final initialSignature = runtime.state.layoutSpec.presentationSignature;
      expect(desiredSignature, isNot(initialSignature));

      runtime.registerViewportRestore(Object(), (_) async => true);
      await runtime.openBook();
      expect(runtime.state.hasStableWorld, isTrue);

      // Prime Host bookkeeping with the presentation already committed.
      host.syncRuntimeConfiguration(runtime, size, initialStyle);
      await tester.pump();
      await tester.pump();

      final jump = runtime.jumpToChapter(1);
      expect(
        runtime.stateMachine.currentOperation?.kind,
        ReaderV2OperationKind.jump,
      );

      host.syncRuntimeConfiguration(runtime, size, desiredStyle);
      for (
        var frame = 0;
        frame < 6 &&
            runtime.stateMachine.currentOperation?.kind !=
                ReaderV2OperationKind.presentation;
        frame++
      ) {
        await tester.pump();
      }

      expect(
        runtime.stateMachine.currentOperation?.kind,
        ReaderV2OperationKind.presentation,
        reason: 'presentation 必須接手 jump 的 pending target 才算有效重現。',
      );
      expect(runtime.pendingLocation?.chapterIndex, 1);
      expect(
        runtime.stateMachine.stagedLayoutSpec?.presentationSignature,
        desiredSignature,
      );
      expect(runtime.state.layoutSpec.presentationSignature, initialSignature);

      targetContent.completeError(
        const ReaderV2ContentUnavailableException('目標章節暫時無法取得'),
      );
      await jump;
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
      }

      expect(runtime.stateMachine.currentOperation, isNull);
      expect(runtime.stateMachine.stagedLayoutSpec, isNull);
      expect(runtime.state.layoutSpec.presentationSignature, initialSignature);
      expect(runtime.takeUserNotice(), '目標章節暫時無法取得');

      host.syncRuntimeConfiguration(runtime, size, desiredStyle);
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
      }

      expect(
        runtime.state.layoutSpec.presentationSignature,
        desiredSignature,
        reason:
            'presentation 在 commit 前因 inherited target 載入失敗時，'
            'Host 仍必須知道 desired presentation 尚未提交。',
      );
    },
  );

  testWidgets(
    'host retries unapplied content settings after the Reader world changes',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final getIt = GetIt.instance;
      await getIt.reset();
      getIt.registerSingleton<BookDao>(_FakeBookDao());
      getIt.registerSingleton<ChapterDao>(_FakeChapterDao());
      getIt.registerSingleton<BookSourceDao>(_FakeSourceDao());

      final book = Book(
        bookUrl: 'http://content-settings.test',
        name: '正文設定測試書',
        author: '作者',
        origin: 'local',
        originName: '本地',
      );
      final host = ReaderV2ControllerHost(
        book: book,
        initialChapters: [chapter(0), chapter(1)],
        openTarget: null,
        onChanged: () {},
        onProgressPersisted: () {},
        isMounted: () => true,
      );
      addTearDown(() async {
        host.dispose();
        await getIt.reset();
      });

      await host.settings.loadSettings();

      const size = Size(220, 180);
      const style = ReaderV2Style(
        fontSize: 18,
        lineHeight: 1.5,
        letterSpacing: 0,
        paragraphSpacing: 0.8,
        paddingTop: 12,
        paddingBottom: 12,
        paddingLeft: 12,
        paddingRight: 12,
        textIndent: 2,
      );
      final initialSpec = host.specFromStyle(size, style);

      final loads = <int, int>{};
      var failNextReload = false;
      final runtime = makeRuntime(
        [chapter(0), chapter(1)],
        initialLayoutSpec: initialSpec,
        contentLoader: (index, chapter) async {
          loads[index] = (loads[index] ?? 0) + 1;
          if (failNextReload) {
            failNextReload = false;
            throw const ReaderV2ContentUnavailableException(
              '正文設定重新載入失敗',
            );
          }
          return chapter.content;
        },
      );
      addTearDown(runtime.dispose);
      runtime.registerViewportRestore(Object(), (_) async => true);
      await runtime.openBook();

      Widget buildHarness() {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (_) {
              host.syncRuntimeConfiguration(runtime, size, style);
              return const SizedBox.expand();
            },
          ),
        );
      }

      await tester.pumpWidget(buildHarness());
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump();
        if (runtime.stateMachine.currentOperation == null) break;
      }
      final chapter0Baseline = loads[0] ?? 0;
      final generationBefore = host.settings.contentSettingsGeneration;

      final nextChineseConvert = host.settings.chineseConvert == 1 ? 0 : 1;
      host.settings.setChineseConvert(nextChineseConvert);
      expect(
        host.settings.contentSettingsGeneration,
        greaterThan(generationBefore),
      );

      failNextReload = true;
      await tester.pumpWidget(buildHarness());
      for (var frame = 0;
          frame < 12 &&
              ((loads[0] ?? 0) < chapter0Baseline + 1 ||
                  runtime.stateMachine.currentOperation != null);
          frame++) {
        await tester.pump();
      }

      expect(loads[0], chapter0Baseline + 1);
      expect(runtime.stateMachine.currentOperation, isNull);
      expect(runtime.takeUserNotice(), '正文設定重新載入失敗');

      // Failure must not create a rebuild/retry loop in the same Reader world.
      await tester.pumpWidget(buildHarness());
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
      }
      expect(loads[0], chapter0Baseline + 1);

      // The desired setting is still unapplied. Moving to a different Reader
      // world must make it eligible for reconciliation again.
      await runtime.jumpToChapter(1);
      expect(loads[1], 1);

      await tester.pumpWidget(buildHarness());
      for (var frame = 0;
          frame < 12 &&
              ((loads[1] ?? 0) < 2 ||
                  runtime.stateMachine.currentOperation != null);
          frame++) {
        await tester.pump();
      }

      expect(
        loads[1],
        2,
        reason:
            '失敗的正文設定 request 不能被永久視為 applied；'
            'Reader world 改變後必須能重新收斂。',
      );

      // Once the same desired generation was applied successfully, rebuilds
      // must stay quiet.
      await tester.pumpWidget(buildHarness());
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
      }
      expect(loads[1], 2);
    },
  );
}
