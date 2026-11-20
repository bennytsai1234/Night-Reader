import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/chinese/ui_language.dart';
import '../../theme/app_chrome.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../skeleton/grouped_list_skeleton.dart';
import '../skeleton/skeleton.dart';
import '../text/ui_text.dart';

/// 分組卡片內的單行輸入列（Telegram ItemListSingleLineInputItem）。
class GroupedTextFieldRow extends StatelessWidget
    implements GroupedSkeletonItem {
  const GroupedTextFieldRow({
    super.key,
    this.label,
    this.controller,
    this.hintText,
    this.onChanged,
    this.keyboardType,
    this.maxLines = 1,
    this.minLines,
    this.style,
    this.autofocus = false,
    this.obscureText = false,
    this.suffix,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
    this.labelWidth = 96,
    this.validator,
    this.errorText,
  });

  /// 左側固定標籤；為 null 時輸入框佔滿整列。
  final String? label;

  /// 標籤欄寬度。
  final double labelWidth;

  /// 放在 [Form] 內時的驗證；提供時改用 [TextFormField]，錯誤文字顯示在
  /// 輸入框下方。
  final FormFieldValidator<String>? validator;

  /// 外部指定的錯誤文字（不經 [Form] 驗證時使用）。
  final String? errorText;
  final TextEditingController? controller;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final int? maxLines;
  final int? minLines;
  final TextStyle? style;
  final bool autofocus;
  final bool obscureText;
  final Widget? suffix;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  static final TextStyle _labelStyle = AppTextStyles.bodyBase.copyWith(
    height: 1.3,
  );

  static final TextStyle _hintStyle = AppTextStyles.bodyBase.copyWith(
    height: 1.3,
  );

  /// 標籤照字排在左欄，輸入框見 [groupedTextFieldShape]。
  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) {
    final labelWidth = this.label == null ? 0.0 : this.labelWidth;
    final fieldWidth = width - AppGrouped.rowPadding * 2 - labelWidth;
    final suffixWidth = switch (suffix) {
      final suffix? => groupedInputSuffixExtent(suffix),
      null => 0.0,
    };
    final field = groupedTextFieldShape(
      context,
      style: _textStyle(context),
      width: fieldWidth - suffixWidth,
      text: controller?.text ?? '',
      hint: hintText,
      hintStyle: _hintStyle,
      maxLines: _maxLines,
      minLines: minLines,
    );
    final label = switch (this.label) {
      final text? => GroupedItemShape.text(
        context,
        text,
        style: _labelStyle,
        width: labelWidth,
      ),
      null => null,
    };
    // 輸入框上下各有內距，右側的 [suffix] 把輸入框撐到至少和它一樣高。單行
    // 的標籤與字置中在列裡；多行的靠上，標籤對齊第一行（上方內距）。
    final box = math.max(field.height + AppSpacing.md * 2, suffixWidth);
    final height = math.max(
      AppGrouped.rowMinHeight,
      math.max(box, AppSpacing.md + (label?.height ?? 0)),
    );
    final single = _single;
    double top(GroupedItemShape part) =>
        single ? (height - part.height) / 2 : AppSpacing.md;
    return GroupedItemShape(
      height,
      marks: [
        ...?label?.marksAt(Offset(AppGrouped.rowPadding, top(label))),
        ...field.marksAt(
          Offset(AppGrouped.rowPadding + labelWidth, top(field)),
        ),
        if (suffix case final suffix?)
          ...groupedInputSuffixShape(context, suffix, height: box).marksAt(
            Offset(
              AppGrouped.rowPadding + labelWidth + fieldWidth - suffixWidth,
              0,
            ),
          ),
      ],
    );
  }

  /// 輸入框實際的最多行數（密碼只有一行）；骨架與 build 共用。
  int? get _maxLines => obscureText ? 1 : maxLines;

  /// 只有一行的輸入框：標籤與字置中在列裡，列被右側按鈕撐高時也對著按鈕。
  bool get _single => _maxLines == 1;

  TextStyle _textStyle(BuildContext context) => groupedInputStyle(
    context,
    style ??
        AppTextStyles.bodyBase.copyWith(
          height: 1.3,
          color: Theme.of(context).colorScheme.onSurface,
        ),
  );

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final scheme = Theme.of(context).colorScheme;
    final decoration = InputDecoration(
      isDense: true,
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      errorText: UiLanguageText.convertNullable(context, errorText),
      contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      hintText: UiLanguageText.convertNullable(context, hintText),
      hintStyle: _hintStyle.copyWith(
        color: chrome.sectionText.withValues(alpha: 0.7),
      ),
      suffixIcon: suffix,
      suffixIconConstraints: const BoxConstraints(
        minWidth: AppGrouped.rowMinHeight,
        minHeight: AppGrouped.rowMinHeight,
      ),
    );
    final effectiveStyle = _textStyle(context);
    final effectiveMaxLines = _maxLines;
    final single = _single;
    final verticalAlign = single ? TextAlignVertical.center : null;
    final field = validator == null
        ? TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            maxLines: effectiveMaxLines,
            minLines: minLines,
            autofocus: autofocus,
            obscureText: obscureText,
            style: effectiveStyle,
            textAlignVertical: verticalAlign,
            decoration: decoration,
          )
        : TextFormField(
            controller: controller,
            focusNode: focusNode,
            validator: validator,
            onChanged: onChanged,
            onFieldSubmitted: onSubmitted,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            maxLines: effectiveMaxLines,
            minLines: minLines,
            autofocus: autofocus,
            obscureText: obscureText,
            style: effectiveStyle,
            textAlignVertical: verticalAlign,
            decoration: decoration,
          );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppGrouped.rowMinHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppGrouped.rowPadding),
        child: label == null
            ? field
            : Row(
                crossAxisAlignment: single
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: single ? 0 : AppSpacing.md),
                    child: SizedBox(
                      width: labelWidth,
                      child: UiText(
                        label!,
                        style: _labelStyle.copyWith(color: scheme.onSurface),
                      ),
                    ),
                  ),
                  Expanded(child: field),
                ],
              ),
      ),
    );
  }
}

