import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book_source_part.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/core/services/check_source_service.dart';
import 'package:night_reader/shared/theme/context_ext.dart';

import '../source_manager_provider.dart';

class SourceItemTile extends StatelessWidget {
  final BookSourcePart source;
  final SourceManagerProvider provider;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onEdit;
  final VoidCallback onShowMenu;
  final ValueChanged<bool?> onEnabledChanged;
  final int? index;
  final bool showHostHeader;
  final String hostLabel;

  const SourceItemTile({
    super.key,
    required this.source,
    required this.provider,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.onEdit,
    required this.onShowMenu,
    required this.onEnabledChanged,
    this.index,
    this.showHostHeader = false,
    this.hostLabel = '',
  });

  @override
  Widget build(BuildContext context) {
    final canDrag = provider.sortMode == 0 && !provider.groupByDomain;
    final hasStatusDot = source.hasExploreUrl;
    final checkProgress = provider.checkService.progressOf(
      source.bookSourceUrl,
    );
    final errorLine = checkProgress == null ? _errorLine : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHostHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Text(
              hostLabel,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            color:
                isSelected
                    ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.08)
                    : null,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (canDrag && index != null)
                      ReorderableDragStartListener(
                        index: index!,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            top: 10,
                            right: AppSpacing.xs,
                          ),
                          child: Icon(
                            Icons.drag_handle,
                            size: 20,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    GestureDetector(
                      onTap: () => provider.toggleSelect(source.bookSourceUrl),
                      child: Padding(
                        padding: const EdgeInsets.only(
                          top: 10,
                          right: AppSpacing.sm,
                        ),
                        child: Icon(
                          isSelected
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          size: 22,
                          color:
                              isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _displayNameGroup(),
                                  style: AppTextStyles.bodySm.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (hasStatusDot)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Icon(
                                    Icons.circle,
                                    size: 8,
                                    color:
                                        source.enabledExplore
                                            ? context.success
                                            : Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              if (source.runtimeHealth.category !=
                                  SourceHealthCategory.healthy)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: _buildStatusTag(
                                    context,
                                    source.runtimeHealth,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            source.bookSourceUrl,
                            style: AppTextStyles.labelXs.copyWith(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          _buildTags(context),
                          if (checkProgress != null) ...[
                            const SizedBox(height: 6),
                            _buildCheckProgress(context, checkProgress),
                          ],
                          if (errorLine != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              errorLine,
                              style: AppTextStyles.labelXs.copyWith(
                                color: context.warning,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 50,
                      child: Switch(
                        value: source.enabled,
                        onChanged: onEnabledChanged,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    IconButton(
                      tooltip: '編輯',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 20),
                    ),
                    IconButton(
                      tooltip: '更多',
                      onPressed: onShowMenu,
                      icon: const Icon(Icons.more_vert, size: 20),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _displayNameGroup() {
    final group = source.bookSourceGroup;
    if (group != null && group.isNotEmpty) {
      return '${source.bookSourceName} [$group]';
    }
    return source.bookSourceName;
  }

  Widget _buildStatusTag(BuildContext context, SourceRuntimeHealth health) {
    final color =
        health.cleanupCandidate
            ? Theme.of(context).colorScheme.error
            : health.quarantined
            ? context.warning
            : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadius.cardXs,
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        health.label,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTags(BuildContext context) {
    final tags = <String>[];
    if (source.hasSearchUrl) tags.add('搜');
    if (source.hasExploreUrl) tags.add(source.enabledExplore ? '發' : '停發');
    if (source.hasBookInfoRule) tags.add('詳');
    if (source.hasTocRule) tags.add('目');
    if (source.hasContentRule) tags.add('正');

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children:
          tags
              .map(
                (tag) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 9,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
              .toList(),
    );
  }

  Widget _buildCheckProgress(
    BuildContext context,
    SourceCheckProgress progress,
  ) {
    final color =
        progress.isFinal
            ? (progress.hasIssue ? context.warning : context.success)
            : Theme.of(context).colorScheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 6),
          child:
              progress.isFinal
                  ? Icon(
                    progress.hasIssue ? Icons.info_outline : Icons.check_circle,
                    size: 14,
                    color: color,
                  )
                  : SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  ),
        ),
        Expanded(
          child: Text(
            progress.message,
            style: AppTextStyles.labelXs.copyWith(
              color: color,
              fontWeight: progress.isFinal ? FontWeight.w600 : FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String? get _errorLine {
    final comment = source.bookSourceComment?.trim();
    if (comment == null || comment.isEmpty) return null;
    for (final line in comment.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('// Error:')) {
        return trimmed.replaceFirst('// Error:', '').trim();
      }
    }
    return null;
  }
}
