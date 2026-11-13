import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:night_reader/core/services/crash_handler.dart';

import 'source_repair_batch.dart';

/// 一批修復的全部紀錄打包成一個 ZIP（修復異常書源頁的「分享這批的全部紀錄」，
/// ADR 0054）：
/// - `整批結果.txt`：這批的設定、用量、每一段的結果，與每個書源的結果、說明、
///   用量和它的完整紀錄是哪一份；
/// - `整批結果.json`：同樣的內容，一個書源一筆，給評估工具讀；
/// - `紀錄/`：交給 AI 修的每個書源的完整紀錄（[AiRepairLog] 寫的那份，秘密
///   已經遮掉）。紀錄資料夾超過上限時舊的會被清掉，清掉的在結果裡寫明。
Future<File> exportRepairBatch(
  SourceRepairBatch batch, {
  required String title,
  required Directory into,
  DateTime? now,
}) async {
  final time = now ?? DateTime.now();
  final stamp = DateFormat('yyyyMMdd-HHmmss').format(time);
  into.createSync(recursive: true);
  final file = File('${into.path}/修復紀錄-$stamp.zip');
  if (file.existsSync()) file.deleteSync();

  final logs = <RepairItem, File?>{};
  for (final item in batch.items) {
    final session = item.session;
    if (session != null) logs[item] = await session.log.file();
  }
  String? logName(RepairItem item) {
    final log = logs[item];
    if (log == null || !log.existsSync()) return null;
    return '紀錄/${log.uri.pathSegments.last}';
  }

  final rows = [
    for (final item in batch.items)
      {
        'name': item.source.bookSourceName,
        'url': item.source.bookSourceUrl,
        'outcome': item.outcome?.name,
        'detail': item.detail,
        'site': item.site?.verdict.name,
        'siteDetail': item.site?.detail,
        'movedTo': item.site?.movedTo,
        'tokens': item.tokens,
        'sharedFrom': item.sharedFrom?.source.bookSourceUrl,
        'merged': item.merged,
        if (item.session case final session?) ...{
          'rounds': session.stats?.rounds,
          'log': logName(item) ?? (logs[item] == null ? null : '（已被清掉）'),
        },
      },
  ];

  final encoder = ZipFileEncoder()..create(file.path);
  try {
    encoder
      ..addArchiveFile(
        ArchiveFile.string('整批結果.txt', _summary(batch, title, time, logName)),
      )
      ..addArchiveFile(
        ArchiveFile.string(
          '整批結果.json',
          const JsonEncoder.withIndent('  ').convert({
            'title': title,
            'exportedAt': time.toIso8601String(),
            'app': CrashHandler.appVersionLine,
            'service': {
              'host': Uri.tryParse(batch.service.baseUrl)?.host,
              'model': batch.service.model,
              'effort': batch.service.effort,
            },
            'tokenBudget': batch.tokenBudget,
            'tokensUsed': batch.tokensUsed,
            'reusedChecks': batch.reusedChecks,
            'stoppedStage': batch.stoppedStage?.name,
            'failedStage': batch.failedStage?.name,
            'error': batch.errorMessage,
            'sources': rows,
          }),
        ),
      );
    for (final MapEntry(key: item, value: log) in logs.entries) {
      final name = logName(item);
      if (log == null || name == null) continue;
      await encoder.addFile(log, name);
    }
  } finally {
    await encoder.close();
  }
  return file;
}

String _summary(
  SourceRepairBatch batch,
  String title,
  DateTime time,
  String? Function(RepairItem item) logName,
) {
  final service = batch.service;
  final lines = <String>[
    '# $title',
    [
      if (CrashHandler.appVersionLine.isNotEmpty)
        '夜讀${CrashHandler.appVersionLine}',
      'AI：${Uri.tryParse(service.baseUrl)?.host ?? service.baseUrl} · '
          '${service.model}'
          '${service.effort.isEmpty ? '' : '（思考程度 ${service.effort}）'}',
      DateFormat('yyyy-MM-dd HH:mm').format(time),
    ].join(' · '),
    '',
    'AI 用量：${batch.tokensUsed} token'
        '${batch.tokenBudget == null ? '（不限）' : '／上限 ${batch.tokenBudget}'}',
    '沿用 24 小時內的校驗結果：${batch.reusedChecks} 個',
    if (batch.stoppedStage case final stage?) '按了停止：做到 ${stage.name}',
    if (batch.errorMessage case final error?) '修復中斷：$error',
    '',
  ];
  for (final outcome in RepairOutcome.values) {
    final group = [
      for (final item in batch.items)
        if (item.outcome == outcome) item,
    ];
    if (group.isEmpty) continue;
    lines.add('## ${_outcomeTitle(outcome)} · ${group.length}');
    for (final item in group) {
      final parts = [
        if (item.detail case final detail? when detail.isNotEmpty) detail,
        if (item.tokens > 0) '${item.tokens} token',
        if (item.merged) '已併進「${item.sharedFrom!.source.bookSourceName}」',
        if (item.session != null) '紀錄：${logName(item) ?? '已被清掉'}',
      ];
      lines.add(
        '- ${item.source.bookSourceName}（${item.source.bookSourceUrl}）'
        '${parts.isEmpty ? '' : '：${parts.join('；')}'}',
      );
    }
    lines.add('');
  }
  final unfinished = batch.items.where((item) => item.outcome == null).length;
  if (unfinished > 0) lines.add('## 還在修 · $unfinished');
  return lines.join('\n');
}

String _outcomeTitle(RepairOutcome outcome) => switch (outcome) {
  RepairOutcome.healthy => '重新校驗就沒問題了',
  RepairOutcome.moved => '換網址修好',
  RepairOutcome.aiFixed => 'AI 修好',
  RepairOutcome.shared => '套用同網站修好的規則',
  RepairOutcome.siteGone => '網站不在了',
  RepairOutcome.notFixed => '沒修好',
  RepairOutcome.skipped => '不用修',
  RepairOutcome.aiUnfixable => 'AI 之前修不好',
  RepairOutcome.notTried => '沒輪到',
};
