import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import 'package:night_reader/shared/widgets/glass.dart';

import '../source_manager_provider.dart';

/// 校驗進度／上次校驗摘要的玻璃膠囊，放在導航頁首搜尋框下方。
class SourceCheckStatusBar extends StatelessWidget {
  final SourceManagerProvider provider;
  final VoidCallback onTap;

  const SourceCheckStatusBar({
    super.key,
    required this.provider,
    required this.onTap,
  });

  /// 膠囊高度。
  static const double height = 40;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    final isChecking = provider.checkService.isChecking;
    final report = provider.lastCheckReport;
    final accent = isChecking ? scheme.primary : context.warning;

    return SizedBox(
      height: height,
      child: GlassSurface(
        borderRadius: AppRadius.pillShape,
        shadow: false,
        child: Material(
          type: MaterialType.transparency,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.lg,
                      right: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: isChecking
                              ? CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: accent,
                                )
                              : Icon(
                                  Icons.rule_folder_outlined,
                                  size: 16,
                                  color: accent,
                                ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            isChecking
                                ? '正在校驗 (${provider.checkService.currentCount}/${provider.checkService.totalCount}): ${provider.checkService.statusMsg}'
                                : '上次校驗摘要: ${report.summary}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.uiSm.copyWith(
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: chrome.sectionText,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (isChecking)
                InkWell(
                  onTap: provider.cancelSourceCheck,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        '取消',
                        style: AppTextStyles.uiSm.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