/// [TextField] 實際用的字樣：先合併 Material 的輸入字體再套 [style]；骨架
/// 也從這份字體量行高，不能只用字號乘行高（不同字體的 strut 會得到不同
/// 整數行高）。
TextStyle groupedInputStyle(BuildContext context, TextStyle style) {
  final theme = Theme.of(context);
  return (theme.useMaterial3
          ? theme.textTheme.bodyLarge!
          : theme.textTheme.titleMedium!)
      .merge(style);
}

/// 輸入框裡字的那一塊（不含輸入框的內距）。行數固定（最少與最多一樣）的
/// 框只看行數，每一行撐滿一條：字可能之後才填進來；行數會變的框照現在的
/// 字 [text] 排，畫框裡會顯示的字（沒字時是提示字 [hint]）。[style] 是
/// [groupedInputStyle] 合併過的字樣。
GroupedItemShape groupedTextFieldShape(
  BuildContext context, {
  required TextStyle style,
  required double width,
  required String text,
  String? hint,
  TextStyle? hintStyle,
  int? maxLines,
  int? minLines,
}) {
  final scaler = MediaQuery.textScalerOf(context);
  final fixed = maxLines != null && (minLines ?? 1) == maxLines;
  final painter = TextPainter(
    text: TextSpan(text: fixed ? '' : text, style: style),
    strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
    textScaler: scaler,
    textDirection: Directionality.of(context),
  )..layout(maxWidth: math.max(0, width));
  final line = painter.preferredLineHeight;
  final fontSize = scaler.scale(
    style.fontSize ?? AppTextStyles.bodyBase.fontSize!,
  );
  final lower = line * (minLines ?? maxLines ?? 1);
  final upper = maxLines == null ? double.infinity : line * maxLines;
  final height = fixed ? line * maxLines : painter.height.clamp(lower, upper);
  painter.dispose();
  if (fixed && minLines != null) {
    // 指定了固定行數的框，字之後才填進來：每一行撐滿一條。
    return GroupedItemShape(
      height,
      marks: [
        for (var i = 0; i < maxLines; i++)
          SkeletonShape(
            Rect.fromLTWH(0, i * line + (line - fontSize) / 2, width, fontSize),
          ),
      ],
    );
  }
  // 照框裡會顯示的字畫：有字畫字，沒字畫提示字（提示字的行高不同，置中在
  // 輸入的那一行上）。
  final shown = switch ((text, hint)) {
    (final text, _) when text.isNotEmpty => GroupedItemShape.text(
      context,
      text,
      style: style,
      width: width,
      maxLines: maxLines,
      strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
      ellipsized: true,
    ),
    (_, final hint?) when hint.isNotEmpty => () {
      final shape = GroupedItemShape.text(
        context,
        hint,
        style: style.merge(hintStyle),
        width: width,
        maxLines: maxLines,
        ellipsized: true,
      );
      return GroupedItemShape(
        shape.height,
        marks: shape.marksAt(Offset(0, (line - shape.height) / 2)),
      );
    }(),
    _ => null,
  };
  return GroupedItemShape(height, marks: shown?.marks ?? const []);
}

/// 輸入框右側的 [suffix]（[InputDecoration.suffixIcon]）佔的見方：至少
/// [AppGrouped.rowMinHeight]，圖示按鈕照它的點擊範圍。輸入框至少有這麼高。
double groupedInputSuffixExtent(Widget suffix) => switch (suffix) {
  PasswordRevealButton() => PasswordRevealButton.extent,
  _ => AppGrouped.rowMinHeight,
};

/// 輸入框右側的 [suffix] 在高 [height] 的輸入框裡的骨架：置中在它佔的那
/// 一格（[groupedInputSuffixExtent]）。
GroupedItemShape groupedInputSuffixShape(
  BuildContext context,
  Widget suffix, {
  required double height,
}) {
  final part = groupedPartShape(suffix, context);
  final width = groupedInputSuffixExtent(suffix);
  return GroupedItemShape(
    height,
    width: width,
    marks: part.marksAt(
      Offset((width - (part.width ?? width)) / 2, (height - part.height) / 2),
    ),
  );
}

/// 密碼框右側顯示／隱藏密碼的眼睛鈕，放在 [InputDecoration.suffixIcon]。
class PasswordRevealButton extends StatelessWidget {
  const PasswordRevealButton({
    super.key,
    required this.revealed,
    required this.onPressed,
  });

  /// 密碼現在看得到。
  final bool revealed;
  final VoidCallback onPressed;

  static const double iconSize = 18;

  /// 點擊範圍（[IconButton] 的最小可點範圍），也是它在輸入框裡佔的見方。
  static const double extent = kMinInteractiveDimension;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: UiLanguageText.convert(context, revealed ? '隱藏密碼' : '顯示密碼'),
    onPressed: onPressed,
    icon: Icon(
      revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      size: iconSize,
      color: AppChrome.of(context).sectionText,
    ),
  );
}
