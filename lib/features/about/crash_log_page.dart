import 'package:flutter/material.dart';
import 'package:night_reader/core/services/crash_handler.dart';

import 'log_page.dart';

/// 崩潰日誌（[CrashHandler] 寫的）：從新到舊，可以複製、分享成檔案或清除。
class CrashLogPage extends StatelessWidget {
  const CrashLogPage({
    super.key,
    this.readLogs,
    this.clearLogs,
    this.writeClipboard,
    this.shareFile,
  });

  final Future<List<String>> Function()? readLogs;
  final Future<void> Function()? clearLogs;
  final Future<void> Function(String text)? writeClipboard;
  final Future<void> Function(String path)? shareFile;

  @override
  Widget build(BuildContext context) => LogPage(
    title: '崩潰日誌',
    emptyTitle: '目前沒有崩潰日誌',
    fileName: '夜讀崩潰日誌',
    readLogs: readLogs ?? CrashHandler.readLogs,
    clearLogs: clearLogs ?? CrashHandler.clearLogs,
    writeClipboard: writeClipboard,
    shareFile: shareFile,
  );
}
