import 'dart:io';

import 'package:night_reader/core/services/crash_handler.dart';
import 'package:night_reader/core/services/crash_trail.dart';

/// [seedFullCrashLogs] 寫的 50 份接起來至少這麼多字，測試用它確認資料量
/// 沒有因為崩潰日誌附的內容改了而悄悄縮水。
const int fullCrashLogsMinChars = 1000000;

/// 系統結束日誌裡系統留下的追蹤最多這麼多位元組（`ProcessExits.kt` 的
/// `TRACE_LIMIT`）。
const int _traceLimit = 16 * 1024;

/// 在 [directory]（已經設成 `CrashHandler.logDirectoryForTesting`）寫滿
/// [count] 份崩潰日誌，每份都到最壞的大小：一個 Dart 錯誤，附上塞滿的
/// 動作（30 筆）與錯誤（20 則，每則到長度上限），再帶一段到上限的系統追蹤
/// （沒有回應時的執行緒追蹤就這麼長）。第 i 份（0 最舊）的錯誤訊息是
/// 「錯誤 #i」。在真實時間裡呼叫（元件測試包在 `tester.runAsync` 裡）。
Future<void> seedFullCrashLogs(Directory directory, {int count = 50}) async {
  CrashTrail.resetForTesting();
  for (var i = 0; i < CrashTrail.maxActions; i++) {
    CrashTrail.action('開始校驗書源（120 個）第 $i 次');
  }
  for (var i = 0; i < CrashTrail.maxErrors; i++) {
    CrashTrail.error('書源 isolate 未處理的錯誤: ${'某個書源的規則 JS 丟出的一段很長的錯誤 ' * 30}');
  }
  final stack = [
    for (var i = 0; i < 40; i++)
      '#$i      SomeWidget.build '
          '(package:night_reader/features/x/y_$i.dart:${100 + i}:7)',
  ].join('\n');
  final trace = StringBuffer('\n--- 系統留下的追蹤 ---\n');
  for (var i = 0; trace.length < _traceLimit; i++) {
    trace.writeln(
      '  at com.inkpage.reader.SomeClass.method$i(SomeClass.kt:${100 + i})',
    );
  }
  await CrashHandler.saveLogForTesting('錯誤 #@\n$stack\n$trace');
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
