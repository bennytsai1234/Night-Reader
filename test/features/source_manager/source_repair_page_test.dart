import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/source_repair_batch.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/features/source_manager/ai_repair/source_repair_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

const _service = (
  baseUrl: 'https://ai.example/v1',
  apiKey: 'k',
  model: 'm',
  effort: '',
);

BookSource _s(String name) =>
    BookSource(bookSourceUrl: 'https://$name.example', bookSourceName: name);

SourceRepairBatch _batch(List<(String, RepairOutcome?)> rows) {
  final batch = SourceRepairBatch(
    sources: [for (final (name, _) in rows) _s(name)],
    service: _service,
  );
  for (var i = 0; i < rows.length; i++) {
    batch.items[i]
      ..outcome = rows[i].$2
      ..detail = '說明 ${rows[i].$1}';
  }
  return batch;
}

Future<void> _pump(WidgetTester tester, SourceRepairBatch batch) async {
  // 清單只建畫面上的列：畫面拉高，整頁都建出來。
  tester.view
    ..physicalSize = const Size(400, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(AppStyle.paper, Brightness.light),
      home: SourceRepairPage(batch: batch, title: '修復異常書源', autoStart: false),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('a finished batch groups the sources by what happened', (
    tester,
  ) async {
    final batch = _batch([
      ('甲', RepairOutcome.aiFixed),
      ('乙', RepairOutcome.shared),
      ('丙', RepairOutcome.siteGone),
      ('丁', RepairOutcome.notFixed),
      ('戊', RepairOutcome.healthy),
    ])..stage = RepairStage.done;

    await _pump(tester, batch);

    expect(find.text('修好了 · 2'), findsOneWidget);
    expect(find.text('網站不在了 · 1'), findsOneWidget);
    expect(find.text('停用這 1 個'), findsOneWidget);
    expect(find.text('刪除這 1 個'), findsOneWidget);
    expect(find.text('沒修好 · 1'), findsOneWidget);
    expect(find.text('重新校驗就沒問題了'), findsOneWidget);
    expect(find.text('沒問題 1 個'), findsOneWidget, reason: '不修 0 個不寫');
    expect(find.text('完成'), findsOneWidget);
  });

  testWidgets('an unexpected error is visible', (
    tester,
  ) async {
    final batch = _batch([('甲', RepairOutcome.notTried)])
      ..stage = RepairStage.done
      ..failedStage = RepairStage.checking
      ..errorMessage = '校驗服務無法啟動';

    await _pump(tester, batch);
    expect(find.text('修復中斷'), findsOneWidget);
    expect(find.text('校驗服務無法啟動'), findsOneWidget);
    expect(find.text('未處理'), findsOneWidget);
  });

  testWidgets('while the AI works the sites being repaired are listed with '
      'their latest step', (tester) async {
    final batch = _batch([('甲', null), ('乙', RepairOutcome.healthy)])
      ..stage = RepairStage.repairing
      ..stageDone = 0
      ..stageTotal = 1;
    final working = batch.items.first;
    working.session = AiRepairSession(source: working.source, service: _service)
      ..job.steps.add(AiRepairStep('第 2 輪', detail: 'AI 改了搜尋，試抓中…'));

    await _pump(tester, batch);

    expect(find.text('正在修 · 1'), findsOneWidget);
    expect(find.text('第 2 輪：AI 改了搜尋，試抓中…'), findsOneWidget);
    expect(find.text('0／1 個網站'), findsOneWidget);
    expect(find.text('停止'), findsOneWidget);
  });
}
