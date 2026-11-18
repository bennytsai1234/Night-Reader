import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/ui_text.dart';
import 'package:night_reader/core/services/ui_language.dart';
import 'package:flutter/services.dart';

import '../theme/app_chrome.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_tokens.dart';
import 'clause_text.dart';
import 'glass.dart';
import 'popup_routes.dart';
import 'grouped_list.dart';

import 'package:night_reader/shared/widgets/drag_overflow_text.dart';

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
///
/// 標題直接問要做什麼（「刪除 3 本書？」），說明只寫一句後果；做了就回
/// 不去的給 [irreversible]，說明下面另起一行危險色的「無法復原」，說明裡
/// 不再寫一次（docs/design/components.md「選單與提示」）。
Future<T?> showAppAlert<T>({
  required BuildContext context,
  String? title,
  String? message,
  Widget? content,
  required List<AppAlertAction<T>> actions,
  bool irreversible = false,
  bool barrierDismissible = true,
  bool translateTitle = true,
  bool translateMessage = true,
}) {
  return _showAlertRoute<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => AppAlert<T>(
      title: title,
      message: message,
      irreversible: irreversible,
      translateTitle: translateTitle,
      translateMessage: translateMessage,
      content: content,
      actions: actions,
    ),
  );
}

/// 需要自己管理狀態（輸入框、勾選）的置中提示框；外觀與動畫同
/// [showAppAlert]，內容由 [builder] 在 [StatefulBuilder] 內建立。
///
/// 輸入框的控制器由提示框擁有：[fieldTexts] 每一項建立一個控制器，依序傳給
/// [builder]，提示框退場動畫結束、卸載時才釋放。呼叫端不要自行建立並在
/// `await` 之後釋放控制器——Future 在退場動畫開始時就完成，動畫期間輸入框
/// 仍在使用控制器。需要輸入值時在按鈕回呼中讀取，或作為結果 pop 回來。
Future<T?> showStatefulAppAlert<T>({
  required BuildContext context,
  required Widget Function(
    BuildContext context,
    StateSetter setState,
    List<TextEditingController> fields,
  )
  builder,
  List<String> fieldTexts = const [],
  bool barrierDismissible = true,
}) {
  return _showAlertRoute<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => TextControllersScope(
      initialTexts: fieldTexts,
      builder: (context, fields) => StatefulBuilder(
        builder: (context, setState) => builder(context, setState, fields),
      ),
    ),
  );
}

Future<T?> _showAlertRoute<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required bool barrierDismissible,
}) {
  final origin = PopupOrigin.of(context).context;
  final navigator = Navigator.of(origin, rootNavigator: true);
  return navigator.push<T>(
    _AlertRoute<T>(
      barrierThemes: InheritedTheme.capture(
        from: origin,
        to: navigator.context,
      ),
      barrierDismissible: barrierDismissible,
      barrierLabel: UiLanguageText.convert(context, '關閉'),
      barrierColor: AppChrome.of(context).barrier,
      transitionDuration: AppMotion.menu,
      pageBuilder: (context, _, _) => builder(context),
      // 提示框在原地出現，只淡入不縮放；是玻璃，所以由玻璃自己連同模糊一起
      // 淡（ADR 0022）。
      transitionBuilder: (context, animation, _, child) => GlassReveal(
        animation: CurvedAnimation(
          parent: animation,
          curve: AppMotion.fadeCurve,
        ),
        child: child,
      ),
    ),
  );
}

/// 提示框的路由（照 [showGeneralDialog]），遮罩跟著當下主題
/// （[LiveDialogBarrier]）。提示框的內容照 [showGeneralDialog] 不複製打開處
/// 的主題，用 App 的主題。
class _AlertRoute<T> extends RawDialogRoute<T> with LiveDialogBarrier<T> {
  _AlertRoute({
    required this.barrierThemes,
    required super.pageBuilder,
    required super.barrierDismissible,
    required super.barrierLabel,
    required super.barrierColor,
    required super.transitionDuration,
    required super.transitionBuilder,
  });

  @override
  final CapturedThemes barrierThemes;
}

