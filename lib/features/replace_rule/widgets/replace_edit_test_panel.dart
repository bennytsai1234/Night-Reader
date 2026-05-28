import 'package:flutter/material.dart';
import 'package:reader/shared/theme/app_tokens.dart';
import 'package:reader/shared/theme/app_text_styles.dart';
import 'package:reader/shared/theme/context_ext.dart';

class ReplaceEditTestPanel extends StatelessWidget {
  final TextEditingController testInputCtrl;
  final String testResult;

  const ReplaceEditTestPanel({
    super.key,
    required this.testInputCtrl,
    required this.testResult,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
        borderRadius: AppRadius.cardSm,
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bug_report, size: 18, color: context.warning),
              const SizedBox(width: 8),
              const Text('規則調試', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: testInputCtrl,
            decoration: const InputDecoration(
              labelText: '測試文字',
              hintText: '請輸入要測試的內容',
              isDense: true,
            ),
            maxLines: 3,
            style: AppTextStyles.bodyXs,
          ),
          const SizedBox(height: 12),
          Text(
            '替換結果:',
            style: AppTextStyles.labelSm.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.05),
              borderRadius: AppRadius.cardXs,
            ),
            child: Text(
              testResult.isEmpty ? '(無結果)' : testResult,
              style: AppTextStyles.bodyXs.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
