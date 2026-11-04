import 'package:flutter/material.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

/// 「備份與同步」和「同步空間」共用的即時狀態文字。
String? syncStatusSubtitle(SyncStatus status) {
  if (!status.enabled) return null;
  if (status.running) {
    final progress = status.progress;
    if (progress == null) return '同步中…';
    return '同步中（${progress.step}/${progress.total}）：${syncKindLabel(progress.kind)}';
  }
  if (status.error case final error?) return '上次同步失敗：$error';
  final at = status.lastSyncAt;
  if (at == null) return '還沒全面同步過';
  String two(int n) => n.toString().padLeft(2, '0');
  return '上次全面同步：${at.month}/${at.day} ${two(at.hour)}:${two(at.minute)}';
}

/// 一種同步資料給使用者看的名字。
String syncKindLabel(String name) => switch (name) {
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

/// 全面同步進度框的內容：正在同步哪一種、第幾步，與一條進度條（樣子同
/// 更新下載的進度）。
class FullSyncProgress extends StatelessWidget {
  const FullSyncProgress({super.key, required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final progress = status.progress;
    return SyncProgressView(
      value: progress == null ? null : progress.step / progress.total,
      label: progress == null
          ? '準備中…'
          : '${syncKindLabel(progress.kind)}（${progress.step}/${progress.total}）',
    );
  }
}

/// 同步進度框裡的一條進度條與一行說明；[value] 是 null 時進度條來回跑。
/// 全面同步與同步本地書共用。
class SyncProgressView extends StatelessWidget {
  const SyncProgressView({super.key, required this.value, required this.label});

  final double? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: AppRadius.pillShape,
          child: LinearProgressIndicator(
            value: value,
            backgroundColor: AppChrome.of(context).separator,
            minHeight: 4,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          label,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySm.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}
