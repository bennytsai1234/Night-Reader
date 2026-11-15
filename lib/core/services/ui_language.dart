import 'package:flutter/widgets.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/core/services/chinese_display.dart';

/// App 固定介面文字使用的繁簡，不影響書籍正文的繁簡轉換。
///
/// null 表示跟隨裝置語言；非中文系統預設保留繁體中文。
class UiLanguageScope extends InheritedWidget {
  const UiLanguageScope({
    super.key,
    required this.locale,
    required super.child,
  });

  final Locale? locale;

  static bool isSimplified(BuildContext context) {
    final chosen = context
        .dependOnInheritedWidgetOfExactType<UiLanguageScope>()
        ?.locale;
    return prefersSimplified(
      chosen ?? WidgetsBinding.instance.platformDispatcher.locale,
    );
  }

  @override
  bool updateShouldNotify(UiLanguageScope oldWidget) =>
      locale != oldWidget.locale;
}

bool prefersSimplified(Locale locale) {
  if (locale.languageCode.toLowerCase() != 'zh') return false;
  final script = locale.scriptCode?.toLowerCase();
  if (script == 'hans') return true;
  if (script == 'hant') return false;
  switch (locale.countryCode?.toUpperCase()) {
    case 'CN':
    case 'SG':
    case 'MY':
      return true;
    default:
      return false;
  }
}

/// 只轉換 App 的固定介面文字；書籍內容依閱讀偏好的繁簡轉換設定。
abstract final class UiLanguageText {
  static final Map<String, String> _simplified = <String, String>{};
  static const int _maxEntries = 4096;

  static String convert(BuildContext context, String text) {
    ChineseDisplay.readyOf(context);
    return UiLanguageScope.isSimplified(context) ? toSimplified(text) : text;
  }

  static String? convertNullable(BuildContext context, String? text) =>
      text == null ? null : convert(context, text);

  static String toSimplified(String text) {
    if (text.isEmpty || !ChineseUtils.isInitialized) return text;
    final cached = _simplified.remove(text);
    if (cached != null) return _simplified[text] = cached;
    final converted = ChineseUtils.t2s(text);
    _simplified[text] = converted;
    if (_simplified.length > _maxEntries)
      _simplified.remove(_simplified.keys.first);
    return converted;
  }

  static InlineSpan convertSpan(InlineSpan span) {
    if (span is! TextSpan) return span;
    return TextSpan(
      text: span.text == null ? null : toSimplified(span.text!),
      children: span.children?.map(convertSpan).toList(growable: false),
      style: span.style,
      recognizer: span.recognizer,
      mouseCursor: span.mouseCursor,
      onEnter: span.onEnter,
      onExit: span.onExit,
      semanticsLabel: span.semanticsLabel == null
          ? null
          : toSimplified(span.semanticsLabel!),
      locale: span.locale,
      spellOut: span.spellOut,
    );
  }
}
