import 'package:flutter/material.dart';
import 'package:night_reader/core/services/crash_handler.dart';
import 'package:night_reader/core/services/crash_trail.dart';

import 'log_page.dart';

/// App 日誌：這次與上次開啟夜讀最近的動作、錯誤與一般日誌（[CrashTrail]），
/// 例如書源的訊息、通知欄播放按了什麼。可以複製、分享成檔案或清除。
class AppLogPage extends StatelessWidget {
  const AppLogPage({super.key});

  @override
  Widget build(BuildContext context) => LogPage(
    title: 'App 日誌',
    emptyTitle: '目前沒有 App 日誌',
    fileName: '夜讀App日誌',
    readLogs: () async =>
        CrashHandler.logChunks(CrashTrail.renderWithPrevious()),
    clearLogs: () async => CrashTrail.clear(),
  );
}
