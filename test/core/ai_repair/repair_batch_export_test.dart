import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/repair_batch_export.dart';
import 'package:night_reader/core/ai_repair/source_repair_batch.dart';
import 'package:night_reader/core/models/book_source.dart';

const _service = (
  baseUrl: 'https://ai.example/v1',
  apiKey: 'k',
  model: 'm',
  effort: '',
);

void main() {
  late Directory directory;

  setUp(() => directory = Directory.systemTemp.createTempSync('repair-export'));
  tearDown(() => directory.deleteSync(recursive: true));

  test('one ZIP holds every source of the batch with its result, and the full '
      'log of each AI repair', () async {
    final batch = SourceRepairBatch(
      sources: [
        BookSource(bookSourceUrl: 'https://a.example', bookSourceName: '甲'),
        BookSource(bookSourceUrl: 'https://b.example', bookSourceName: '乙'),
      ],
      service: _service,
    )..tokensUsed = 1234;
    final repaired = batch.items.first;
    repaired
      ..outcome = RepairOutcome.aiFixed
      ..detail = 'AI：正文在 div.txt'
      ..tokens = 1234
      ..session = AiRepairSession(
        source: repaired.source,
        service: _service,
        logDirectory: () async => directory,
      );
    repaired.session!.log
      ..header('AI：ai.example · m')
      ..section('校驗原本的書源')
      ..both('正文失效：正文為空');
    batch.items.last
      ..outcome = RepairOutcome.skipped
      ..detail = '需要登入：不修（token=secret-token-123）';

    final zip = await exportRepairBatch(
      batch,
      title: '修復異常書源',
      into: Directory('${directory.path}/out'),
      now: DateTime(2026, 11, 13, 20),
      secrets: (source) async => {
        if (source.bookSourceName == '乙') 'secret-token-123',
      },
    );

    final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
    String text(String name) =>
        utf8.decode(archive.findFile(name)!.content as List<int>);
    final summary = text('整批結果.txt');
    expect(summary, contains('## AI 修好 · 1'));
    expect(summary, contains('甲（https://a.example）：AI：正文在 div.txt；1234 token'));
    expect(summary, contains('## 不用修 · 1'));
    expect(summary, isNot(contains('secret-token-123')), reason: '秘密要遮掉');
    expect(text('整批結果.json'), isNot(contains('secret-token-123')));
    final json = jsonDecode(text('整批結果.json')) as Map<String, dynamic>;
    expect(json['tokensUsed'], 1234);
    final rows = json['sources'] as List;
    expect(rows.first['outcome'], 'aiFixed');
    final log = rows.first['log'] as String;
    expect(text(log), contains('正文失效：正文為空'));
    expect(rows.last.containsKey('log'), isFalse, reason: '沒交給 AI 的沒有紀錄');
  });
}
