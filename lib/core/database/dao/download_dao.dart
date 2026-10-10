import 'package:drift/drift.dart';

import '../../models/download_task.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'download_dao.g.dart';

@DriftAccessor(tables: [DownloadTasks])
class DownloadDao extends DatabaseAccessor<AppDatabase>
    with _$DownloadDaoMixin {
  DownloadDao(super.db);

  /// 依佇列順序；同順序（舊版留下的 0）時照加入時間。
  Future<List<DownloadTask>> getAll() {
    return (select(downloadTasks)..orderBy([
          (t) => OrderingTerm.asc(t.sortOrder),
          (t) => OrderingTerm.asc(t.lastUpdateTime),
        ]))
        .get();
  }

  /// 把整個佇列的順序寫回：清單中的位置就是 sortOrder。
  Future<void> saveOrder(List<String> bookUrls) {
    return transaction(() async {
      for (var i = 0; i < bookUrls.length; i++) {
        await (update(downloadTasks)
              ..where((t) => t.bookUrl.equals(bookUrls[i])))
            .write(DownloadTasksCompanion(sortOrder: Value(i)));
      }
    });
  }

  Stream<List<DownloadTask>> watchAll() => select(downloadTasks).watch();

  Future<void> upsert(DownloadTask task) => into(downloadTasks)
      .insertOnConflictUpdate(DownloadTaskToInsertable(task).toInsertable());

  Future<void> deleteByUrl(String bookUrl) =>
      (delete(downloadTasks)..where((t) => t.bookUrl.equals(bookUrl))).go();

  Future<List<DownloadTask>> getUnfinishedTasks() {
    return (select(
      downloadTasks,
    )..where((t) => t.status.equals(0) | t.status.equals(1))).get();
  }

  Future<void> updateProgress(
    String bookUrl, {
    int? status,
    int? currentChapterIndex,
    int? successCount,
    int? errorCount,
  }) {
    return (update(
      downloadTasks,
    )..where((t) => t.bookUrl.equals(bookUrl))).write(
      DownloadTasksCompanion(
        status: status != null ? Value(status) : const Value.absent(),
        currentChapterIndex: currentChapterIndex != null
            ? Value(currentChapterIndex)
            : const Value.absent(),
        successCount: successCount != null
            ? Value(successCount)
            : const Value.absent(),
        errorCount: errorCount != null
            ? Value(errorCount)
            : const Value.absent(),
        lastUpdateTime: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }
}
