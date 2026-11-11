import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/crash_handler.dart';
import 'package:night_reader/core/services/crash_trail.dart';
import 'package:night_reader/core/services/process_exits.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Exits implements ProcessExitSource {
  _Exits(this.exits);
  final List<ProcessExit> exits;

  @override
  Future<List<ProcessExit>> recent() async => exits;
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('crash_logs');
    CrashHandler.logDirectoryForTesting = () async => directory;
    CrashTrail.resetForTesting();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    CrashHandler.resetLogDirectoryForTesting();
    // 正在寫的那一次寫完才刪資料夾：Windows 刪不掉開著的檔案。
    await CrashTrail.flushForTesting();
    CrashTrail.resetForTesting();
    await directory.delete(recursive: true);
  });

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

  test(
    'the crash log page shows every kept log, not only the newest 20',
    () async {
      for (var i = 0; i < 25; i++) {
        File(
          '${directory.path}/crash-2026-01-01-00-00-00-'
          '${(1000 + i).toString().padLeft(13, '0')}.log',
        ).writeAsStringSync('log $i');
      }

      final logs = await CrashHandler.readLogs();
      expect(logs, contains('log 0'));
      expect(logs, contains('log 24'));
    },
  );

  test('a Dart error carries what happened just before it', () async {
    CrashTrail.action('開始修復異常書源（3 個）');

    await CrashHandler.saveLogForTesting('boom');

    final logs = await CrashHandler.readLogs();
    expect(logs, contains('boom'));
    expect(logs, contains('開始修復異常書源（3 個）'));
  });

  group('exits the system recorded', () {
    final crashedAt = DateTime(2026, 11, 11, 15, 2, 14);
    final now = DateTime(2026, 11, 11, 16);

    Future<void> leaveTrailOfLastTime() async {
      // 上次開啟留下的紀錄：開啟在崩潰前一分鐘。
      File('${directory.path}/${CrashTrail.fileName}').writeAsStringSync(
        'session ${crashedAt.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch}\n'
        '--- 最近的動作 ---\n15:02:14 按了停止：修復異常書源（做到重新校驗）\n',
      );
      await CrashTrail.start(directory);
    }

    final nativeCrash = ProcessExit(
      timestamp: crashedAt.millisecondsSinceEpoch,
      reason: ProcessExit.reasonCrashNative,
      status: 6,
      importance: 100,
      pssKb: 512 * 1024,
      trace: 'Abort message: pthread_mutex_lock called on a destroyed mutex',
    );

    test('a native crash is written with the trail left before it, '
        'ordinary exits are not', () async {
      await leaveTrailOfLastTime();
      final prefs = await SharedPreferences.getInstance();

      await CrashHandler.recordPreviousExits(
        source: _Exits([
          nativeCrash,
          // 在背景時被系統收掉、使用者從設定強制停止：平常的事，不寫。
          ProcessExit(
            timestamp: crashedAt
                .subtract(const Duration(hours: 1))
                .millisecondsSinceEpoch,
            reason: ProcessExit.reasonLowMemory,
            importance: 400,
          ),
          ProcessExit(
            timestamp: crashedAt
                .subtract(const Duration(hours: 2))
                .millisecondsSinceEpoch,
            reason: 11,
            importance: 100,
          ),
        ]),
        preferences: prefs,
        now: now,
      );

      expect(crashLogs(), hasLength(1));
      final log = await CrashHandler.readLogs();
      expect(log, contains('原生程式崩潰（訊號 6 SIGABRT）'));
      expect(log, contains('當時: 前景'));
      expect(log, contains('destroyed mutex'));
      expect(log, contains('按了停止：修復異常書源'));
      expect(prefs.getInt(CrashHandler.exitsSeenKey), nativeCrash.timestamp);
    });

    test('an exit already written is not written again', () async {
      final prefs = await SharedPreferences.getInstance();
      final source = _Exits([nativeCrash]);

      await CrashHandler.recordPreviousExits(
        source: source,
        preferences: prefs,
        now: now,
      );
      await CrashHandler.recordPreviousExits(
        source: source,
        preferences: prefs,
        now: now,
      );

      expect(crashLogs(), hasLength(1));
    });

    test(
      'an exit that could not be written is written the next time',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final source = _Exits([nativeCrash]);
        CrashHandler.logDirectoryForTesting = () async =>
            throw const FileSystemException('儲存空間暫時不能用');

        await CrashHandler.recordPreviousExits(
          source: source,
          preferences: prefs,
          now: now,
        );
        expect(crashLogs(), isEmpty);

        CrashHandler.logDirectoryForTesting = () async => directory;
        await CrashHandler.recordPreviousExits(
          source: source,
          preferences: prefs,
          now: now,
        );
        expect(crashLogs(), hasLength(1));
        expect(prefs.getInt(CrashHandler.exitsSeenKey), nativeCrash.timestamp);
      },
    );

    test('the first time, exits older than two weeks are left out', () async {
      await CrashHandler.recordPreviousExits(
        source: _Exits([
          ProcessExit(
            timestamp: now
                .subtract(const Duration(days: 15))
                .millisecondsSinceEpoch,
            reason: ProcessExit.reasonAnr,
            importance: 100,
          ),
        ]),
        preferences: await SharedPreferences.getInstance(),
        now: now,
      );

      expect(crashLogs(), isEmpty);
    });

    test('being killed while in use counts; swiping away from recents does '
        'not', () {
      ProcessExit killed({int importance = 125, String? description}) =>
          ProcessExit(
            timestamp: 1,
            reason: ProcessExit.reasonOther,
            importance: importance,
            description: description,
          );
      expect(killed().isReportable, isTrue, reason: '前景服務跑著時被收掉');
      expect(killed(importance: 400).isReportable, isFalse);
      expect(killed(description: 'remove task').isReportable, isFalse);
    });
  });
}
