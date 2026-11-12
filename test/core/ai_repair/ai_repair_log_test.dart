import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_repair_log.dart';

void main() {
  late Directory directory;

  setUp(() => directory = Directory.systemTemp.createTempSync('ai-repair-log'));
  tearDown(() => directory.deleteSync(recursive: true));

  AiRepairLog log() => AiRepairLog(
    sourceName: '蜘蛛小说网',
    sourceUrl: 'https://www.zhizhuxs.com',
    directory: () async => directory,
  );

  test('the summary keeps the start of each response and writes a repeated '
      'one only once; the full log keeps the whole page', () async {
    final page = '<p>${'大家都在搜索' * 100}</p>';
    final record = log()
      ..header('AI：api.example · m')
      ..section('抓網頁')
      ..requests(
        [
          'POST https://www.zhizhuxs.com/search/ 送出：searchkey=%E6%88%91',
          '  ← https://www.zhizhuxs.com/search/ 200 text/html，10837 位元組：$page',
          'https://www.zhizhuxs.com/search/?searchkey=x',
          '  ← https://www.zhizhuxs.com/search/ 200 text/html，10837 位元組：$page',
        ],
        pages: ['  ← https://www.zhizhuxs.com/search/ 200 text/html\n$page'],
      );

    final summary = record.summary;
    expect(summary, contains('送出：searchkey=%E6%88%91'));
    expect(summary, contains('（內容同前）'));
    expect(summary.length, lessThan(page.length));
    final full = (await record.file())!.readAsStringSync();
    expect(full, contains(page));
  });

  test('a long summary drops rounds from the middle and says which', () async {
    final record = log()..header('AI：api.example · m');
    for (var round = 1; round <= 20; round++) {
      record
        ..section('第 $round 輪', round: true)
        ..reply('{"action":"test","note":"${'改了規則' * 150}"}');
    }
    record
      ..section('結果')
      ..both('沒修好');

    await record.file();
    final summary = record.summary;
    expect(summary.length, lessThanOrEqualTo(AiRepairLog.summaryLength));
    expect(summary, contains('## 第 1 輪'));
    expect(summary, contains('## 第 20 輪'));
    expect(summary, contains('## 結果'));
    expect(summary, matches(RegExp(r'（省略 \d+ 輪：第 \d+ 輪')));
  });

  test('every piece is redacted before it is kept', () async {
    final record = log()
      ..redact = ((text) => text.replaceAll('sk-secret', '«已遮蔽»'))
      ..header('AI：api.example · m')
      ..section('第 1 輪', round: true)
      ..message('user', 'cookie=sk-secret')
      ..reply('看到 sk-secret');

    expect(record.summary, isNot(contains('sk-secret')));
    final full = (await record.file())!.readAsStringSync();
    expect(full, isNot(contains('sk-secret')));
    expect(full, contains('cookie=«已遮蔽»'));
  });

  test('only the newest logs are kept', () async {
    for (var i = 0; i < 105; i++) {
      final n = i.toString().padLeft(3, '0');
      File('${directory.path}/20260101-000000-$n-old.txt')
          .writeAsStringSync('舊的');
    }
    final record = log()..header('AI：api.example · m');
    final file = (await record.file())!;

    String name(File f) => f.uri.pathSegments.last;
    final left = directory.listSync().whereType<File>().map(name).toList();
    expect(left, hasLength(100));
    expect(left, contains(name(file)));
    expect(
      left,
      isNot(contains('20260101-000000-005-old.txt')),
      reason: '最舊的刪掉',
    );
    expect(left, contains('20260101-000000-006-old.txt'));
  });
}
