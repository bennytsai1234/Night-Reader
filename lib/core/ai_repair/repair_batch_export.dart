import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/crash_handler.dart';

import 'ai_repair_secrets.dart';
import 'source_repair_batch.dart';

/// 一批修復的全部紀錄打包成一個 ZIP（修復異常書源頁的「分享這批的全部紀錄」，
/// ADR 0054）：
/// - `整批結果.txt`：這批的設定、用量，與每個書源的結果、說明、網站檢查、
///   用量和它的完整紀錄是哪一份；
/// - `整批結果.json`：同樣的內容，一個書源一筆，給評估工具讀；
/// - `紀錄/`：交給 AI 修的每個書源的完整紀錄（[AiRepairLog] 寫的那份，秘密
///   已經遮掉）。紀錄資料夾超過上限時舊的會被清掉，清掉的在結果裡寫明。
///
/// 兩份結果從同一份 [_Row] 產生，每段文字照修復紀錄的規則遮掉秘密：書源的
/// 登入資料、Cookie 與變數（[secrets]），AI 服務的金鑰，交給 AI 的書源再加上
/// 修復途中讀到的。
Future<File> exportRepairBatch(
  SourceRepairBatch batch, {
  required String title,
  required Directory into,
  DateTime? now,
  Future<Set<String>> Function(BookSource source)? secrets,
}) async {
  final time = now ?? DateTime.now();
  final stamp = DateFormat('yyyyMMdd-HHmmss-SSS').format(time);
  into.createSync(recursive: true);
  final file = File('${into.path}/修復紀錄-$stamp.zip');
  if (file.existsSync()) file.deleteSync();

  final secretsOf = secrets ?? _defaultSecrets;
  final apiKey = batch.service.apiKey;
  final everySecret = <String>{if (apiKey.length >= 6) apiKey};
  final rows = <_Row>[];
  for (final item in batch.items) {
    final found = {...await secretsOf(item.source), ...everySecret};
    everySecret.addAll(found);
    final session = item.session;
    String redact(String text) {
      final known = redactAiRepairSecrets(text, found);
      return session == null ? known : session.log.redact(known);
    }

    rows.add(
      _Row(
        item,
        redact,
        log: session == null ? null : await session.log.file(),
      ),
    );
  }
  String redactAll(String text) => redactAiRepairSecrets(text, everySecret);

  final encoder = ZipFileEncoder()..create(file.path);
  try {
    final logged = <_Row>[];
    for (final row in rows) {
      final log = row.log;
      if (log == null) continue;
      // 被修剪掉的（或剛好在打包時被清掉的）照「已被清掉」寫。
      try {
        await encoder.addFile(log, row.logName);
        logged.add(row);
      } on FileSystemException {
        continue;
      }
    }
    String? logOf(_Row row) => logged.contains(row)
        ? row.logName
        : row.log == null
        ? null
        : '（已被清掉）';
    encoder
      ..addArchiveFile(
        ArchiveFile.string(
          '整批結果.txt',
          _summary(batch, title, time, rows, logOf, redactAll),
        ),
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
            'error': batch.errorMessage == null
                ? null
                : redactAll(batch.errorMessage!),
            'sources': [for (final row in rows) row.toJson(logOf(row))],
          }),
        ),
      );
  } finally {
    await encoder.close();
  }
  return file;
}

Future<Set<String>> _defaultSecrets(BookSource source) async => {
  ...await aiRepairSecretsOf(source),
  ...aiRepairLiveCookieSecrets([source.bookSourceUrl]),
};

/// 一個書源匯出的樣子：自由文字都已經遮過。
final class _Row {
  _Row(this.item, String Function(String) redact, {this.log})
    : name = redact(item.source.bookSourceName),
      url = redact(item.source.bookSourceUrl),
      detail = item.detail == null ? null : redact(item.detail!),
      siteDetail = item.site == null ? null : redact(item.site!.detail),
      movedTo = item.site?.movedTo == null ? null : redact(item.site!.movedTo!),
      sharedFrom = item.sharedFrom == null
          ? null
          : redact(item.sharedFrom!.source.bookSourceUrl);

  final RepairItem item;
  final File? log;
  final String name;
  final String url;
  final String? detail;
  final String? siteDetail;
  final String? movedTo;
  final String? sharedFrom;

  String get logName => '紀錄/${log!.uri.pathSegments.last}';

  Map<String, Object?> toJson(String? log) => {
    'name': name,
    'url': url,
    'outcome': item.outcome?.name,
    'detail': detail,
    'site': item.site?.verdict.name,
    'siteDetail': siteDetail,
    'movedTo': movedTo,
    'tokens': item.tokens,
    'sharedFrom': sharedFrom,
    if (item.session case final session?) ...{
      'rounds': session.stats?.rounds,
      'log': log,
    },
  };
}

String _summary(
  SourceRepairBatch batch,
  String title,
  DateTime time,
  List<_Row> rows,
  String? Function(_Row row) logOf,
  String Function(String text) redact,
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
    if (batch.errorMessage case final error?) '修復中斷：${redact(error)}',
    '',
  ];
  for (final outcome in [...RepairOutcome.values, null]) {
    final group = [
      for (final row in rows)
        if (row.item.outcome == outcome) row,
    ];
    if (group.isEmpty) continue;
    lines.add('## ${_outcomeTitle(outcome)} · ${group.length}');
    for (final row in group) {
      final site = row.item.site;
      final parts = [
        if (row.detail case final detail? when detail.isNotEmpty) detail,
        if (site != null)
          '網站：${row.siteDetail}'
              '${row.movedTo == null ? '' : '（搬到 ${row.movedTo}）'}',
        if (row.item.tokens > 0) '${row.item.tokens} token',
        if (row.item.session != null) '紀錄：${logOf(row) ?? '沒有存成檔案'}',
      ];
      lines.add(
        '- ${row.name}（${row.url}）'
        '${parts.isEmpty ? '' : '：${parts.join('；')}'}',
      );
    }
    lines.add('');
  }
  return lines.join('\n');
}

String _outcomeTitle(RepairOutcome? outcome) => switch (outcome) {
  RepairOutcome.healthy => '重新校驗就沒問題了',
  RepairOutcome.moved => '換網址修好',
  RepairOutcome.aiFixed => 'AI 修好',
  RepairOutcome.shared => '套用同網站修好的規則',
  RepairOutcome.siteGone => '網站不在了',
  RepairOutcome.notFixed => '沒修好',
  RepairOutcome.skipped => '不用修',
  RepairOutcome.aiUnfixable => 'AI 之前修不好',
  RepairOutcome.notTried => '沒輪到',
  null => '還在修',
};
