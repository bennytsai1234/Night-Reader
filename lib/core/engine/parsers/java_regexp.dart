/// 書源規則裡的正則照 Java `Pattern` 寫（Legado 直接 `Pattern.compile`）：
/// 預設 `.` 不跨行、`^`／`$` 只對整段頭尾；開頭的 `(?i)`、`(?s)`、`(?m)`、
/// `(?u)` 這類旗標 Dart 不認得，換成 RegExp 的選項。
RegExp javaRegExp(String pattern) {
  final flags = RegExp(r'^\(\?([imsux]+)\)').firstMatch(pattern);
  final options = flags?.group(1) ?? '';
  return RegExp(
    flags == null ? pattern : pattern.substring(flags.end),
    caseSensitive: !options.contains('i'),
    multiLine: options.contains('m'),
    dotAll: options.contains('s'),
    unicode: options.contains('u'),
  );
}
