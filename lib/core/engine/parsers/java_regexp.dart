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
/// - Java 不用開選項就認得 `\p{…}`、`\pL`（字元類別）；Dart 要開 `unicode`，
///   沒開時 `\p` 是字母 p。規則裡有它們（或開頭寫了 `(?u)`）時開 `unicode`，
///   Java 專有的名稱（`IsHan`、`InCJKUnifiedIdeographs`、`Punct` 這類）換成
///   Dart 認得的寫法，認不得的丟 [FormatException]；開了 `unicode` 之後 Dart
///   不收的 Java 寫法（`\-`、`\<` 這類多餘的跳脫、單獨的 `}`、`]`、字元集合裡
///   緊鄰 `\w` 的 `-`、`\x{…}`、`\Q…\E`、八進位、`\e`、`\h`、`\R`）換成同義
///   的寫法。字元類別照 Legado 實際跑的 Android（ICU）認，POSIX 名稱也看
///   Unicode。
///
/// [wholeInput] 同 Java `matches()`：整段都要符合。寫錯的 [pattern] 一樣丟
/// [FormatException]：先照原樣編一次再包，不然 `[abc` 這類少了括號的寫法
/// 會和包在外面的字接起來，變成另一個合法、什麼都對得上的寫法。
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
  final unicode = options.contains('u') || _hasPropertyEscape(body);
  var source = _translate(
    body,
    multiLine: multiLine,
    comments: options.contains('x'),
    unicode: unicode,
  );
  RegExp compile(String source) => RegExp(
    source,
    caseSensitive: !options.contains('i'),
    multiLine: multiLine,
    dotAll: options.contains('s'),
    unicode: unicode,
  );
  if (!wholeInput) return compile(source);
  compile(source);
  return compile('$_inputStart(?:$source)$_inputEnd');
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
  required bool unicode,
}) {
  final out = StringBuffer();
  var inClass = false;
  var lastWasQuantifier = false;
  // 字元集合裡剛寫了 \w、\p{…} 這類（unicode 模式後面的 - 要跳脫）。
  var lastWasClassEscape = false;
  for (var i = 0; i < pattern.length; i++) {
    final char = pattern[i];
    if (char == r'\' && i + 1 < pattern.length) {
      final next = pattern[++i];
      if (next == 'p' || next == 'P') {
        final String name;
        if (i + 1 < pattern.length && pattern[i + 1] == '{') {
          final close = pattern.indexOf('}', i + 2);
          if (close == -1) {
            throw FormatException('字元類別少了 }', pattern, i);
          }
          name = pattern.substring(i + 2, close);
          i = close;
        } else if (i + 1 < pattern.length) {
          name = pattern[++i];
        } else {
          throw FormatException('字元類別少了名稱', pattern, i);
        }
        out.write(
          _unicodeProperty(name, negated: next == 'P', inClass: inClass),
        );
        lastWasQuantifier = false;
        lastWasClassEscape = inClass;
        continue;
      }
      // Dart 的 \u{…}、\x{…} 整組是一個 token：裡面的大括號不是量詞，後面
      // 的 + 也不是所有格尾碼。
      if (_bracketedEscapes.contains(next) &&
          i + 1 < pattern.length &&
          pattern[i + 1] == '{') {
        final close = pattern.indexOf('}', i + 2);
        if (close != -1) {
          // unicode 模式只認 \u{…}；Java 的 \x{…} 是同一個意思。
          out.write(
            unicode
                ? '\\u${pattern.substring(i + 1, close + 1)}'
                : pattern.substring(i - 1, close + 1),
          );
          i = close;
          lastWasQuantifier = false;
          continue;
        }
      }
      if (unicode) {
        final converted = _javaOnlyEscape(pattern, i, inClass: inClass);
        if (converted != null) {
          out.write(converted.text);
          i = converted.end - 1;
          lastWasQuantifier = false;
          lastWasClassEscape = false;
          continue;
        }
      }
      final anchor = inClass
          ? null
          : switch (next) {
              'A' => _inputStart,
              'z' => _inputEnd,
              'Z' => _finalLineEnd,
              _ => null,
            };
      out.write(
        anchor ??
            (unicode ? _unicodeEscape(next, inClass: inClass) : '$char$next'),
      );
      lastWasQuantifier = false;
      lastWasClassEscape = inClass && _classEscapes.contains(next);
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
      if (unicode &&
          char == '-' &&
          (lastWasClassEscape || _classEscapeAt(pattern, i + 1))) {
        out.write(r'\-');
      } else {
        out.write(char);
      }
      lastWasQuantifier = false;
      lastWasClassEscape = false;
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
      final quantifier = _quantifierAt(pattern, i, comments: comments);
      if (quantifier != null) {
        // 註解模式會把量詞裡的空白與註解拿掉，寫回正規化後的寫法。
        out.write(quantifier.text);
        i = quantifier.end - 1;
        lastWasQuantifier = true;
        continue;
      }
    }
    // unicode 模式不收單獨的 } 與 ]；Java 照字面。
    out.write(unicode && (char == '}' || char == ']') ? '\\$char' : char);
    lastWasQuantifier = false;
  }
  return out.toString();
}

