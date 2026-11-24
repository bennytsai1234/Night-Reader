import '../engine/parsers/java_regexp.dart';
import 'json_read.dart';

/// ReplaceRule - 替換淨化規則模型
/// (原 Android data/entities/ReplaceRule.kt)
class ReplaceRule {
  int id;
  String name; // 規則名稱
  String? group; // 分組
  String pattern; // 替換正則內容
  String replacement; // 替換為內容
  String? scope; // 作用範圍 (書名/書源URL)
  bool scopeTitle; // 是否作用於標題
  bool scopeContent; // 是否作用於正文
  String? excludeScope; // 排除範圍
  bool isEnabled; // 是否啟用
  bool isRegex; // 是否為正則
  int timeoutMillisecond; // 正則執行超時 (ms)
  int order; // 排序序號 (原 Android sortOrder)

  ReplaceRule({
    this.id = 0,
    this.name = '',
    this.group,
    this.pattern = '',
    this.replacement = '',
    this.scope,
    this.scopeTitle = false,
    this.scopeContent = true,
    this.excludeScope,
    this.isEnabled = true,
    this.isRegex = true,
    this.timeoutMillisecond = 3000,
    this.order = 0,
  });

  /// 校驗規則是否合法 (原 Android isValid)
  bool isValid() {
    if (pattern.isEmpty) return false;
    if (isRegex) {
      try {
        javaRegExp(pattern);
      } on FormatException {
        return false;
      }
      // 檢查結尾是否有多餘的 | (原版特有的健壯性檢查)
      if (pattern.endsWith('|') && !pattern.endsWith(r'\|')) {
        return false;
      }
    }
    return true;
  }

  int getValidTimeoutMillisecond() {
    return timeoutMillisecond <= 0 ? 3000 : timeoutMillisecond;
  }

  bool matchesScope({required String bookName, required String bookOrigin}) {
    final includeScope = scope?.trim();
    final includeMatched =
        includeScope == null ||
        includeScope.isEmpty ||
        _containsNonEmpty(includeScope, bookName) ||
        _containsNonEmpty(includeScope, bookOrigin);
    if (!includeMatched) return false;

    final exclude = excludeScope?.trim();
    if (exclude == null || exclude.isEmpty) return true;
    return !_containsNonEmpty(exclude, bookName) &&
        !_containsNonEmpty(exclude, bookOrigin);
  }

  bool appliesToContent({
    required String bookName,
    required String bookOrigin,
  }) {
    return isEnabled &&
        scopeContent &&
        pattern.isNotEmpty &&
        matchesScope(bookName: bookName, bookOrigin: bookOrigin);
  }

  bool appliesToTitle({required String bookName, required String bookOrigin}) {
    return isEnabled &&
        scopeTitle &&
        pattern.isNotEmpty &&
        matchesScope(bookName: bookName, bookOrigin: bookOrigin);
  }

  String getDisplayNameGroup() {
    return (group == null || group!.isEmpty) ? name : '$name ($group)';
  }

  /// 套用這一條規則：正文、標題與試跑都用它。正則照 Java 預設（同
  /// Legado）：`.` 不跨段、`^`／`$` 不逐行，開頭寫 `(?s)`、`(?m)` 才開
  /// （[javaRegExp]）。
  String apply(String content) {
    if (pattern.isEmpty) return content;
    try {
      if (isRegex) {
        final reg = javaRegExp(pattern);
        return content.replaceAllMapped(
          reg,
          (match) => _javaReplacement(replacement, match as RegExpMatch),
        );
      } else {
        return content.replaceAll(pattern, replacement);
      }
    } on FormatException {
      return content;
    }
  }

  /// 照 Java `Matcher.appendReplacement`（Legado 用的）展開「替換為」：
  /// `\` 讓下一個字照字面；`$n` 取第 n 組，後面的數字只在群組夠多時才併進
  /// 編號（只有一組時 `$12` 是第 1 組接著「2」）；`${名稱}` 取具名群組。
  /// 沒有的群組、落單的 `\` 或 `$` 丟 [FormatException]，這條規則整條不套
  /// （[apply]）。
  static String _javaReplacement(String replacement, RegExpMatch match) {
    final out = StringBuffer();
    var i = 0;
    while (i < replacement.length) {
      final char = replacement[i];
      if (char == r'\') {
        if (i + 1 >= replacement.length) {
          throw const FormatException('character to be escaped is missing');
        }
        out.write(replacement[i + 1]);
        i += 2;
        continue;
      }
      if (char != r'$') {
        out.write(char);
        i += 1;
        continue;
      }
      i += 1;
      if (i >= replacement.length) {
        throw const FormatException(
          'Illegal group reference: group index is missing',
        );
      }
      if (replacement[i] == '{') {
        final close = replacement.indexOf('}', i);
        if (close < 0) {
          throw const FormatException(
            "named capturing group is missing trailing '}'",
          );
        }
        final name = replacement.substring(i + 1, close);
        if (!match.groupNames.contains(name)) {
          throw FormatException('No group with name {$name}');
        }
        out.write(match.namedGroup(name) ?? '');
        i = close + 1;
        continue;
      }
      var number = _digit(replacement, i);
      if (number == null) {
        throw const FormatException('Illegal group reference');
      }
      i += 1;
      while (i < replacement.length) {
        final next = _digit(replacement, i);
        if (next == null || number! * 10 + next > match.groupCount) break;
        number = number * 10 + next;
        i += 1;
      }
      if (number! > match.groupCount) {
        throw FormatException('No group $number');
      }
      out.write(match.group(number) ?? '');
    }
    return out.toString();
  }

  static int? _digit(String text, int index) {
    final unit = text.codeUnitAt(index);
    return unit >= 0x30 && unit <= 0x39 ? unit - 0x30 : null;
  }

  factory ReplaceRule.fromJson(Map<String, dynamic> json) {
    return ReplaceRule(
      id: readJsonInt(json['id'], fallback: 0),
      name: _readString(json['name'] ?? json['replaceSummary']),
      group: _readNullableString(json['group']),
      pattern: _readString(json['pattern'] ?? json['regex']),
      replacement: _readString(json['replacement']),
      scope: _readNullableString(json['scope'] ?? json['useTo']),
      scopeTitle: readJsonBool(json['scopeTitle'], fallback: false),
      scopeContent: readJsonBool(json['scopeContent'], fallback: true),
      excludeScope: _readNullableString(json['excludeScope']),
      isEnabled: readJsonBool(
        json['isEnabled'] ?? json['enable'],
        fallback: true,
      ),
      isRegex: readJsonBool(json['isRegex'], fallback: true),
      timeoutMillisecond: readJsonInt(
        json['timeoutMillisecond'],
        fallback: 3000,
      ),
      order: readJsonInt(json['order'] ?? json['serialNumber'], fallback: 0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id == 0 ? null : id,
      'name': name,
      'group': group,
      'pattern': pattern,
      'replacement': replacement,
      'scope': scope,
      'scopeTitle': scopeTitle ? 1 : 0,
      'scopeContent': scopeContent ? 1 : 0,
      'excludeScope': excludeScope,
      'isEnabled': isEnabled ? 1 : 0,
      'isRegex': isRegex ? 1 : 0,
      'timeoutMillisecond': timeoutMillisecond,
      'order': order,
    };
  }

  static bool _containsNonEmpty(String scopeText, String value) {
    final trimmed = value.trim();
    return trimmed.isNotEmpty && scopeText.contains(trimmed);
  }

  static String _readString(dynamic value) => readJsonString(value) ?? '';

  static String? _readNullableString(dynamic value) => readJsonString(value);
}
