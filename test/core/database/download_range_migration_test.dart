import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/models/download_task.dart';

void main() {
  test('a schema 5 task with a chapter index range upgrades to the whole '
      'book and keeps its state', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          // schema 5 的 download_tasks：範圍是章節序號。
          raw.execute('''
            CREATE TABLE download_tasks (
              bookUrl TEXT NOT NULL PRIMARY KEY,
              bookName TEXT NOT NULL,
              startChapterIndex INTEGER NOT NULL DEFAULT 0,
              endChapterIndex INTEGER NOT NULL DEFAULT 0,
              currentChapterIndex INTEGER NOT NULL DEFAULT 0,
              totalChapterCount INTEGER NOT NULL DEFAULT 0,
              status INTEGER NOT NULL DEFAULT 0,
              successCount INTEGER NOT NULL DEFAULT 0,
              errorCount INTEGER NOT NULL DEFAULT 0,
              addTime INTEGER NOT NULL DEFAULT 0,
              sortOrder INTEGER NOT NULL DEFAULT 0
            )''');
          raw.execute(
            'INSERT INTO download_tasks (bookUrl, bookName, '
            'startChapterIndex, endChapterIndex, totalChapterCount, status, '
            'successCount, addTime, sortOrder) '
            "VALUES ('a', 'A', 10, 20, 11, 2, 4, 123, 7)",
          );
          raw.execute('PRAGMA user_version = 5');
        },
      ),
    );
    addTearDown(db.close);

    final task = (await DownloadDao(db).getAll()).single;

    expect(task.startChapterUrl, isNull);
    expect(task.endChapterUrl, isNull);
    expect(task.status, DownloadTask.statusPaused);
    expect(task.totalCount, 11);
    expect(task.successCount, 4);
    expect(task.lastUpdateTime, 123);
    expect(task.sortOrder, 7);
  });
}
