import 'package:flutter/widgets.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/core/services/chinese_display.dart';

/// App 固定介面文字使用的繁簡，不影響書籍正文的繁簡轉換。
///
/// [locale] 是使用者選的介面語言，null 表示跟隨系統；非中文系統用繁體。
/// 跟隨系統時每次建立都重新看系統語言：系統語言改了 MaterialApp 會重建
/// builder，這裡跟著換，介面文字只在繁簡真的變了時重建。
class UiLanguageScope extends InheritedWidget {
  UiLanguageScope({super.key, required Locale? locale, required super.child})
    : simplified = prefersSimplified(
        locale ?? WidgetsBinding.instance.platformDispatcher.locale,
      );

  /// 介面文字顯示簡體。
  final bool simplified;

  static bool isSimplified(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<UiLanguageScope>()
          ?.simplified ??
      prefersSimplified(WidgetsBinding.instance.platformDispatcher.locale);

  @override
  bool updateShouldNotify(UiLanguageScope oldWidget) =>
      simplified != oldWidget.simplified;
}

/// 偏好設定存的介面語言（`system`、`zh_TW`、`zh_CN`）現在是不是簡體；
/// 開 App 建第一幀之前、還沒有 [UiLanguageScope] 時用。
bool languagePrefIsSimplified(String? pref) => switch (pref) {
  'zh_CN' => true,
  'zh_TW' => false,
  _ => prefersSimplified(WidgetsBinding.instance.platformDispatcher.locale),
};

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

/// 介面固定字（標籤、單位、預設字）和書的資料拼在同一段字、那段字設了
/// `translate: false` 時，固定字用 [ui] 照介面語言，資料用 `zh` 照閱讀偏好
/// （ADR 0066）。
extension UiLanguageContext on BuildContext {
  String ui(String text) => UiLanguageText.convert(this, text);
}

/// 「最新：章名」：標籤與沒有章名時的 [fallback] 照介面語言，章名照閱讀
/// 偏好的繁簡轉換（ADR 0066）。整段用 `translate: false` 顯示。
String latestChapterLine(
  BuildContext context,
  String? title, {
  required String fallback,
}) {
  final trimmed = title?.trim();
  final value = trimmed == null || trimmed.isEmpty
      ? context.ui(fallback)
      : context.zh(trimmed);
  return '${context.ui('最新：')}$value';
}

/// 只轉換 App 的固定介面文字；書籍內容依閱讀偏好的繁簡轉換設定。
abstract final class UiLanguageText {
  static final Map<String, String> _simplified = <String, String>{};
  static const int _maxEntries = 4096;

  /// 介面是簡體時才登記字典載入完成時重建；繁體介面不轉換，閱讀偏好的
  /// 繁簡轉換改了也不必重建介面文字。
  static String convert(BuildContext context, String text) {
    if (!UiLanguageScope.isSimplified(context)) return text;
    ChineseDisplay.readyOf(context);
    return toSimplified(text);
  }

  static String? convertNullable(BuildContext context, String? text) =>
      text == null ? null : convert(context, text);

  static String toSimplified(String text) {
    if (text.isEmpty || !ChineseUtils.isInitialized) return text;
    final cached = _simplified.remove(text);
    if (cached != null) return _simplified[text] = cached;
    final converted = ChineseUtils.t2s(text);
    _simplified[text] = converted;
    if (_simplified.length > _maxEntries) {
      _simplified.remove(_simplified.keys.first);
    }
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
