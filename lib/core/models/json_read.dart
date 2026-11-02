import 'dart:convert';

/// 讀外部匯入的 Legado JSON（書源、替換規則）用的寬鬆轉換。
///
/// Legado 用 Gson 解析，數字欄位寫成字串（例如源倉庫給的
/// `"lastUpdateTime":"1792825494301"`）、開關寫成 `"true"` 也照收；這裡比照
/// 辦理，讀不懂的值改用預設值，不讓一個欄位擋掉整份匯入。
int readJsonInt(dynamic value, {required int fallback}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? fallback;
  return fallback;
}

bool readJsonBool(dynamic value, {required bool fallback}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
      case 'on':
        return true;
      case '0':
      case 'false':
      case 'no':
      case 'off':
        return false;
    }
  }
  return fallback;
}

/// 書源、替換規則的文字欄位：照 Legado 的 `StringJsonDeserializer`，數字、
/// true／false 轉成文字，物件或陣列（例如 `"header": {"User-Agent": …}`、
/// `"loginUi": [...]`）轉成 JSON 文字，null 是 null。
///
/// 和 Gson 差在數字：Dart 讀 JSON 時不留原文，`1.50` 讀成 `"1.5"`。物件裡有
/// 超出範圍的數字（`1e400` 讀成 Infinity）時 JSON 寫不出來，改用 Dart 的文字，
/// 不讓一個欄位擋掉整份匯入。
String? readJsonString(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  try {
    return jsonEncode(value);
  } on JsonUnsupportedObjectError {
    return value.toString();
  }
}
