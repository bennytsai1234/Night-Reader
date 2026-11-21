import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/diagnostics/crash_trail.dart';

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

  test('errors are kept apart from the logs, and only actions and errors go '
      'into a crash log', () {
    AppLog.e('書源 isolate 未處理的錯誤: StateError');
    AppLog.put('讀快取失敗', error: const FormatException('壞掉的 JSON'));
    for (var i = 0; i < 200; i++) {
      AppLog.d('書源訊息 $i');
    }

    final all = CrashTrail.render();
    expect(all, contains('書源 isolate 未處理的錯誤: StateError'));
    expect(all, contains('讀快取失敗: FormatException: 壞掉的 JSON'));
    expect(all, contains('書源訊息 199'));

    final forCrash = CrashTrail.renderForCrash();
    expect(forCrash, contains('書源 isolate 未處理的錯誤: StateError'));
    expect(forCrash, isNot(contains('書源訊息')));
  });

  test('an error keeps the top of its stack, so it shows where it broke', () {
    AppLog.e(
      '書源校驗失敗 [某書源]',
      error: StateError('壞了'),
      stackTrace: StackTrace.fromString(
        '#0      SourceChecker._run (package:night_reader/a.dart:10:3)\n'
        '#1      SourceChecker.run (package:night_reader/a.dart:20:5)\n'
        '#2      _checkTask (package:night_reader/b.dart:30:7)\n'
        '#3      Worker.run (package:night_reader/c.dart:40:9)\n',
      ),
    );

    final line = CrashTrail.renderForCrash()
        .split('\n')
        .firstWhere((line) => line.contains('書源校驗失敗'));
    expect(line, contains('Bad state: 壞了'));
    expect(line, contains('a.dart:10:3'));
    expect(line, contains('b.dart:30:7'));
    expect(line, isNot(contains('c.dart')));
  });

  test('the logs section is cut from what was stored, old or new layout', () {
    const stored =
        '開啟夜讀：2026-11-18 10:00:00\n\n'
        '--- 最近的動作 ---\n10:00:01 回到前景\n\n'
        '--- 最近的錯誤 ---\n10:00:02 讀快取失敗\n\n'
        '--- 最近的日誌 ---\n10:00:03 書源訊息';
    expect(
      CrashTrail.withoutLogs(stored),
      allOf(contains('回到前景'), contains('讀快取失敗'), isNot(contains('書源訊息'))),
    );
    // 這一版之前存的沒有錯誤那段。
    const old =
        '開啟夜讀：2026-11-18 10:00:00\n\n'
        '--- 最近的動作 ---\n10:00:01 回到前景\n\n'
        '--- 最近的日誌 ---\n10:00:03 書源訊息';
    expect(
      CrashTrail.withoutLogs(old),
      allOf(contains('回到前景'), isNot(contains('書源訊息'))),
    );
  });

  test(
    'the App log shows this time and last time; clearing empties both',
    () async {
      await CrashTrail.start(directory);
      CrashTrail.action('開始校驗書源（199 個）');
      await CrashTrail.flushForTesting();
      CrashTrail.resetForTesting();
      await CrashTrail.start(directory);
      CrashTrail.action('系統播放按了 播放');

      final text = CrashTrail.renderWithPrevious();
      expect(text.indexOf('系統播放按了 播放'), lessThan(text.indexOf('=== 上次開啟 ===')));
      expect(
        text.indexOf('=== 上次開啟 ==='),
        lessThan(text.indexOf('開始校驗書源（199 個）')),
      );

      await CrashTrail.clear();
      expect(CrashTrail.renderWithPrevious(), isEmpty);
      expect(
        File('${directory.path}/${CrashTrail.fileName}').readAsStringSync(),
        isNot(contains('系統播放按了')),
      );
    },
  );

  test('a line that only mentions the logs header does not move the cut', () {
    const stored =
        '開啟夜讀：2026-11-18 10:00:00\n\n'
        '--- 最近的動作 ---\n10:00:01 開始 AI 修復：--- 最近的日誌 --- 書源\n\n'
        '--- 最近的錯誤 ---\n10:00:02 讀快取失敗\n\n'
        '--- 最近的日誌 ---\n10:00:03 書源訊息';
    final cut = CrashTrail.withoutLogs(stored);
    expect(cut, contains('開始 AI 修復：--- 最近的日誌 --- 書源'));
    expect(cut, contains('讀快取失敗'));
    expect(cut, isNot(contains('書源訊息')));
  });

  test('nothing recorded shows no App log, and an empty last time is '
      'not shown as one', () async {
    expect(CrashTrail.renderWithPrevious(), isEmpty);

    await CrashTrail.start(directory);
    await CrashTrail.flushForTesting();
    CrashTrail.resetForTesting();
    await CrashTrail.start(directory);
    expect(CrashTrail.previous, isNull);
    expect(CrashTrail.renderWithPrevious(), isEmpty);
  });

  test('clearing reports a write that did not land', () async {
    await CrashTrail.start(directory);
    CrashTrail.action('開始校驗書源（199 個）');
    await CrashTrail.flushForTesting();
    // 暫存檔的位置被一個資料夾佔著：寫不進去。
    Directory('${directory.path}/${CrashTrail.fileName}.tmp').createSync();

    await expectLater(CrashTrail.clear(), throwsA(isA<FileSystemException>()));
    expect(
      File('${directory.path}/${CrashTrail.fileName}').readAsStringSync(),
      contains('開始校驗書源（199 個）'),
    );
    Directory('${directory.path}/${CrashTrail.fileName}.tmp').deleteSync();
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

  test('the next start reads back when the last session began, in '
      'milliseconds', () async {
    await CrashTrail.start(directory);
    CrashTrail.action('開始校驗書源（199 個）');
    await CrashTrail.flushForTesting();

    CrashTrail.resetForTesting();
    await CrashTrail.start(directory);

    final previous = CrashTrail.previous;
    expect(previous, isNotNull);
    // 崩潰記錄拿它跟系統的毫秒時間比，單位錯了（例如秒）就對不上。
    final now = DateTime.now().millisecondsSinceEpoch;
    expect(
      previous!.start,
      allOf(
        lessThanOrEqualTo(now),
        greaterThan(now - const Duration(hours: 1).inMilliseconds),
      ),
    );
  });
}
