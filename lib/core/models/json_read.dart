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