/// Java 的 `{m}`、`{m,}`、`{m,n}` 量詞；註解模式允許裡面有空白與註解。
({String text, int end})? _quantifierAt(
  String pattern,
  int start, {
  required bool comments,
}) {
  final body = StringBuffer();
  var digits = 0;
  for (var i = start + 1; i < pattern.length; i++) {
    final char = pattern[i];
    if (comments) {
      if (_isJavaWhitespace(char)) continue;
      if (char == '#') {
        while (i + 1 < pattern.length && pattern[i + 1] != '\n') {
          i++;
        }
        continue;
      }
    }
    if (char == '}') {
      final text = '{$body}';
      if (digits == 0 || !_quantifier.hasMatch(text)) return null;
      return (text: text, end: i + 1);
    }
    final code = char.codeUnitAt(0);
    if ((code >= 0x30 && code <= 0x39) || char == ',') {
      body.write(char);
      if (char != ',') digits++;
      continue;
    }
    return null;
  }
  return null;
}

/// 正規化後的量詞（去掉註解模式的有效空白）。
final RegExp _quantifier = RegExp(r'^\{\d+(?:,\d*)?\}$');

const Set<String> _bracketedEscapes = {'u', 'x'};

/// 字元集合裡代表一整類字的跳脫。
const Set<String> _classEscapes = {'w', 'W', 'd', 'D', 's', 'S'};

/// [pattern] 從 [index] 起是 `\w`、`\p` 這類代表一整類字的跳脫。
bool _classEscapeAt(String pattern, int index) =>
    index + 1 < pattern.length &&
    pattern[index] == r'\' &&
    (_classEscapes.contains(pattern[index + 1]) ||
        pattern[index + 1] == 'p' ||
        pattern[index + 1] == 'P');

