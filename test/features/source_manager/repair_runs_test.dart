import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/source_repair_batch.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/background_work/background_work.dart';
import 'package:night_reader/core/services/check_source_service.dart';
import 'package:night_reader/features/source_manager/ai_repair/repair_runs.dart';
import 'package:night_reader/features/source_manager/ai_repair/source_repair_page.dart';
import 'package:night_reader/features/source_manager/source_check_job.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

const _service = (
  baseUrl: 'https://ai.example/v1',
  apiKey: 'k',
  model: 'm',
  effort: '',
);

/// 換掉 Android 那一半，看通知實際收到什麼（只驗 Dart 這邊的協定）。
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
      recheck: (urls, progress) async {
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

  BatchRepairRun runOf(SourceRepairBatch batch) =>
      BatchRepairRun(batch, title: '修復異常書源', work: work, navigator: () => null);

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

    batch.stop();
    expect(run.status.text, '正在停下…');
  });

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

  test('an unread batch result cannot be replaced by a single repair', () async {
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
  });

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

  test('stop on the notification stops the batch and says so', () async {
    final gate = Completer<void>();
    final batch = _batch(gate: gate);
    final run = runOf(batch);
    run.start();
    await _flush();

    run.stopFromSystem();
    await _flush();
    expect(batch.isStopped, isTrue);
    expect(platform.calls.last, startsWith('正在停下…'));

    gate.complete();
    await batch.completion;
    await _flush();
    expect(platform.calls.last, 'hide');
    expect(work.isBusy, isFalse);
  });

  test('a source check holds the slot and reports how far it got', () async {
    final changes = ValueNotifier<int>(0);
    var cancelled = false;
    final finish = Completer<void>();
    final job = SourceCheckJob(
      changes: changes,
      done: () => changes.value,
      total: () => 4,
      cancel: () => cancelled = true,
      work: work,
    );

    final running = job.run(() => finish.future);
    expect(work.isBusy, isTrue);
    await _flush();
    changes.value = 1;
    await _flush();
    job.stopFromSystem();
    await _flush();
    finish.complete();
    await running;
    await _flush();

    expect(cancelled, isTrue);
    expect(platform.calls, ['第 0／4 個｜0', '第 1／4 個｜250', '正在停下…｜250', 'hide']);
    expect(work.isBusy, isFalse);
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
}
