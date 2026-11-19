import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_repair_backups.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/source_check/source_check_isolate.dart';
import 'package:night_reader/core/ai_repair/source_probe.dart';
import 'package:night_reader/core/ai_repair/source_repair_batch.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/background_work/background_work.dart';
import 'package:night_reader/core/background_work/paused_work_file.dart';
import 'package:night_reader/core/source_check/check_source_service.dart';
import 'package:night_reader/features/source_manager/ai_repair/repair_runs.dart';
import 'package:night_reader/features/source_manager/ai_repair/source_repair_page.dart';
import 'package:night_reader/features/source_manager/source_check_job.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

import '../../support/fake_ai.dart';

const _service = (
  baseUrl: 'https://ai.example/v1',
  apiKey: 'k',
  model: 'm',
  effort: '',
);

/// 換掉 Android 那一半，看通知實際收到什麼（只驗 Dart 這邊的協定）。
/// 存在記憶體裡的暫停存檔。
class _MemoryFile extends PausedWorkFile {
  _MemoryFile([this.text]) : super('check_sources');
  String? text;
  bool closed = false;

  @override
  bool get isClosed => closed;

  @override
  Future<String?> read() async => text;

  @override
  void saveLater(String Function() encode) {
    if (!closed) text = encode();
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    closed = true;
    text = null;
  }
}

class _FakePlatform implements BackgroundWorkPlatform {
  final List<String> calls = [];

  @override
  Future<bool> show(BackgroundWorkStatus status) async {
    calls.add('${status.text}｜${status.permille}');
    return true;
  }

  @override
  Future<void> hide() async => calls.add('hide');

  @override
  set onAction(void Function(String action)? handler) {}
}

BookSource _s(String name) =>
    BookSource(bookSourceUrl: 'https://$name.example', bookSourceName: name);

/// 重新校驗等 [gate]：給了就停在第一段，沒給就馬上全部沒問題、整批做完。
SourceRepairBatch _batch({Completer<void>? gate, int count = 2}) =>
    SourceRepairBatch(
      sources: [for (var i = 0; i < count; i++) _s('s$i')],
      service: _service,
      recheck: (urls, progress, _) async {
        if (gate != null) {
          progress(1);
          await gate.future;
        }
        return [
          for (final url in urls)
            SourceCheckEntry(
              sourceUrl: url,
              sourceName: url,
              stage: 'done',
              message: '校驗成功',
              health: SourceRuntimeHealth.healthy,
            ),
        ];
      },
    );

Future<void> _flush() => Future<void>.delayed(Duration.zero);

