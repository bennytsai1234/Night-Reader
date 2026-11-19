import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';
import 'package:night_reader/core/background_work/background_work.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import 'package:night_reader/shared/widgets/glass/glass.dart';

import '../source_check_job.dart';
import '../source_manager_provider.dart';

import 'package:night_reader/shared/widgets/text/drag_overflow_text.dart';

/// 「已暫停，校驗了 37／199 個」：校驗膠囊與校驗詳情用同一句。
String sourceCheckPausedText(SourceCheckPlan plan) =>
    '已暫停，校驗了 ${plan.finished.length}／${plan.urls.length} 個';

/// 校驗進度／上次校驗摘要的玻璃膠囊，放在導航頁首搜尋框下方。一直在
/// （ADR 0059）：還沒校驗過時寫「還沒校驗過」，[onTap] 為 null、灰掉。
/// 右側兩顆鈕（使用者 2026-11-15 在候選圖上選的甲）：校驗中「暫停｜結束」，
/// 暫停中「繼續｜結束」，其他時候「暫停｜結束」灰掉（ADR 0058）。
class SourceCheckStatusBar extends StatelessWidget {
  final SourceManagerProvider provider;
  final VoidCallback? onTap;

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
    final job = SourceCheckJob.current;
    // 按了暫停或結束、還沒停好：校驗服務已經不派新的書源，但這次校驗還沒
    // 停好，照校驗中畫，寫「正在暫停…」「正在結束…」，正在暫停時還能按結束。
    final settling = job != null && job.phase.settling;
    final isChecking = provider.checkService.isChecking || settling;
    final paused = isChecking ? null : provider.pausedCheck.plan;
    final report = provider.lastCheckReport;
    final accent = isChecking ? scheme.primary : context.warning;
    final idle = onTap == null;

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
                  child: Opacity(
                    opacity: idle ? AppDisabled.opacity : 1,
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
                                : paused != null
                                ? Icon(
                                    Icons.pause_circle_outline_rounded,
                                    size: 16,
                                    color: chrome.sectionText,
                                  )
                                : Icon(
                                    Icons.rule_folder_outlined,
                                    size: 16,
                                    color: idle ? scheme.onSurface : accent,
                                  ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: DragOverflowText(
                              child: UiText(
                                isChecking
                                    // statusMsg 已經是「正在校驗: 書源名」，前面只補進度。
                                    ? '(${provider.checkService.currentCount}/${provider.checkService.totalCount}) ${settling ? (job.isEnding ? backgroundWorkEnding : backgroundWorkPausing) : provider.checkService.statusMsg}'
                                    : paused != null
                                    ? sourceCheckPausedText(paused)
                                    : idle
                                    ? '還沒校驗過'
                                    : '上次校驗摘要: ${report.summary}',
                                maxLines: 1,
                                style: AppTextStyles.uiSm.copyWith(
                                  color: scheme.onSurface,
                                ),
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
              ),
              _CapsuleButton(
                label: paused != null ? '繼續' : '暫停',
                color: scheme.primary,
                onTap: paused != null
                    ? (provider.canResumeSourceCheck
                          ? () => unawaited(provider.resumeSourceCheck())
                          : null)
                    // 整批修復的重新校驗、登入完的自動校驗不是背景工作，不能暫停。
                    : (job != null && !settling
                          ? provider.pauseSourceCheck
                          : null),
              ),
              Container(width: 0.5, height: 16, color: chrome.sectionText),
              _CapsuleButton(
                label: '結束',
                color: context.danger,
                onTap:
                    (isChecking && !(job?.isEnding ?? false)) || paused != null
                    ? provider.endSourceCheck
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 膠囊右邊的一顆文字鈕；不能按時換成中性灰（ADR 0059、[AppDisabled]）。
class _CapsuleButton extends StatelessWidget {
  const _CapsuleButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Center(
        widthFactor: 1,
        child: UiText(
          label,
          style: AppTextStyles.uiSm.copyWith(
            color: context.actionColor(color, enabled: onTap != null),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}
