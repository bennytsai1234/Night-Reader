import 'package:flutter/material.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/core/services/ui_language.dart';

/// 與 Flutter Text 相容的介面文字：構造參數、const、Text.rich 及 Text 類型
/// 比對全部保留，只在顯示時依介面語言轉換。書籍正文不要使用本元件。
class UiText extends Text {
  const UiText(
    super.data, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
    this.translate = true,
  });

  const UiText.rich(
    super.textSpan, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
    this.translate = true,
  }) : super.rich();

  /// 書名、作者、正文、使用者輸入的文字不應跟著介面語言轉換。
  final bool translate;

  /// 拖曳溢位文字在量測前先拿到與畫面相同的文字。
  Text displayText(BuildContext context) {
    // 字典初始化完成時通知重建；不依賴閱讀偏好目前的轉換方向。
    ChineseDisplay.readyOf(context);
    if (!translate || !UiLanguageScope.isSimplified(context)) {
      return this;
    }
    final dataValue = data;
    final convertedSpan = textSpan;
    final semantics = semanticsLabel == null
        ? null
        : UiLanguageText.toSimplified(semanticsLabel!);
    if (dataValue != null) {
      return Text(
        UiLanguageText.toSimplified(dataValue),
        key: key,
        style: style,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: textDirection,
        locale: locale,
        softWrap: softWrap,
        overflow: overflow,
        textScaler: textScaler,
        maxLines: maxLines,
        semanticsLabel: semantics,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      );
    }
    return Text.rich(
      UiLanguageText.convertSpan(convertedSpan!),
      key: key,
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semantics,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayed = displayText(context);
    return identical(displayed, this) ? super.build(context) : displayed;
  }
}
