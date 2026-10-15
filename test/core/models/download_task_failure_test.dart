import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/download_task.dart';

void main() {
  DownloadTask failed() =>
      DownloadTask(bookUrl: 'u', bookName: '書')
        ..status = DownloadTask.statusFailed;

  test('a classified failure names the reason, chapter and message', () {
    final task = failed()
      ..setFailure(reason: '網路錯誤', message: '連線逾時', chapterIndex: 2);
    expect(task.failureSummary, '網路錯誤，第 3 章：連線逾時');
  });

  test('the generic reason is not repeated after the status line', () {
    final task = failed()..setFailure(reason: '下載失敗', message: '抓不到目錄');
    expect(task.failureSummary, '抓不到目錄');
  });

  test('nothing recorded means no summary line', () {
    expect(failed().failureSummary, isNull);
  });
}
