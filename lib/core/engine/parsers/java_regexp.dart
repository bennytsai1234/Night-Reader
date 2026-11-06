/// 書源規則裡的正則照 Java `Pattern` 寫（Legado 直接 `Pattern.compile`、
/// `toRegex()`），換成意思相同的 Dart RegExp：
///
/// - 開頭連續的旗標（`(?i)`、`(?s)`、`(?m)`、`(?x)`、`(?u)`，可以寫成
///   `(?is)` 或 `(?i)(?s)`）Dart 不認得，換成 RegExp 的選項；`(?x)` 由這裡
///   拿掉空白與 `#` 之後的註解（Java 在字元集合裡也一樣）。其他寫法照原文交給
///   Dart，不支援的直接丟 [FormatException]。
/// - 預設 `.` 不跨行、`^` 只對整段開頭；沒開 `(?m)` 時 `$` 同 Java 也對得到
///   最後一個換行之前（Dart 只認真正的結尾）。`\A`、`\z`、`\Z` 換成同義的寫法。
/// - Java 的原子群組 `(?>…)` 換成非捕獲組 `(?:…)`，所有格量詞（`a*+`、
///   `a++`、`a?+`、`a{2,3}+`）拿掉後面多出來的 `+`：Dart 沒有這兩種寫法，
///   換掉後只在回溯行為上不同，多數規則的比對結果相同。
///
/// [wholeInput] 同 Java `matches()`：整段都要符合。
RegExp javaRegExp(String pattern, {bool wholeInput = false}) {
  var options = '';
  var body = pattern;
  for (
    var flags = _leadingFlags.firstMatch(body);
    flags != null;
    flags = _leadingFlags.firstMatch(body)
  ) {
    options += flags.group(1)!;
    body = body.substring(flags.end);
  }
  final multiLine = options.contains('m');
  var source = _translate(
    body,
    multiLine: multiLine,
    comments: options.contains('x'),
  );
  if (wholeInput) source = '$_inputStart(?:$source)$_inputEnd';
  return RegExp(
    source,
    caseSensitive: !options.contains('i'),
    multiLine: multiLine,
    dotAll: options.contains('s'),
    unicode: options.contains('u'),
  );
}

final RegExp _leadingFlags = RegExp(r'^\(\?([imsux]+)\)');

const String _inputStart = r'(?<![\s\S])';
const String _inputEnd = r'(?![\s\S])';

/// 整段結尾，或最後一個換行（Java 的行終止符：`\r\n`、`\n`、`\r`、U+0085、
/// U+2028、U+2029）之前。
final String _finalLineEnd =
    r'(?=(?:\r\n|[\n\r\u0085'
    '${String.fromCharCode(0x2028)}${String.fromCharCode(0x2029)}'
    r'])?(?![\s\S]))';

String _translate(
  String pattern, {
  required bool multiLine,
  required bool comments,
}) {
  final out = StringBuffer();
  var inClass = false;
  var lastWasQuantifier = false;
  for (var i = 0; i < pattern.length; i++) {
    final char = pattern[i];
    if (char == r'\' && i + 1 < pattern.length) {
      final next = pattern[++i];
      final anchor = inClass
          ? null
          : switch (next) {
              'A' => _inputStart,
              'z' => _inputEnd,
              'Z' => _finalLineEnd,
              _ => null,
            };
      out.write(anchor ?? '$char$next');
      lastWasQuantifier = false;
      continue;
    }
    if (comments) {
      if (_isJavaWhitespace(char)) continue;
      if (char == '#') {
        while (i + 1 < pattern.length && pattern[i + 1] != '\n') {
          i++;
        }
        continue;
      }
    }
    if (inClass) {
      if (char == ']') inClass = false;
      out.write(char);
      lastWasQuantifier = false;
      continue;
    }
    if (char == '[') {
      inClass = true;
      out.write(char);
      lastWasQuantifier = false;
      continue;
    }
    if (char == '(' &&
        i + 2 < pattern.length &&
        pattern[i + 1] == '?' &&
        pattern[i + 2] == '>') {
      // 原子群組不佔捕獲組編號，換成一般的非捕獲組。
      out.write('(?:');
      i += 2;
      lastWasQuantifier = false;
      continue;
    }
    if (char == r'$' && !multiLine) {
      out.write(_finalLineEnd);
      lastWasQuantifier = false;
      continue;
    }
    if (char == '+' && lastWasQuantifier) {
      // 所有格量詞：拿掉多出來的 +，原本的量詞與組號都不變。
      lastWasQuantifier = false;
      continue;
    }
    if (char == '*' || char == '+' || char == '?') {
      out.write(char);
      lastWasQuantifier = true;
      continue;
    }
    if (char == '{') {
      final quantifier = _quantifier.matchAsPrefix(pattern, i);
      if (quantifier != null) {
        out.write(quantifier.group(0));
        i = quantifier.end - 1;
        lastWasQuantifier = true;
        continue;
      }
    }
    out.write(char);
    lastWasQuantifier = false;
  }
  return out.toString();
}

/// Java 的 `{m}`、`{m,}`、`{m,n}` 量詞。
final RegExp _quantifier = RegExp(r'\{\d+(?:,\d*)?\}');

/// Java 註解模式略過的空白（`Character.isWhitespace` 的 ASCII 部分）。
bool _isJavaWhitespace(String char) =>
    char == ' ' ||
    char == '\t' ||
    char == '\n' ||
    char == '\r' ||
    char == '\f' ||
    char == '\u000B';