/// 頁上有轉圈時 pumpAndSettle 等不完，改成推進一段時間。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late _FakePlatform platform;
  late BackgroundWork work;
  late RepairRuns runs;

  setUp(() {
    platform = _FakePlatform();
    work = BackgroundWork(platform: platform);
    runs = RepairRuns();
  });

  BatchRepairRun runOf(SourceRepairBatch batch) => BatchRepairRun(
    batch,
    title: '修復異常書源',
    progress: _MemoryFile(),
    work: work,
    navigator: () => null,
  );

  test('each of the four stages is a quarter of the progress bar', () {
    final batch = _batch()
      ..stage = RepairStage.checking
      ..stageDone = 5
      ..stageTotal = 10;
    expect(repairBatchProgress(batch), 0.125);

    batch
      ..stage = RepairStage.repairing
      ..stageDone = 3
      ..stageTotal = 4;
    expect(repairBatchProgress(batch), (3 + 0.75) / 4);

    // 沒有搬家的網站：這一段一開始就沒有東西要做，不除以零。
    batch
      ..stage = RepairStage.moving
      ..stageDone = 0
      ..stageTotal = 0;
    expect(repairBatchProgress(batch), 0.5);

    batch.stage = RepairStage.done;
    expect(repairBatchProgress(batch), 1);
  });

  test('the notification says which stage and how far, in the same words '
      'as the page', () {
    final batch = _batch()
      ..stage = RepairStage.checking
      ..stageDone = 12
      ..stageTotal = 199;
    final run = runOf(batch);
    expect(run.status.title, '修復異常書源');
    expect(run.status.text, '重新校驗，第 12／199 個');
    expect(repairStageProgress(batch), '第 12／199 個');

    batch
      ..stage = RepairStage.repairing
      ..stageDone = 7
      ..stageTotal = 24;
    expect(run.status.text, 'AI 修，7／24 個網站');
  });

  test('a single repair notification says what is being done, not which '
      'round', () async {
    final checking = Completer<void>();
    final answering = Completer<void>();
    final session = AiRepairSession(
      source: _s('one'),
      service: _service,
      check: (source, _) async {
        await checking.future;
        return SourceCheckIsolateResult(
          stage: 'content',
          message: '正文為空',
          isHealthy: false,
          updatedSourceJson: source.toJson(),
          logs: const [],
        );
      },
      probe: (_, _, {start}) async =>
          const SourceProbeReport(logs: [], requests: []),
      ask: (_, _) async {
        await answering.future;
        return fakeAiReply(
          jsonEncode({
            'action': 'give_up',
            'why': 'site_gone',
            'reason': '網站關了',
          }),
        );
      },
      secrets: (_) async => const {},
    );
    final run = SingleRepairRun(
      session,
      progress: _MemoryFile(),
      work: work,
      navigator: () => null,
    );
    expect(run.status.title, 'AI 修復 · one');
    expect(run.status.text, '準備中…');

    final done = run.run();
    for (var i = 0; i < 20 && session.job.steps.isEmpty; i++) {
      await _flush();
    }
    expect(run.status.text, '校驗原本的書源');

    checking.complete();
    for (var i = 0; i < 20 && session.job.steps.length < 3; i++) {
      await _flush();
    }
    expect(session.job.steps.last.title, '第 1 輪', reason: '紀錄照寫輪次');
    expect(run.status.text, 'AI 回覆中…');

    answering.complete();
    await done;
    run.disposeWork();
    run.dispose();
  });

  test(
    'a single repair records a confirmed unstable site as removable',
    () async {
      final marked = <String>[];
      final session = AiRepairSession(
        source: _s('unstable'),
        service: _service,
        check: (source, _) async => SourceCheckIsolateResult(
          stage: 'content',
          message: '正文為空',
          isHealthy: false,
          updatedSourceJson: source.toJson(),
          logs: const [],
        ),
        probe: (_, _, {start}) async =>
            const SourceProbeReport(logs: [], requests: []),
        ask: (_, _) async => fakeAiReply(
          jsonEncode({
            'action': 'give_up',
            'why': 'site_unstable',
            'reason': '同一請求時好時壞',
          }),
        ),
        secrets: (_) async => <String>{},
      );
      final run = SingleRepairRun(
        session,
        progress: _MemoryFile(),
        work: work,
        navigator: () => null,
        markUnfixable: (source, reason) async =>
            marked.add('${source.bookSourceUrl}:$reason'),
      );
      await run.run();

      expect(marked, ['https://unstable.example:site_unstable']);
      expect(run.sourceEdits, 1);
      run.disposeWork();
      run.dispose();
    },
  );

  test('a batch that finishes with no page open stays until its results '
      'are seen, then is let go', () async {
    final batch = _batch();
    final run = runOf(batch);
    runs.adopt(run);
    run.start();
    await batch.completion;
    await _flush();

    expect(work.isBusy, isFalse);
    expect(platform.calls.last, 'hide');
    expect(runs.current, same(run), reason: '還沒看過結果');

    run
      ..attach()
      ..detach();
    await _flush();
    expect(runs.current, isNull);
  });

  test(
    'an unread batch result cannot be replaced by a single repair',
    () async {
      final first = runOf(_batch());
      expect(runs.adopt(first), isTrue);
      first.start();
      await first.batch.completion;
      await _flush();
      expect(first.isFinished, isTrue);
      expect(first.isDone, isFalse);

      final attempted = SingleRepairRun(
        AiRepairSession(source: _s('different'), service: null),
        work: work,
        navigator: () => null,
      );
      expect(runs.adopt(attempted), isFalse);
      expect(runs.current, same(first), reason: '還沒看過的結果不能被取代');
      attempted.disposeWork();
      attempted.dispose();

      // 回到結果頁再關掉，下一件工作才可以開始。
      first
        ..attach()
        ..detach();
      await _flush();
      expect(runs.current, isNull);

      final next = runOf(_batch());
      expect(runs.adopt(next), isTrue);
      expect(runs.current, same(next));
      next.disposeWork();
      next.dispose();
      runs.dispose();
    },
  );

  test('an in-progress result also cannot be replaced directly', () async {
    final gate = Completer<void>();
    final first = runOf(_batch(gate: gate));
    expect(runs.adopt(first), isTrue);
    first.start();
    await _flush();

    final attempted = runOf(_batch());
    expect(runs.adopt(attempted), isFalse);
    expect(runs.current, same(first));
    attempted.disposeWork();
    attempted.dispose();

    gate.complete();
    await first.batch.completion;
    await _flush();
    first
      ..attach()
      ..detach();
    await _flush();
    expect(runs.current, isNull);
    runs.dispose();
  });

  test('end on the notification ends the batch and says so', () async {
    final gate = Completer<void>();
    final batch = _batch(gate: gate);
    final run = runOf(batch);
    run.start();
    await _flush();

    run.endFromSystem();
    await _flush();
    expect(batch.isStopped, isTrue);
    expect(platform.calls.last, startsWith('正在結束…'));

    gate.complete();
    await batch.completion;
    await _flush();
    expect(platform.calls.last, 'hide');
    expect(work.isBusy, isFalse);
  });

  group('a source check', () {
    SourceCheckEntry entry(String url) => SourceCheckEntry(
      sourceUrl: url,
      sourceName: url,
      stage: '搜尋',
      message: 'ok',
      health: SourceRuntimeHealth.healthy,
    );

    /// 假的校驗：照順序校驗 [urls]，每做完一個回報；校驗完 [stopAfter] 個之後
    /// 等到被取消才回來（取消時正在校驗的那個不算做完）。
    ({SourceCheckJob job, ValueNotifier<int> changes}) jobOf(
      SourceCheckPlan plan,
      _MemoryFile file,
      PausedSourceCheck paused, {
      int stopAfter = 1,
      List<int>? doneBeforeSeen,
    }) {
      final changes = ValueNotifier<int>(plan.finished.length);
      final cancel = Completer<void>();
      final job = SourceCheckJob(
        plan: plan,
        changes: changes,
        done: () => changes.value,
        total: () => plan.urls.length,
        cancel: () {
          if (!cancel.isCompleted) cancel.complete();
        },
        check:
            (
              urls, {
              required doneBefore,
              required earlier,
              required onFinished,
            }) async {
              doneBeforeSeen?.add(doneBefore);
              for (final (i, url) in urls.indexed) {
                if (i >= stopAfter) {
                  await cancel.future;
                  return;
                }
                await Future<void>.delayed(Duration.zero);
                onFinished(url, entry(url));
                changes.value++;
              }
            },
        file: file,
        paused: paused,
        work: work,
      );
      return (job: job, changes: changes);
    }

    test('holds the slot and reports how far it got; end keeps what was '
        'checked and drops the save', () async {
      final file = _MemoryFile();
      final paused = PausedSourceCheck(file: _MemoryFile.new);
      final plan = SourceCheckPlan(['a', 'b', 'c', 'd']);
      final (:job, changes: _) = jobOf(plan, file, paused);

      final running = job.run();
      expect(work.isBusy, isTrue);
      await _flush();
      await _flush();
      job.endFromSystem();
      await running;
      await _flush();

      expect(platform.calls, ['第 0／4 個｜0', '第 1／4 個｜250', '正在結束…｜250', 'hide']);
      expect(work.isBusy, isFalse);
      expect(file.closed, isTrue);
      expect(paused.isPaused, isFalse);
      expect(plan.finished, {'a'});
    });

    test('pause keeps what is left; continue checks only that, counting on '
        'from what was done', () async {
      final file = _MemoryFile();
      final paused = PausedSourceCheck(file: _MemoryFile.new);
      final (:job, changes: _) = jobOf(
        SourceCheckPlan(['a', 'b', 'c', 'd']),
        file,
        paused,
      );
      final running = job.run();
      await _flush();
      await _flush();
      job.pauseFromSystem();
      await running;
      await _flush();

      expect(work.isBusy, isFalse, reason: '暫停空出位置、收掉通知');
      expect(platform.calls, ['第 0／4 個｜0', '第 1／4 個｜250', '正在暫停…｜250', 'hide']);
      expect(paused.plan!.remaining, ['b', 'c', 'd']);
      expect(file.closed, isFalse);
      final saved = SourceCheckPlan.decode(file.text!)!;
      expect(saved.finished, {'a'}, reason: '下次開 App 讀得回來');
      expect(saved.entries.single.sourceUrl, 'a');

      final (plan, kept) = paused.take()!;
      final seen = <int>[];
      final (job: resumed, changes: _) = jobOf(
        plan,
        kept as _MemoryFile,
        paused,
        stopAfter: 99,
        doneBeforeSeen: seen,
      );
      await resumed.run();
      expect(seen, [1]);
      expect(plan.finished, {'a', 'b', 'c', 'd'});
      expect(plan.entries.map((e) => e.sourceUrl), ['a', 'b', 'c', 'd']);
      expect(kept.closed, isTrue, reason: '做完了，存檔刪掉');
      expect(paused.isPaused, isFalse);
    });

    test('a check left when the app was closed comes back paused; ending it '
        'drops the save', () async {
      final left = SourceCheckPlan(
        ['a', 'b'],
        finished: {'a'},
        entries: [entry('a')],
      );
      final file = _MemoryFile(left.encode());
      final paused = PausedSourceCheck(file: () => file);
      await paused.restore();
      expect(paused.plan!.remaining, ['b']);
      expect(paused.plan!.entries.single.sourceUrl, 'a');

      await paused.end();
      expect(paused.isPaused, isFalse);
      expect(file.closed, isTrue);
    });

    test('a save that cannot be read is dropped', () async {
      final file = _MemoryFile('{"version": 0}');
      final paused = PausedSourceCheck(file: () => file);
      await paused.restore();
      expect(paused.isPaused, isFalse);
      expect(file.closed, isTrue);
    });
  });

  testWidgets('going back from the page leaves the batch running', (
    tester,
  ) async {
    final gate = Completer<void>();
    final batch = _batch(gate: gate);
    final run = runOf(batch);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: const SizedBox(),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => SourceRepairPage(run: run)),
      ),
    );
    await _settle(tester);
    expect(batch.isRunning, isTrue);
    expect(work.isBusy, isTrue);

    navigator.currentState!.pop();
    await _settle(tester);
    expect(find.byType(SourceRepairPage), findsNothing);
    expect(batch.isRunning, isTrue);
    expect(batch.isStopped, isFalse);

    gate.complete();
    await tester.runAsync(() => batch.completion);
    await tester.pump();
    expect(work.isBusy, isFalse);
  });

  testWidgets('a paused single repair brought back after the app was closed '
      'shows the four stages, not the clipboard steps', (tester) async {
    // 還原時只知道書源網址，工作沒有 AI 服務（按繼續時才照設定重開）。
    final run = SingleRepairRun.paused(
      AiRepairSession(source: _s('one'), service: null),
      file: _MemoryFile(),
      work: work,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: run.page(),
      ),
    );
    await _settle(tester);

    expect(find.text('校驗原本的書源'), findsOneWidget);
    expect(find.text('AI 修改規則'), findsOneWidget);
    expect(find.text('校驗修好的書源'), findsOneWidget);
    expect(find.text('已暫停'), findsOneWidget);
    expect(find.text('繼續'), findsOneWidget);
    run.disposeWork();
    run.dispose();
  });

  group('ending while the pause is still settling', () {
    /// AI 回覆要等 [gate] 才停得下來：按了暫停、還沒停好的那一段看得到。
    AiRepairSession slowToStop(Completer<void> gate) => AiRepairSession(
      source: _s('one'),
      service: _service,
      check: (source, _) async => SourceCheckIsolateResult(
        stage: 'content',
        message: '正文為空',
        isHealthy: false,
        updatedSourceJson: source.toJson(),
        logs: const [],
      ),
      probe: (_, _, {start}) async =>
          const SourceProbeReport(logs: [], requests: []),
      ask: (_, token) async {
        await gate.future;
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(),
          reason: token.cancelError?.message ?? '',
        );
      },
      apply: (_, _) async {},
      secrets: (_) async => const {},
      backups: AiRepairBackups(),
    );

    testWidgets('a single repair page shows pausing, then ending, then done; '
        'the notification says the same', (tester) async {
      final gate = Completer<void>();
      final file = _MemoryFile();
      final run = SingleRepairRun(
        slowToStop(gate),
        progress: file,
        work: work,
        navigator: () => null,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: run.page(),
        ),
      );
      run.start();
      for (var i = 0; i < 20 && run.session.job.steps.length < 3; i++) {
        await tester.runAsync(_flush);
      }
      await tester.pump();
      expect(find.text('暫停'), findsOneWidget);
      expect(find.text('結束'), findsOneWidget);

      run.pauseNow();
      await tester.pump();
      expect(run.status.text, '正在暫停…');
      expect(run.status.actions, isEmpty);
      expect(find.text('正在暫停…'), findsOneWidget);
      expect(find.text('結束'), findsOneWidget, reason: '正在暫停時還能按結束');

      await run.end();
      await tester.pump();
      expect(run.status.text, '正在結束…');
      expect(find.text('正在結束…'), findsOneWidget);

      gate.complete();
      for (var i = 0; i < 40 && !run.isFinished; i++) {
        await tester.runAsync(_flush);
      }
      await _settle(tester);
      expect(run.isFinished, isTrue, reason: '結束蓋過暫停');
      expect(run.isPaused, isFalse);
      expect(run.session.job.explanation, '已結束，書源沒有改。');
      expect(file.closed, isTrue);
      expect(work.isBusy, isFalse);
      expect(find.text('完成'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(_flush);
      run
        ..disposeWork()
        ..dispose();
    });

    test('a batch ends rather than pauses, and the notification says '
        'ending', () async {
      final gate = Completer<void>();
      final file = _MemoryFile();
      final run = BatchRepairRun(
        _batch(gate: gate),
        title: '修復異常書源',
        progress: file,
        work: work,
        navigator: () => null,
      );
      run.start();
      await _flush();
      run.pauseNow();
      expect(run.status.text, '正在暫停…');

      await run.end();
      expect(run.status.text, '正在結束…');
      gate.complete();
      await run.batch.completion;
      await _flush();
      await _flush();

      expect(run.isFinished, isTrue);
      expect(run.isPaused, isFalse);
      expect(file.closed, isTrue);
      expect(work.isBusy, isFalse);
      expect(platform.calls.last, 'hide');
    });
  });

  group('pausing a repair', () {
    test('a batch paused during the recheck frees the slot, keeps its save '
        'and continues as a new batch', () async {
      final gate = Completer<void>();
      final file = _MemoryFile();
      final reopened = <List<String>>[];
      final run = BatchRepairRun(
        _batch(gate: gate),
        title: '修復異常書源',
        progress: file,
        work: work,
        navigator: () => null,
        reopen: (progress) async {
          reopened.add(progress.urls);
          return _batch();
        },
      );
      runs.adopt(run);
      run.start();
      await _flush();
      run.pauseNow();
      expect(run.status.text, '正在暫停…');
      gate.complete();
      await run.batch.completion;
      await _flush();
      await _flush();

      expect(run.isPaused, isTrue);
      expect(run.isFinished, isFalse);
      expect(work.isBusy, isFalse, reason: '暫停空出位置、收掉通知');
      expect(platform.calls.last, 'hide');
      final saved = jsonDecode(file.text!) as Map<String, Object?>;
      expect(saved['kind'], 'batch');
      expect(saved['urls'], ['https://s0.example', 'https://s1.example']);
      expect(runs.current, same(run), reason: '入口推回暫停的這一批');

      await run.resume();
      await run.batch.completion;
      await _flush();
      await _flush();
      expect(reopened, [
        ['https://s0.example', 'https://s1.example'],
      ]);
      expect(run.isFinished, isTrue);
      expect(file.closed, isTrue, reason: '做完了，存檔刪掉');
    });

    test('a single repair paused while the AI answers continues as a fresh '
        'repair of the same source', () async {
      final file = _MemoryFile();
      AiRepairSession session({required bool blocks}) => AiRepairSession(
        source: _s('one'),
        service: _service,
        check: (source, _) async => SourceCheckIsolateResult(
          stage: 'content',
          message: '正文為空',
          isHealthy: false,
          updatedSourceJson: source.toJson(),
          logs: const [],
        ),
        probe: (_, _, {start}) async =>
            const SourceProbeReport(logs: [], requests: []),
        ask: (_, token) async {
          if (!blocks) {
            return fakeAiReply(
              jsonEncode({
                'action': 'give_up',
                'why': 'site_gone',
                'reason': '網站關了',
              }),
            );
          }
          await token.whenCancel;
          throw DioException.requestCancelled(
            requestOptions: RequestOptions(),
            reason: '已暫停',
          );
        },
        apply: (_, _) async {},
        secrets: (_) async => const {},
        backups: AiRepairBackups(),
      );
      final reopened = <String>[];
      final run = SingleRepairRun(
        session(blocks: true),
        progress: file,
        work: work,
        navigator: () => null,
        reopen: (url) async {
          reopened.add(url);
          return session(blocks: false);
        },
      );
      run.start();
      for (var i = 0; i < 20 && run.session.job.steps.length < 3; i++) {
        await _flush();
      }
      run.pauseNow();
      for (var i = 0; i < 20 && !run.isPaused; i++) {
        await _flush();
      }
      expect(run.isPaused, isTrue);
      expect(run.session.job.outcome, isNull, reason: '暫停不定案、書源不改');
      expect(jsonDecode(file.text!), {
        'version': 1,
        'kind': 'single',
        'url': 'https://one.example',
      });
      expect(work.isBusy, isFalse);

      await run.resume();
      for (var i = 0; i < 40 && !run.isFinished; i++) {
        await _flush();
      }
      expect(reopened, ['https://one.example']);
      expect(run.isFinished, isTrue);
      expect(file.closed, isTrue);
    });

    test('a batch left paused when the app was closed comes back with its '
        'results; ending it drops the save', () async {
      final file = _MemoryFile(
        jsonEncode({
          'version': 1,
          'kind': 'batch',
          'title': '修復異常書源',
          'baseUrl': 'https://ai.example/v1',
          'model': 'm',
          'urls': ['https://s0.example', 'https://s1.example'],
          'done': {
            'https://s0.example': ['healthy', '重新校驗就沒問題了', 0],
          },
          'reused': [
            'https://s0.example',
            'https://s9.example',
            'https://s8.example',
          ],
          'tokensUsed': 5000,
        }),
      );
      await restorePausedRepair(
        file: file,
        runs: runs,
        load: (urls) async => [
          for (final url in urls) _s(Uri.parse(url).host.split('.').first),
        ],
        work: work,
      );
      final run = runs.current! as BatchRepairRun;
      expect(run.isPaused, isTrue);
      expect(run.batch.items.first.outcome, RepairOutcome.healthy);
      expect(run.batch.items.last.outcome, isNull);
      expect(run.batch.reusedChecks, 3);
      expect(run.batch.tokensUsed, 5000, reason: '沒定案的書源花掉的也算');
      expect(run.batch.service.model, 'm');

      await run.end();
      expect(run.isFinished, isTrue);
      expect(run.batch.items.last.outcome, RepairOutcome.notTried);
      expect(file.closed, isTrue);
    });

    test('a single repair whose source is gone is not brought back', () async {
      final file = _MemoryFile(
        jsonEncode({
          'version': 1,
          'kind': 'single',
          'url': 'https://x.example',
        }),
      );
      await restorePausedRepair(
        file: file,
        runs: runs,
        load: (_) async => const [],
        work: work,
      );
      expect(runs.current, isNull);
      expect(file.closed, isTrue);
    });
  });

  test('a new repair ends the paused one in the source manager; a paused AI '
      'find keeps its place', () async {
    final repairs = RepairRuns(newEndsPaused: true);
    final file = _MemoryFile(
      jsonEncode({'version': 1, 'kind': 'single', 'url': 'https://a.example'}),
    );
    await restorePausedRepair(
      file: file,
      runs: repairs,
      load: (_) async => [_s('a')],
      work: work,
    );
    final paused = repairs.current!;
    expect(paused.isPaused, isTrue);
    expect(repairs.canStartNew, isTrue, reason: '別的書源的 AI 修復不再灰著');

    final next = SingleRepairRun(
      AiRepairSession(source: _s('b'), service: null),
      progress: _MemoryFile(),
      work: work,
      navigator: () => null,
    );
    expect(repairs.adopt(next), isTrue);
    expect(repairs.current, same(next));
    await _flush();
    await _flush();
    expect(paused.isFinished, isTrue, reason: '暫停的那件結束了');
    expect(file.closed, isTrue);

    final finds = RepairRuns();
    final pausedFind = SingleRepairRun.paused(
      AiRepairSession(source: _s('c'), service: null),
      file: _MemoryFile('{}'),
      work: work,
    );
    expect(finds.adopt(pausedFind), isTrue);
    expect(finds.canStartNew, isFalse, reason: 'AI 找書的 ✦ 推回暫停的那次');
    repairs.dispose();
    finds.dispose();
  });

  test('ending while continue is still reading back keeps the ended repair '
      'and lets go of the late one', () async {
    final reopening = Completer<AiRepairSession?>();
    final run = SingleRepairRun.paused(
      AiRepairSession(source: _s('a'), service: null),
      file: _MemoryFile('{}'),
      reopen: (_) => reopening.future,
      work: work,
    );
    final original = run.session;
    final resuming = run.resume();
    await _flush();
    await run.end();
    expect(run.isFinished, isTrue);
    reopening.complete(AiRepairSession(source: _s('a'), service: _service));
    await resuming;
    expect(run.session, same(original), reason: '晚到的新修復不換上去');
    expect(run.isFinished, isTrue);
    expect(work.isBusy, isFalse);
  });

  test('a paused page hears when the slot frees up, so continue turns on', () {
    final run = SingleRepairRun.paused(
      AiRepairSession(source: _s('a'), service: null),
      file: _MemoryFile('{}'),
      work: work,
    );
    var heard = 0;
    run.addListener(() => heard++);
    final other = _Other();
    work.begin(other, const BackgroundWorkStatus(title: '校驗書源', text: ''));
    expect(run.canResume, isFalse);
    work.end(other);
    expect(run.canResume, isTrue);
    expect(heard, 2, reason: '佔住、空出各通知一次');
    run.dispose();
  });
}

class _Other implements BackgroundJob {
  @override
  void pauseFromSystem() {}

  @override
  void endFromSystem() {}

  @override
  void openFromNotification() {}
}
