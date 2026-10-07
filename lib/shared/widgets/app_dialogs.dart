import 'package:flutter/material.dart';

import '../theme/app_chrome.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_tokens.dart';
import 'glass.dart';
import 'grouped_list.dart';

/// 提示框的一個按鈕。
class AppAlertAction<T> {
  const AppAlertAction({
    required this.label,
    required this.value,
    this.isDefault = false,
    this.destructive = false,
    this.enabled = true,
  });

  final String label;
  final T value;

  /// 主要動作（加粗）。
  final bool isDefault;
  final bool destructive;
  final bool enabled;
}

/// Telegram 式置中提示框：標題、說明、可選的自訂內容，按鈕以髮絲線分隔。
/// 兩個以內的按鈕橫排，三個以上直排。
Future<T?> showAppAlert<T>({
  required BuildContext context,
  String? title,
  String? message,
  Widget? content,
  required List<AppAlertAction<T>> actions,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: '關閉',
    barrierColor: AppChrome.of(context).barrier,
    transitionDuration: AppMotion.menu,
    pageBuilder:
        (context, _, _) => AppAlert<T>(
          title: title,
          message: message,
          content: content,
          actions: actions,
        ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.springCurve,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: AppMotion.fadeCurve),
        child: ScaleTransition(
          scale: Tween<double>(begin: 1.08, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// 確認類提示框；按下確認回傳 true，取消或點外面回傳 false。
Future<bool> showAppConfirm({
  required BuildContext context,
  required String title,
  String? message,
  Widget? content,
  String confirmLabel = '確定',
  String cancelLabel = '取消',
  bool destructive = false,
}) async {
  final result = await showAppAlert<bool>(
    context: context,
    title: title,
    message: message,
    content: content,
    actions: [
      AppAlertAction(label: cancelLabel, value: false),
      AppAlertAction(
        label: confirmLabel,
        value: true,
        isDefault: !destructive,
        destructive: destructive,
      ),
    ],
  );
  return result ?? false;
}

/// 提示框本體；需要自行管理狀態（例如輸入框）的對話框可直接在
/// `showGeneralDialog`／`showDialog` 的 builder 裡使用。
class AppAlert<T> extends StatelessWidget {
  const AppAlert({
    super.key,
    this.title,
    this.message,
    this.content,
    required this.actions,
    this.onAction,
  });

  final String? title;
  final String? message;
  final Widget? content;
  final List<AppAlertAction<T>> actions;

  /// 覆寫按鈕行為；預設為 `Navigator.pop(value)`。
  final ValueChanged<T>? onAction;

  static const double _width = 290;

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final horizontal = actions.length <= 2;

    Widget actionButton(AppAlertAction<T> action) {
      final color =
          action.destructive
              ? (Theme.of(context).brightness == Brightness.dark
                  ? AppPalette.rustDark
                  : AppPalette.rust)
              : scheme.primary;
      return InkWell(
        onTap:
            action.enabled
                ? () {
                  if (onAction != null) {
                    onAction!(action.value);
                  } else {
                    Navigator.of(context).pop(action.value);
                  }
                }
                : null,
        child: SizedBox(
          height: AppGrouped.rowMinHeight + AppSpacing.xs,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMd.copyWith(
                  height: 1.2,
                  color: color.withValues(alpha: action.enabled ? 1 : 0.4),
                  fontWeight:
                      action.isDefault ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final hairline = Container(
      width: horizontal ? AppGlass.hairline : null,
      height: horizontal ? null : AppGlass.hairline,
      color: chrome.separator,
    );

    final buttons =
        horizontal
            ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) hairline,
                    Expanded(child: actionButton(actions[i])),
                  ],
                ],
              ),
            )
            : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) hairline,
                  actionButton(actions[i]),
                ],
              ],
            );

    return Center(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: media.viewInsets.bottom,
          left: AppSpacing.xxl,
          right: AppSpacing.xxl,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _width,
            maxHeight:
                media.size.height -
                media.viewInsets.bottom -
                media.padding.vertical -
                AppSpacing.xxxl * 2,
          ),
          child: GlassSurface(
            borderRadius: AppRadius.cardXl,
            grouped: false,
            tint: chrome.groupedSurface.withValues(alpha: 0.94),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.xl,
                        AppSpacing.xl,
                        AppSpacing.lg,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (title != null)
                            Semantics(
                              header: true,
                              child: Text(
                                title!,
                                textAlign: TextAlign.center,
                                style: AppTextStyles.titleMd.copyWith(
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                          if (message != null) ...[
                            if (title != null)
                              const SizedBox(height: AppSpacing.sm),
                            Text(
                              message!,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodySm.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                          if (content != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            content!,
                          ],
                        ],
                      ),
                    ),
                  ),
                  Container(height: AppGlass.hairline, color: chrome.separator),
                  buttons,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部動作表的一個動作。
class AppSheetAction<T> {
  const AppSheetAction({
    required this.label,
    required this.value,
    this.icon,
    this.subtitle,
    this.destructive = false,
    this.selected = false,
    this.enabled = true,
  });

  final String label;
  final T value;
  final IconData? icon;
  final String? subtitle;
  final bool destructive;

  /// 單選情境中目前選中的項目，右側打勾。
  final bool selected;
  final bool enabled;
}

/// iOS 式底部動作表：動作卡片＋獨立的「取消」卡片，取代簡單的選擇對話框。
Future<T?> showAppActionSheet<T>({
  required BuildContext context,
  String? title,
  String? message,
  required List<AppSheetAction<T>> actions,
  String cancelLabel = '取消',
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: AppChrome.of(context).barrier,
    builder:
        (context) => _AppActionSheet<T>(
          title: title,
          message: message,
          actions: actions,
          cancelLabel: cancelLabel,
        ),
  );
}

class _AppActionSheet<T> extends StatelessWidget {
  const _AppActionSheet({
    required this.title,
    required this.message,
    required this.actions,
    required this.cancelLabel,
  });

  final String? title;
  final String? message;
  final List<AppSheetAction<T>> actions;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final media = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;
    final hasHeader = title != null || message != null;
    final anySelected = actions.any((a) => a.selected);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        media.padding.top + AppSpacing.xxxl,
        AppSpacing.md,
        media.padding.bottom + AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: GlassSurface(
              borderRadius: AppRadius.cardXl,
              grouped: false,
              tint: chrome.groupedSurface.withValues(alpha: 0.94),
              child: Material(
                type: MaterialType.transparency,
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    if (hasHeader)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                          vertical: AppSpacing.lg,
                        ),
                        child: Column(
                          children: [
                            if (title != null)
                              Text(
                                title!,
                                textAlign: TextAlign.center,
                                style: AppTextStyles.uiSm.copyWith(
                                  color: chrome.sectionText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (message != null) ...[
                              if (title != null)
                                const SizedBox(height: AppSpacing.xs),
                              Text(
                                message!,
                                textAlign: TextAlign.center,
                                style: AppTextStyles.bodySm.copyWith(
                                  color: chrome.sectionText,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0 || hasHeader)
                        Container(
                          height: AppGlass.hairline,
                          color: chrome.separator,
                        ),
                      GroupedRow(
                        title: actions[i].label,
                        subtitle: actions[i].subtitle,
                        destructive: actions[i].destructive,
                        enabled: actions[i].enabled,
                        showChevron: false,
                        leading:
                            actions[i].icon == null
                                ? null
                                : Icon(
                                  actions[i].icon,
                                  size: 22,
                                  color:
                                      actions[i].destructive
                                          ? null
                                          : scheme.onSurface.withValues(
                                            alpha: 0.8,
                                          ),
                                ),
                        trailing:
                            anySelected
                                ? SizedBox(
                                  width: 22,
                                  child:
                                      actions[i].selected
                                          ? Icon(
                                            Icons.check_rounded,
                                            size: 22,
                                            color: scheme.primary,
                                          )
                                          : null,
                                )
                                : null,
                        onTap:
                            () => Navigator.of(context).pop(actions[i].value),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          GlassSurface(
            borderRadius: AppRadius.cardXl,
            grouped: false,
            tint: chrome.groupedSurface.withValues(alpha: 0.94),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                child: SizedBox(
                  height: AppGrouped.rowMinHeight + AppSpacing.md,
                  child: Center(
                    child: Text(
                      cancelLabel,
                      style: AppTextStyles.bodyMd.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