/// [pattern] 裡有 `\p`、`\P`（不是跳脫過的反斜線後面的 p）。
bool _hasPropertyEscape(String pattern) {
  for (var i = 0; i + 1 < pattern.length; i++) {
    if (pattern[i] != r'\') continue;
    final next = pattern[++i];
    if (next == 'p' || next == 'P') return true;
  }
  return false;
}

/// unicode 模式下 `\` 加 [next]：Dart 只收語法字元的跳脫（字元集合裡另收
/// `-`），Java 的其他多餘跳脫（`\<`、`\"`、`\_`）照字面寫。
String _unicodeEscape(String next, {required bool inClass}) {
  final code = next.codeUnitAt(0);
  final alphanumeric =
      (code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A);
  if (alphanumeric || _syntaxCharacters.contains(next)) return '\\$next';
  if (next == '-') return inClass ? r'\-' : '-';
  return next;
}

const String _syntaxCharacters = r'^$\.*+?()[]{}|/';

/// unicode 模式下 Dart 不認得、Java 認得的跳脫（[index] 是反斜線後面那個
/// 字）：`\Q…\E`（中間照字面）、八進位 `\0nn`、`\e`、`\a`、`\h`、`\H`、
/// `\R`。換成同義的寫法與下一個要讀的位置；不是這幾種時是 null。
({String text, int end})? _javaOnlyEscape(
  String pattern,
  int index, {
  required bool inClass,
}) {
  final next = pattern[index];
  switch (next) {
    case 'Q':
      final close = pattern.indexOf(r'\E', index + 1);
      final quoted = pattern.substring(
        index + 1,
        close == -1 ? pattern.length : close,
      );
      final text = StringBuffer();
      for (final rune in quoted.runes) {
        final char = String.fromCharCode(rune);
        text.write(
          _syntaxCharacters.contains(char) || (inClass && char == '-')
              ? '\\$char'
              : char,
        );
      }
      return (text: '$text', end: close == -1 ? pattern.length : close + 2);
    case '0':
      var end = index + 1;
      var value = 0;
      while (end < pattern.length &&
          end < index + 4 &&
          pattern.codeUnitAt(end) >= 0x30 &&
          pattern.codeUnitAt(end) <= 0x37 &&
          value * 8 + pattern.codeUnitAt(end) - 0x30 <= 0xFF) {
        value = value * 8 + pattern.codeUnitAt(end) - 0x30;
        end++;
      }
      if (end == index + 1) return null;
      return (text: '\\u{${value.toRadixString(16)}}', end: end);
    case 'e':
      return (text: r'\u{1B}', end: index + 1);
    case 'a':
      return (text: r'\u{7}', end: index + 1);
    case 'h' || 'H':
      return (
        text: _renderSet(
          const _CharSet.union(_horizontalSpace),
          negated: next == 'H',
          inClass: inClass,
          name: next,
        ),
        end: index + 1,
      );
    case 'R' when !inClass:
      return (
        text: '(?:\\r\\n|[\\n\\u{B}\\f\\r\\u{85}\\u{2028}\\u{2029}])',
        end: index + 1,
      );
  }
  return null;
}

/// Java `\h` 的水平空白。
const String _horizontalSpace =
    r' \t\u{A0}\u{1680}\u{180E}\u{2000}-\u{200A}\u{202F}\u{205F}\u{3000}';

/// Java 的字元類別換成 Dart unicode 模式能寫的樣子：一個屬性（[token]，
/// 在哪裡都能取反）、一組字（[body] 是字元集合裡的內容），或一組字以外的
/// 字（[complement]）。
final class _CharSet {
  const _CharSet.token(String this.token) : body = null, complement = false;
  const _CharSet.union(String this.body) : token = null, complement = false;
  const _CharSet.except(String this.body) : token = null, complement = true;

  final String? token;
  final String? body;
  final bool complement;
}

/// [set] 寫成正則：字元集合外面包成 `[…]`、`[^…]`；字元集合裡面只能寫出
/// 不用取反的那一種，另一種丟 [FormatException]。
String _renderSet(
  _CharSet set, {
  required bool negated,
  required bool inClass,
  required String name,
}) {
  if (set.token case final token?) {
    return '\\${negated ? 'P' : 'p'}{$token}';
  }
  final body = set.body!;
  final excluded = set.complement != negated;
  if (!inClass) return excluded ? '[^$body]' : '[$body]';
  if (excluded) {
    throw FormatException('字元集合裡的這種寫法不支援：$name');
  }
  return body;
}

/// Java 的字元類別 `\p{name}`（[negated] 是 `\P`）換成 Dart unicode 模式的
/// 寫法。Legado 跑在 Android 上，Java 的正則由 ICU 執行：POSIX 名稱照
/// Unicode 認，不加 `Is` 的名稱先找一般分類、再找文字系統。Dart 只認一般
/// 分類、文字系統與二元屬性，Unicode 區塊（`In…`）換成範圍；認不得的丟
/// [FormatException]。
String _unicodeProperty(
  String name, {
  required bool negated,
  required bool inClass,
}) => _renderSet(
  _javaProperty(name),
  negated: negated,
  inClass: inClass,
  name: '\\p{$name}',
);

_CharSet _javaProperty(String name) {
  String compact(String text) =>
      text.replaceAll(RegExp(r'[\s_-]'), '').toLowerCase();
  final key = compact(name);
  if (_posixClasses[name] case final posix?) return posix;
  if (_javaClasses[name] case final java?) return java;
  if (_generalCategories.contains(name)) return _CharSet.token(name);

  final eq = name.indexOf('=');
  if (eq > 0) {
    final kind = name.substring(0, eq).toLowerCase();
    final value = name.substring(eq + 1);
    switch (kind) {
      case 'gc' || 'general_category':
        if (_generalCategories.contains(value)) return _CharSet.token(value);
      case 'sc' || 'script':
        return _CharSet.token('Script=${_scriptName(value)}');
      case 'blk' || 'block':
        if (_blocks[compact(value)] case final block?) {
          return _CharSet.union(block);
        }
    }
    throw FormatException('認不得的字元類別 \\p{$name}');
  }
  if (key.startsWith('in')) {
    if (_blocks[key.substring(2)] case final block?) {
      return _CharSet.union(block);
    }
  }
  if (name.startsWith('Is') && name.length > 2) {
    final rest = name.substring(2);
    if (_generalCategories.contains(rest)) return _CharSet.token(rest);
    if (_binaryProperties[key.substring(2)] case final binary?) {
      return _CharSet.token(binary);
    }
    return _CharSet.token('Script=${_scriptName(rest)}');
  }
  if (RegExp(r'^[A-Za-z][A-Za-z_]*$').hasMatch(name)) {
    return _CharSet.token('Script=${_scriptName(name)}');
  }
  throw FormatException('認不得的字元類別 \\p{$name}');
}

/// Java 的文字系統名稱不分大小寫，Dart 要寫成 `Han`、`Old_Italic` 這樣。
String _scriptName(String name) => name
    .split('_')
    .map(
      (part) => part.isEmpty
          ? part
          : part[0].toUpperCase() + part.substring(1).toLowerCase(),
    )
    .join('_');

const Set<String> _generalCategories = {
  'L', 'Lu', 'Ll', 'Lt', 'Lm', 'Lo', 'LC', 'M', 'Mn', 'Mc', 'Me', //
  'N', 'Nd', 'Nl', 'No', 'P', 'Pc', 'Pd', 'Ps', 'Pe', 'Pi', 'Pf', 'Po', //
  'S', 'Sm', 'Sc', 'Sk', 'So', 'Z', 'Zs', 'Zl', 'Zp', //
  'C', 'Cc', 'Cf', 'Co', 'Cs', 'Cn',
};

/// Java `\p{IsXxx}` 的二元屬性（去掉底線、小寫）對 Dart 的名稱。
const Map<String, String> _binaryProperties = {
  'alphabetic': 'Alphabetic',
  'ideographic': 'Ideographic',
  'letter': 'L',
  'lowercase': 'Lowercase',
  'uppercase': 'Uppercase',
  'titlecase': 'Lt',
  'punctuation': 'P',
  'control': 'Cc',
  'whitespace': 'White_Space',
  'digit': 'Nd',
  'hexdigit': 'Hex_Digit',
  'joincontrol': 'Join_Control',
  'noncharactercodepoint': 'Noncharacter_Code_Point',
  'assigned': 'Assigned',
};

/// POSIX 字元類別，照 ICU（Android）的定義認 Unicode。
const Map<String, _CharSet> _posixClasses = {
  'Lower': _CharSet.token('Lowercase'),
  'Upper': _CharSet.token('Uppercase'),
  'ASCII': _CharSet.union(r'\u{0}-\u{7F}'),
  'Alpha': _CharSet.token('Alphabetic'),
  'Digit': _CharSet.token('Nd'),
  'Alnum': _CharSet.union(r'\p{Alphabetic}\p{Nd}'),
  'Punct': _CharSet.token('P'),
  'Graph': _CharSet.except(r'\p{White_Space}\p{Cc}\p{Cs}\p{Cn}'),
  'Print': _CharSet.except(r'\p{Cc}\p{Cs}\p{Cn}\p{Zl}\p{Zp}'),
  'Blank': _CharSet.union(r'\p{Zs}\t'),
  'Cntrl': _CharSet.token('Cc'),
  'XDigit': _CharSet.union(r'\p{Nd}\p{Hex_Digit}'),
  'Space': _CharSet.token('White_Space'),
};

/// Java 的 `\p{javaXxx}`（照 `Character.isXxx`）。
const Map<String, _CharSet> _javaClasses = {
  'javaLowerCase': _CharSet.token('Lowercase'),
  'javaUpperCase': _CharSet.token('Uppercase'),
  'javaTitleCase': _CharSet.token('Lt'),
  'javaAlphabetic': _CharSet.token('Alphabetic'),
  'javaIdeographic': _CharSet.token('Ideographic'),
  'javaDigit': _CharSet.token('Nd'),
  'javaLetter': _CharSet.token('L'),
  'javaLetterOrDigit': _CharSet.union(r'\p{L}\p{Nd}'),
  'javaSpaceChar': _CharSet.token('Z'),
  'javaMirrored': _CharSet.token('Bidi_Mirrored'),
  // Character.isWhitespace：不含不斷行空白（U+00A0、U+2007、U+202F）。
  'javaWhitespace': _CharSet.union(
    r'\t\n\u{B}\f\r\u{1C}-\u{20}\u{1680}\u{2000}-\u{2006}'
    r'\u{2008}-\u{200A}\u{2028}\u{2029}\u{205F}\u{3000}',
  ),
};

/// 書源規則常用的 Unicode 區塊（名稱去掉空白、底線、連字號，小寫）。
const Map<String, String> _blocks = {
  'basiclatin': r'\u{0}-\u{7F}',
  'latin1supplement': r'\u{80}-\u{FF}',
  'generalpunctuation': r'\u{2000}-\u{206F}',
  'cjkradicalssupplement': r'\u{2E80}-\u{2EFF}',
  'cjksymbolsandpunctuation': r'\u{3000}-\u{303F}',
  'hiragana': r'\u{3040}-\u{309F}',
  'katakana': r'\u{30A0}-\u{30FF}',
  'bopomofo': r'\u{3100}-\u{312F}',
  'cjkunifiedideographsextensiona': r'\u{3400}-\u{4DBF}',
  'cjkunifiedideographs': r'\u{4E00}-\u{9FFF}',
  'hangulsyllables': r'\u{AC00}-\u{D7AF}',
  'cjkcompatibilityideographs': r'\u{F900}-\u{FAFF}',
  'verticalforms': r'\u{FE10}-\u{FE1F}',
  'cjkcompatibilityforms': r'\u{FE30}-\u{FE4F}',
  'halfwidthandfullwidthforms': r'\u{FF00}-\u{FFEF}',
};

/// Java 註解模式略過的空白（`Character.isWhitespace` 的 ASCII 部分）。
bool _isJavaWhitespace(String char) =>
    char == ' ' ||
    char == '\t' ||
    char == '\n' ||
    char == '\r' ||
    char == '\f' ||
    char == '\u000B';
