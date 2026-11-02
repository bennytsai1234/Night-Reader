import 'package:night_reader/core/sync/sync_service.dart';

/// 「備份與同步」和「同步空間」共用的即時狀態文字。
String? syncStatusSubtitle(SyncStatus status) {
  if (!status.enabled) return null;
  if (status.running) {
    final progress = status.progress;
    if (progress == null) return '同步中…';
    return '同步中（${progress.step}/${progress.total}）：${_kindLabel(progress.kind)}';
  }
  if (status.error case final error?) return '上次同步失敗：$error';
  final at = status.lastSyncAt;
  if (at == null) return '還沒同步過';
  String two(int n) => n.toString().padLeft(2, '0');
  return '上次同步：${at.month}/${at.day} ${two(at.hour)}:${two(at.minute)}';
}

String _kindLabel(String name) => switch (name) {
  'progress' => '閱讀進度',
  'sources' => '書源',
  'replace_rules' => '替換規則',
  'bookshelf' => '書架',
  'bookmarks' => '書籤',
  'highlights' => '標註',
  'read_stats' => '閱讀統計',
  'settings' => '設定',
  'login_cache' || 'login_cookies' || 'login_cookie_jar' => '登入資料',
  _ => '資料',
};
