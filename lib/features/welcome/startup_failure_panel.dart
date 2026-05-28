import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader/features/about/crash_log_page.dart';
import 'package:reader/shared/theme/app_tokens.dart';

class StartupFailurePanel extends StatelessWidget {
  const StartupFailurePanel({
    super.key,
    required this.details,
    required this.onRetry,
    this.title = '啟動失敗',
    this.message = '初始化沒有完成，請重試或查看錯誤詳情。',
  });

  final String title;
  final String message;
  final String details;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.88),
        borderRadius: AppRadius.cardLg,
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重試'),
              ),
              OutlinedButton.icon(
                onPressed: () => _showDetails(context),
                icon: const Icon(Icons.article_outlined),
                label: const Text('詳情'),
              ),
              OutlinedButton.icon(
                onPressed: () => _copyDetails(context),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('複製'),
              ),
              TextButton.icon(
                onPressed:
                    () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CrashLogPage()),
                    ),
                icon: const Icon(Icons.report_problem_outlined),
                label: const Text('崩潰日誌'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('錯誤詳情'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: SelectableText(
                  details,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('關閉'),
              ),
            ],
          ),
    );
  }

  Future<void> _copyDetails(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: details));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已複製錯誤詳情')));
  }
}
