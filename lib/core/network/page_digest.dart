/// 給 AI 看的網頁：拿掉 `<head>`、程式、樣式、圖形與註解，標籤只留規則會用到
/// 的屬性（class、id、連結與圖片網址、表單欄位），空白合成一格。書源規則選的
/// 是內文的結構，這些拿掉之後同樣的字數看得到的內文多好幾倍。不像 HTML 的
/// （JSON、純文字）照原樣。
String digestPage(String text) {
  final trimmed = text.trimLeft();
  if (!trimmed.startsWith('<')) return _collapse(text);
  var html = text
      .replaceAll(_comment, '')
      .replaceAll(_head, '')
      .replaceAll(_dropBlocks, '')
      .replaceAll(_dropTags, '');
  html = html.replaceAllMapped(_openTag, (match) {
    final attributes = match.group(2);
    if (attributes == null || attributes.trim().isEmpty) return match.group(0)!;
    final kept = [
      for (final attribute in _attribute.allMatches(attributes))
        if (_keptAttributes.contains(attribute.group(1)!.toLowerCase()))
          '${attribute.group(1)}=${_shorten(attribute.group(2)!)}',
    ];
    final close = match.group(3) ?? '';
    return kept.isEmpty
        ? '<${match.group(1)}$close>'
        : '<${match.group(1)} ${kept.join(' ')}$close>';
  });
  return _collapse(html);
}

String _collapse(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// 屬性值太長（內嵌圖片、整段資料）只留開頭。
String _shorten(String quoted) =>
    quoted.length <= 120 ? quoted : '${quoted.substring(0, 100)}…${quoted[0]}';

final RegExp _comment = RegExp(r'<!--.*?-->', dotAll: true);
final RegExp _head = RegExp(
  r'<head\b[^>]*>.*?</head>',
  dotAll: true,
  caseSensitive: false,
);
final RegExp _dropBlocks = RegExp(
  r'<(script|style|svg|noscript|template)\b[^>]*>.*?</\1\s*>',
  dotAll: true,
  caseSensitive: false,
);
final RegExp _dropTags = RegExp(
  r'<(meta|link|base)\b[^>]*>',
  caseSensitive: false,
);
final RegExp _openTag = RegExp(r'<([a-zA-Z][a-zA-Z0-9-]*)(\s[^<>]*?)?(/?)>');
final RegExp _attribute = RegExp(
  r'''([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*("[^"]*"|'[^']*')''',
);
const Set<String> _keptAttributes = {
  'class',
  'id',
  'href',
  'src',
  'data-src',
  'data-original',
  'name',
  'value',
  'action',
  'method',
  'type',
  'onclick',
};
