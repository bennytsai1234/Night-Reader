import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import '../source_manager_provider.dart';

class SourceCheckStatusBar extends StatelessWidget {
  final SourceManagerProvider provider;
  final VoidCallback onTap;

  const SourceCheckStatusBar({
    super.key,
    required this.provider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isChecking = provider.checkService.isChecking;
    final report = provider.lastCheckReport;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color:
            isChecking
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                : context.warning.withValues(alpha: 0.08),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child:
                  isChecking
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : Icon(
                        Icons.rule_folder_outlined,
                        size: 16,
                        color: context.warning,
                      ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isChecking
                    ? '正在校驗 (${provider.checkService.currentCount}/${provider.checkService.totalCount}): ${provider.checkService.statusMsg}'
                    : '上次校驗摘要: ${report.summary}',
                style: AppTextStyles.labelSm,
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 16,
              color:
                  isChecking
                      ? Theme.of(context).colorScheme.primary
                      : context.warning,
            ),
            if (isChecking)
              TextButton(
                onPressed: provider.cancelSourceCheck,
                child: const Text('取消'),
              ),
          ],
        ),
      ),
    );
  }
}
