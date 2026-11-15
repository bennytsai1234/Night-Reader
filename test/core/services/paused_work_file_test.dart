import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/background_work/paused_work_file.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('paused-work'));
  tearDown(() => dir.deleteSync(recursive: true));

  PausedWorkFile file() => PausedWorkFile('job', directory: () async => dir);

  test('the last save is what a fresh start reads back', () async {
    final first = file()
      ..save('第 1 輪')
      ..save('第 2 輪')
      ..save('第 3 輪');
    await first.flush();
    expect(await file().read(), '第 3 輪');
    expect(dir.listSync().map((e) => e.uri.pathSegments.last), [
      'job.json',
    ], reason: '暫存檔改名後不留');
  });

  test('nothing saved reads as null', () async {
    expect(await file().read(), isNull);
  });

  test('after close the save is gone and a late save does not bring it '
      'back', () async {
    final job = file()..save('第 1 輪');
    await job.flush();
    job.save('第 2 輪');
    await job.close();
    job.save('第 3 輪');
    await job.flush();
    expect(job.isClosed, isTrue);
    expect(await file().read(), isNull);
    expect(dir.listSync(), isEmpty);
  });
}