/// 擁有一組輸入框控制器：隨此元件建立，在它卸載時才釋放。
///
/// 對話框與底部面板的 Future 在退場動畫開始時就完成，若在那之後釋放控制器，
/// 退場動畫中的輸入框會使用到已釋放的控制器。把控制器交給路由內的這個元件
/// 擁有即可；[showStatefulAppAlert] 已內建，底部面板可直接包在 builder 外層。
class TextControllersScope extends StatefulWidget {
  const TextControllersScope({
    super.key,
    required this.initialTexts,
    required this.builder,
  });

  /// 每一項建立一個控制器，作為初始文字。
  final List<String> initialTexts;
  final Widget Function(
    BuildContext context,
    List<TextEditingController> controllers,
  )
  builder;

  @override
  State<TextControllersScope> createState() => _TextControllersScopeState();
}

class _TextControllersScopeState extends State<TextControllersScope> {
  late final List<TextEditingController> _controllers = [
    for (final text in widget.initialTexts) TextEditingController(text: text),
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controllers);
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
  bool irreversible = false,
  bool translateTitle = true,
  bool translateMessage = true,
}) async {
  final result = await showAppAlert<bool>(
    context: context,
    title: title,
    message: message,
    irreversible: irreversible,
    translateTitle: translateTitle,
    translateMessage: translateMessage,
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

/// 提示框本體；需要自行管理狀態（例如輸入框）的對話框用
/// [showStatefulAppAlert] 開啟，在其 builder 裡使用。
class AppAlert<T> extends StatelessWidget {
  const AppAlert({
    super.key,
    this.title,
    this.message,
    this.content,
    required this.actions,
    this.onAction,
    this.irreversible = false,
    this.translateTitle = true,
    this.translateMessage = true,
  });

  final String? title;
  final String? message;

  /// 做了就回不去：說明下面另起一行危險色的「無法復原」。
  final bool irreversible;

  /// 標題或說明整段是資料（書源名稱、書源傳來的訊息、網址）時給 false，
  /// 不跟介面語言轉換。句子裡夾著名稱的照介面語言整句轉（ADR 0066）。
  final bool translateTitle;
  final bool translateMessage;
  final Widget? content;
  final List<AppAlertAction<T>> actions;

  /// 覆寫按鈕行為；預設為 `Navigator.pop(value)`。
  final ValueChanged<T>? onAction;

  /// 寬 320：說明是 15 號字，290 時平均多排快半行，三分之一的說明最後
  /// 一行只剩一兩個字（2026-11-18 量 12 則真的說明）。窄手機收到螢幕寬減
  /// 兩側留白。
  static const double _width = 320;

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final horizontal = actions.length <= 2;

    final danger = Theme.of(context).brightness == Brightness.dark
        ? AppPalette.rustDark
        : AppPalette.rust;
    // 提示框裡只有兩種字級：標題與按鈕 17，其餘 15（說明、自訂內容）。
    final bodyStyle = AppTextStyles.bodyBase.copyWith(color: scheme.onSurface);

    Widget actionButton(AppAlertAction<T> action) {
      final color = action.destructive ? danger : scheme.primary;
      return InkWell(
        onTap: action.enabled
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
              child: DragOverflowText(
                child: UiText(
                  action.label,
                  maxLines: 1,
                  style: AppTextStyles.bodyMd.copyWith(
                    height: 1.2,
                    color: color.withValues(alpha: action.enabled ? 1 : 0.4),
                    fontWeight: action.isDefault
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
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
      color: chrome.popupSeparator,
    );

    final buttons = horizontal
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
            tint: chrome.popupTint(0.94),
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
                              child: UiText(
                                title!,
                                translate: translateTitle,
                                textAlign: TextAlign.center,
                                style: AppTextStyles.titleMd.copyWith(
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                          if (message != null) ...[
                            if (title != null)
                              const SizedBox(height: AppSpacing.sm),
                            ClauseText(
                              message!,
                              translate: translateMessage,
                              textAlign: TextAlign.center,
                              style: bodyStyle,
                            ),
                          ],
                          if (irreversible) ...[
                            if (title != null || message != null)
                              const SizedBox(height: AppSpacing.sm),
                            _IrreversibleLine(color: danger),
                          ],
                          if (content != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            DefaultTextStyle.merge(
                              style: bodyStyle,
                              child: content!,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Container(
                    height: AppGlass.hairline,
                    color: chrome.popupSeparator,
                  ),
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

/// 「無法復原」：說明下面獨立一行，危險色、加粗，讓最重要的後果一眼看到。
class _IrreversibleLine extends StatelessWidget {
  const _IrreversibleLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.bodyBase.copyWith(
      color: color,
      fontWeight: FontWeight.w600,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.error_outline_rounded,
          // 圖示和字一樣大，跟著系統字級放大。
          size: MediaQuery.textScalerOf(context).scale(style.fontSize!),
          color: color,
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(child: UiText('無法復原', style: style)),
      ],
    );
  }
}

/// 提示框內的輸入框：分組底色的圓角欄位，沒有外框線。
class AlertTextField extends StatelessWidget {
  const AlertTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.errorText,
    this.onChanged,
    this.autofocus = false,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String? hintText;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final scheme = Theme.of(context).colorScheme;
    const border = OutlineInputBorder(
      borderRadius: AppRadius.cardMd,
      borderSide: BorderSide.none,
    );
    return TextField(
      controller: controller,
      autofocus: autofocus,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      style: AppTextStyles.bodyBase.copyWith(
        height: 1.3,
        color: scheme.onSurface,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: chrome.groupedBackground,
        hintText: UiLanguageText.convertNullable(context, hintText),
        errorText: UiLanguageText.convertNullable(context, errorText),
        hintStyle: AppTextStyles.bodyBase.copyWith(
          height: 1.3,
          color: chrome.sectionText.withValues(alpha: 0.7),
        ),
        // 提示框裡只有 17 與 15 兩種字級；預設的錯誤訊息是 13。
        errorStyle: AppTextStyles.bodyBase.copyWith(
          height: 1.3,
          color: scheme.error,
        ),
        errorMaxLines: 3,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border,
        errorBorder: border,
        focusedErrorBorder: border,
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
  // 面板裡的 MediaQuery 已被移除頂端內距，狀態列高度要先從外層取。
  final topInset = MediaQuery.paddingOf(context).top;
  final origin = PopupOrigin.of(context);
  return pushAppSheet<T>(
    origin: origin,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (context) => origin.wrap(
      _AppActionSheet<T>(
        title: title,
        message: message,
        actions: actions,
        cancelLabel: cancelLabel,
        topInset: topInset,
      ),
    ),
  );
}

class _AppActionSheet<T> extends StatelessWidget {
  const _AppActionSheet({
    required this.title,
    required this.message,
    required this.actions,
    required this.cancelLabel,
    required this.topInset,
  });

  final String? title;
  final String? message;
  final List<AppSheetAction<T>> actions;
  final String cancelLabel;

  /// 外層的狀態列高度；項目很多時卡片頂端才不會頂到狀態列。
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final media = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;
    final hasHeader = title != null || message != null;
    final anySelected = actions.any((a) => a.selected);

    return Padding(
      // 左右和頁面上的卡片、分頁列同一條線。
      padding: EdgeInsets.fromLTRB(
        AppGrouped.margin,
        topInset + AppSpacing.xxxl,
        AppGrouped.margin,
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
              tint: chrome.popupTint(0.94),
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
                              UiText(
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
                              UiText(
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
                          color: chrome.popupSeparator,
                        ),
                      GroupedRow(
                        title: actions[i].label,
                        subtitle: actions[i].subtitle,
                        destructive: actions[i].destructive,
                        enabled: actions[i].enabled,
                        showChevron: false,
                        leading: actions[i].icon == null
                            ? null
                            : Icon(
                                actions[i].icon,
                                size: 22,
                                // 危險項目的圖示和文字同為危險色。
                                color: actions[i].destructive
                                    ? (Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? AppPalette.rustDark
                                          : AppPalette.rust)
                                    : scheme.onSurface.withValues(alpha: 0.8),
                              ),
                        trailing: anySelected
                            ? SizedBox(
                                width: 22,
                                child: actions[i].selected
                                    ? Icon(
                                        Icons.check_rounded,
                                        size: 22,
                                        color: scheme.primary,
                                      )
                                    : null,
                              )
                            : null,
                        onTap: () =>
                            Navigator.of(context).pop(actions[i].value),
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
            tint: chrome.popupTint(0.94),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                child: SizedBox(
                  height: AppGrouped.rowMinHeight + AppSpacing.md,
                  child: Center(
                    child: UiText(
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
