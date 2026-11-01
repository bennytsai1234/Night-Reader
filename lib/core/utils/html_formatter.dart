/// HtmlFormatter - HTML 內容清理工具 (原 Android utils/HtmlFormatter.kt)
/// 用於將 HTML 轉為閱讀器友好的純文字。
class HtmlFormatter {
  HtmlFormatter._();

  static final RegExp nbspRegex = RegExp(r'(&nbsp;)+');
  static final RegExp espRegex = RegExp(r'(&ensp;|&emsp;)');
  static final RegExp noPrintRegex = RegExp(
    r'(&thinsp;|&zwnj;|&zwj;|\u2009|\u200C|\u200D)',
  );
  static final RegExp wrapHtmlRegex = RegExp(
    r'</?(?:div|p|br|hr|h\d|article|dd|dl)[^>]*>',
    caseSensitive: false,
  );
  static final RegExp commentRegex = RegExp(r'<!--[^>]*-->');
  static final RegExp otherHtmlRegex = RegExp(
    r'</?[a-zA-Z]+(?=[ >])[^<>]*>',
    caseSensitive: false,
  );

  static final RegExp notImgHtmlRegex = RegExp(
    r'</?(?!img)[a-zA-Z]+(?=[ >])[^<>]*>',
    caseSensitive: false,
  );
  static final RegExp formatImageRegex = RegExp(
    r'''<img[^>]*\ssrc\s*=\s*['"]([^'"{>]*\{(?:[^{}]|\{[^}>]+\})+\})['"][^>]*>|<img[^>]*\s(?:data-src|src)\s*=\s*['"]([^'">]+)['"][^>]*>|<img[^>]*\sdata-[^=>]*=\s*['"]([^'">]*)['"][^>]*>''',
    caseSensitive: false,
  );
  static final RegExp _urlOptionRegex = RegExp(r'\s*,\s*(?=\{)');

  static final RegExp indent1Regex = RegExp(r'\s*\n+\s*');
  static final RegExp indent2Regex = RegExp(r'^[\n\s]+');
  static final RegExp lastRegex = RegExp(r'[\n\s]+$');

  /// 格式化 HTML 為文字
  static String format(String? html, {RegExp? otherRegex}) {
    if (html == null) return '';
    final regex = otherRegex ?? otherHtmlRegex;

    return html
        .replaceAll(nbspRegex, ' ')
        .replaceAll(espRegex, ' ')
        .replaceAll('\u00A0', ' ')
        .replaceAll(noPrintRegex, '')
        .replaceAll(wrapHtmlRegex, '\n')
        .replaceAll(commentRegex, '')
        .replaceAll(regex, '')
        .replaceAll(indent1Regex, '\n　　')
        .replaceAll(indent2Regex, '　　')
        .replaceAll(lastRegex, '');
  }

  /// 同 [format]，但保留圖片：每張圖整理成 `<img src="網址">`，網址照
  /// [redirectUrl] 補成完整網址，網址選項（`,{…}`）照原樣接在後面（Legado
  /// `HtmlFormatter.formatKeepImg`，規則 JS 的 `java.htmlFormat`）。
  static String formatKeepImg(String? html, {String? redirectUrl}) {
    if (html == null) return '';
    final keepImgHtml = format(html, otherRegex: notImgHtmlRegex);
    return keepImgHtml.replaceAllMapped(formatImageRegex, (match) {
      var param = '';
      var src = match.group(1);
      if (src != null) {
        final option = _urlOptionRegex.firstMatch(src);
        if (option != null) {
          param = ',${src.substring(option.end)}';
          src = src.substring(0, option.start);
        }
      } else {
        src = match.group(2) ?? match.group(3)!;
      }
      final base = redirectUrl == null ? null : Uri.tryParse(redirectUrl);
      var absolute = src;
      try {
        if (base != null) absolute = base.resolve(src).toString();
      } on FormatException {
        // 補不成完整網址的照原樣留著，同 Legado。
      }
      return '<img src="$absolute$param">';
    });
  }
}
