import 'dart:io';

import 'package:night_reader/core/services/crash_handler.dart';
import 'package:night_reader/core/services/crash_trail.dart';

/// 在 [directory]（已經設成 `CrashHandler.logDirectoryForTesting`）寫滿
/// [count] 份崩潰日誌：每份是一個 Dart 錯誤，附上塞滿的崩潰前紀錄（動作
/// 30 筆、日誌 60 則，每則到長度上限），同書源校驗時規則 JS 印滿訊息的樣子。
/// 第 i 份（0 最舊）的錯誤訊息是「錯誤 #i」。在真實時間裡呼叫（元件測試
/// 包在 `tester.runAsync` 裡）。
Future<void> seedFullCrashLogs(Directory directory, {int count = 50}) async {
  CrashTrail.resetForTesting();
  for (var i = 0; i < CrashTrail.maxActions; i++) {
    CrashTrail.action('開始校驗書源（120 個）第 $i 次');
  }
  for (var i = 0; i < CrashTrail.maxLogs; i++) {
    CrashTrail.log('書源訊息: ${'某個書源的規則 JS 印出的一段很長的訊息 ' * 30}');
  }
  final stack = [
    for (var i = 0; i < 40; i++)
      '#$i      SomeWidget.build '
          '(package:night_reader/features/x/y_$i.dart:${100 + i}:7)',
  ].join('\n');
  await CrashHandler.saveLogForTesting('錯誤 #@\n$stack');
  final template = directory.listSync().whereType<File>().firstWhere(
    (file) => file.uri.pathSegments.last.startsWith('crash-'),
  );
  final text = await template.readAsString();
  await template.delete();
  for (final name in ['crash_log.txt', CrashTrail.fileName]) {
    final file = File('${directory.path}/$name');
    if (await file.exists()) await file.delete();
  }
  for (var i = 0; i < count; i++) {
    await File(
      '${directory.path}/crash-2026-11-01-00-00-00-'
      '${(1700000000000 + i).toString().padLeft(13, '0')}.log',
    ).writeAsString(text.replaceFirst('錯誤 #@', '錯誤 #$i'));
  }
  CrashTrail.resetForTesting();
}
