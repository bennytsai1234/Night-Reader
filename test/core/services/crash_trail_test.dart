import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/crash_trail.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('crash_trail');
    CrashTrail.resetForTesting();
  });

  tearDown(() async {
    // 正在寫的那一次寫完才刪資料夾：Windows 刪不掉開著的檔案。
    await CrashTrail.flushForTesting();
    CrashTrail.resetForTesting();
    await directory.delete(recursive: true);
  });

  test('a burst of logs does not push the actions out', () {
    CrashTrail.action('按了停止：修復異常書源');
    for (var i = 0; i < 200; i++) {
      CrashTrail.log('書源訊息 $i');
    }

    final text = CrashTrail.render();
    expect(text, contains('按了停止：修復異常書源'));
    expect(text, contains('書源訊息 199'));
    expect(text, isNot(contains('書源訊息 139')));
    expect('書源訊息 '.allMatches(text), hasLength(CrashTrail.maxLogs));
  });

  test('a long or multi-line log is cut to one short line', () {
    CrashTrail.log('第一行\n第二行${'字' * 500}');

    final line = CrashTrail.render()
        .split('\n')
        .firstWhere((line) => line.contains('第一行'));
    expect(line, contains('第一行 第二行'));
    expect(line.length, lessThan(CrashTrail.maxLineLength + 20));
  });

  test('login details in URLs and headers are masked', () {
    CrashTrail.log(
      'Network Request: [GET] https://user:pass@example.com/api'
      '?q=夜雨&token=abc123&page=2&Password=hunter2',
    );
    CrashTrail.log('書源標頭 {"Cookie": "sid=xyz; uid=42", "User-Agent": "夜讀"}');
    CrashTrail.log('Authorization: Bearer secret-value');

    final text = CrashTrail.render();
    for (final secret in [
      'user:pass',
      'abc123',
      'hunter2',
      'sid=xyz',
      'uid=42',
      'secret-value',
    ]) {
      expect(text, isNot(contains(secret)));
    }
    expect(text, contains('q=夜雨'));
    expect(text, contains('page=2'));
    expect(text, contains('"User-Agent": "夜讀"'));
  });

  test('what was recorded is on disk, and the next start reads it back as '
      'last time', () async {
    await CrashTrail.start(directory);
    CrashTrail.action('開始校驗書源（199 個）');
    await CrashTrail.flushForTesting();

    CrashTrail.resetForTesting();
    await CrashTrail.start(directory);

    final previous = CrashTrail.previous;
    expect(previous, isNotNull);
    expect(previous!.text, contains('開始校驗書源（199 個）'));
    expect(
      previous.start,
      lessThanOrEqualTo(DateTime.now().millisecondsSinceEpoch),
    );
  });
}
