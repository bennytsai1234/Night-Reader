import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/download_task.dart';

void main() {
  DownloadTask failed() =>
      DownloadTask(bookUrl: 'u', bookName: '書')
        ..status = DownloadTask.statusFailed;

  test('a chapter failure names the chapter in the book\'s unit and the '
      'reason', () {
    final task = failed()
      ..setFailure(
        reason: '連不上網站',
        message: '連不上網站，檢查網路後重試或換源',
        chapterIndex: 2,
      );
    expect(task.failureSummary(), '第 3 章：連不上網站，檢查網路後重試或換源');
    expect(task.failureSummary(unit: '話'), '第 3 話：連不上網站，檢查網路後重試或換源');
  });

  test('a failure before any chapter is just the reason', () {
    final task = failed()
      ..setFailure(reason: '書源已刪除', message: '這本書的書源已經刪除，換源');
    expect(task.failureSummary(), '這本書的書源已經刪除，換源');
  });

  test('a row saved by an older version still shows its message', () {
    final task = failed()
      ..setFailure(reason: '下載失敗', message: '發生未預期的錯誤', chapterIndex: 0);
    expect(task.failureSummary(), '第 1 章：發生未預期的錯誤');
  });

  test('nothing recorded means no summary line', () {
    expect(failed().failureSummary(), isNull);
  });
}
