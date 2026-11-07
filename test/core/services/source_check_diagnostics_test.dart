import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/crash_handler.dart';
import 'package:night_reader/core/services/source_check_diagnostics.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('source_check_diag');
    CrashHandler.logDirectoryForTesting = () async => directory;
  });

  tearDown(() => directory.delete(recursive: true));

  Future<void> recordOne(String name) => SourceCheckDiagnostics.record(
    sourceName: name,
    sourceUrl: 'https://$name.example',
    outcome: '目錄失效',
    entries: ['[目錄] 目錄抓取失敗'],
  );

  test('keeps only the latest check, apart from the crash logs', () async {
    await SourceCheckDiagnostics.begin();
    await recordOne('舊書源');
    await SourceCheckDiagnostics.begin();
    await recordOne('新書源');

    final text = await SourceCheckDiagnostics.read();
    expect(text, contains('[新書源] (https://新書源.example)'));
    expect(text, contains('[目錄] 目錄抓取失敗'));
    expect(text, isNot(contains('舊書源')));
    // 書源的錯誤不寫進崩潰日誌。
    expect(await CrashHandler.readLogs(), isEmpty);
  });

  test('a source without diagnoses writes nothing', () async {
    await SourceCheckDiagnostics.begin();
    await SourceCheckDiagnostics.record(
      sourceName: '正常',
      sourceUrl: 'https://ok.example',
      outcome: '校驗成功',
      entries: const [],
    );

    expect(await SourceCheckDiagnostics.read(), isNot(contains('正常')));
  });
}
