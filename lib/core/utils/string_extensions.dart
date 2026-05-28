import 'package:flutter/widgets.dart';
import 'string_utils.dart';

/// StringExtensions - 字符串擴展 (原 Android utils/StringExtensions.kt)
extension StringExtensions on String {
  /// 判斷是否為絕對 URL
  bool isAbsUrl() {
    final lower = toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  /// 判斷是否為 Data URL
  bool isDataUrl() {
    return startsWith('data:');
  }

  /// 判斷是否為 JSON
  bool isJson() {
    final s = trim();
    return (s.startsWith('{') && s.endsWith('}')) ||
        (s.startsWith('[') && s.endsWith(']'));
  }

  /// 判斷是否為 XML
  bool isXml() {
    final s = trim();
    return s.startsWith('<') && s.endsWith('>');
  }

  /// 轉換為布林值 (支持 Legado 格式: false/no/not/0 為 false)
  bool isTrue({bool nullIsTrue = false}) {
    final s = trim().toLowerCase();
    if (s.isEmpty || s == 'null') return nullIsTrue;
    return !RegExp(r'^(false|no|not|0)$').hasMatch(s);
  }

  /// 是否包含中文
  bool isChinese() {
    return RegExp(r'[\u4e00-\u9fa5]').hasMatch(this);
  }

  /// 安全 Trim (對標 StringUtils.trim)
  String safeTrim() {
    return StringUtils.trim(this);
  }

  /// 轉義正則表達式特殊字元
  static final RegExp _regexCharRegex = RegExp(r'([.*+?^${}()|[\]\\])');
  String escapeRegex() {
    return replaceAllMapped(_regexCharRegex, (match) => '\\${match.group(1)}');
  }

  /// 檔案名稱合法化
  static final RegExp _fileNameRegex = RegExp(r'[\\/:*?"<>|]');
  String normalizeFileName() {
    return replaceAll(_fileNameRegex, '_');
  }

  /// 拆分為單個字元 (支援 Emoji)
  List<String> toStringArray() {
    return characters.map((c) => c).toList();
  }
}

extension StringNullableExtensions on String? {
  bool isNullOrBlank() {
    return this == null || this!.trim().isEmpty;
  }
}
