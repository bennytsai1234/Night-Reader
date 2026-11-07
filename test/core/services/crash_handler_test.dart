import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/crash_handler.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('crash_logs');
    CrashHandler.logDirectoryForTesting = () async => directory;
  });

  tearDown(() => directory.delete(recursive: true));

  List<String> crashLogs() =>
      directory
          .listSync()
          .map((file) => file.uri.pathSegments.last)
          .where((name) => name.startsWith('crash-'))
          .toList()
        ..sort();

  test('keeps only the newest 50 crash logs', () async {
    for (var i = 0; i < 55; i++) {
      File(
        '${directory.path}/crash-2026-01-01-00-00-00-'
        '${(1000 + i).toString().padLeft(13, '0')}.log',
      ).writeAsStringSync('old $i');
    }

    await CrashHandler.saveLogForTesting('new error');

    final logs = crashLogs();
    expect(logs, hasLength(50));
    // 最舊的幾份刪掉了，剛寫的那份還在。
    expect(logs, isNot(contains(contains('0000000001000'))));
    expect(await CrashHandler.readLogs(), contains('new error'));
  });
}
