import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';

class AppBottomSheet extends StatelessWidget {
  final String title;
  final IconData? icon;
  final List<Widget> children;
  final Widget? trailing;
  final bool showDragHandle;

  const AppBottomSheet({
    super.key,
    required this.title,
    this.icon,
    required this.children,
    this.trailing,
    this.showDragHandle = true,
  });

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle & header — 固定不捲動
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showDragHandle)
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(
                          top: AppSpacing.md,
                          bottom: AppSpacing.xl,
                        ),
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).dividerColor.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      if (icon != null) ...[
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.3),
                            borderRadius: AppRadius.cardMd,
                          ),
                          child: Icon(
                            icon,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Text(
                        title,
                        style: AppTextStyles.titleSm.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      if (trailing != null) trailing!,
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.keyboard_arrow_down, size: 28),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

            // 可捲動的內容區域
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [...children, const SizedBox(height: 24)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 靜態便捷方法：顯示標準底欄
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    IconData? icon,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      builder:
          (ctx) => AppBottomSheet(
            title: title,
            icon: icon,
            trailing: trailing,
            children: children,
          ),
    );
  }
}

/// 底部選單專用的區塊標題
class SheetSection extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SheetSection({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
      child: Row(
        children: [
          Text(
            title,
            style: AppTextStyles.bodyXs.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
