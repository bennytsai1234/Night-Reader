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
}
