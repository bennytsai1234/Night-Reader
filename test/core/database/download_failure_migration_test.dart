import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/models/download_task.dart';

import 'legacy_download_tasks_table.dart';

/// 下載失敗的類型、訊息與章節（schema 14）：存在資料庫裡，重開 App 後佇列
/// 的「查看失敗原因」照樣看得到。
void main() {
  test(
    'a schema 13 download queue upgrades with no recorded failure',
    () async {
      final db = AppDatabase.forTesting(
        NativeDatabase.memory(
          setup: (raw) {
            raw.execute(legacyDownloadTasksTable);
            raw.execute(
              'INSERT INTO download_tasks (bookUrl, bookName, status, '
              'errorCount, sortOrder) '
              "VALUES ('a', 'A', 4, 2, 3)",
            );
            raw.execute('PRAGMA user_version = 13');
          },
        ),
      );
      addTearDown(db.close);

      final task = (await DownloadDao(db).getAll()).single;
      expect(task.status, DownloadTask.statusFailed);
      expect(task.errorCount, 2);
      expect(task.sortOrder, 3);
      expect(task.lastErrorReason, isNull);
      expect(task.lastErrorMessage, isNull);
      expect(task.lastErrorChapterIndex, isNull);
    },
  );

  test(
    'a failure is still there after reopening, and a retry clears it',
    () async {
      final dir = Directory.systemTemp.createTempSync('nr-download-failure-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/app.db');

      var db = AppDatabase.forTesting(NativeDatabase(file));
      final task = DownloadTask(bookUrl: 'a', bookName: 'A');
      await DownloadDao(db).upsert(task);
      task
        ..status = DownloadTask.statusFailed
        ..errorCount = 1
        ..setFailure(reason: '網路錯誤', message: '連線逾時', chapterIndex: 2);
      await DownloadDao(db).updateProgress(
        'a',
        status: task.status,
        errorCount: task.errorCount,
        failureOf: task,
      );
      await db.close();

      db = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(() => db.close());
      final reopened = (await DownloadDao(db).getAll()).single;
      expect(reopened.failureSummary, '網路錯誤，第 3 章：連線逾時');

      reopened
        ..status = DownloadTask.statusWaiting
        ..errorCount = 0
        ..clearFailure();
      await DownloadDao(db).updateProgress(
        'a',
        status: reopened.status,
        errorCount: 0,
        failureOf: reopened,
      );
      final retried = (await DownloadDao(db).getAll()).single;
      expect(retried.lastErrorReason, isNull);
      expect(retried.lastErrorMessage, isNull);
      expect(retried.lastErrorChapterIndex, isNull);
    },
  );
}
