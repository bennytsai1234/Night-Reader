/// 假名偵測——判斷一行文字是否為「未翻譯的日文段落」。
///
/// 純 Dart、無任何平台相依，worker isolate 可安全使用。
///
/// 判定規則（閾值集中於常數，便於調整）：
/// - 核心假名（平假名/片假名字母，不含長音「ー」與疊字符）數 >=
///   [kJapaneseMinCoreKana]：擋掉中文網文慣用的單字「の」（「XXの店」）
///   與擬聲拖長（「啊ーー」）。
/// - 假名占假名＋漢字的比例 >= [kJapaneseMinKanaRatio]：擋掉大量中文
///   夾帶一兩個假名的句子。
library;

const int kJapaneseMinCoreKana = 2;
const double kJapaneseMinKanaRatio = 0.15;

bool looksJapanese(String line) {
  if (line.isEmpty) return false;
  var coreKana = 0;
  var kana = 0;
  var han = 0;
  for (final rune in line.runes) {
    if (_isCoreKana(rune)) {
      coreKana += 1;
      kana += 1;
    } else if (_isAuxiliaryKana(rune)) {
      kana += 1;
    } else if (_isHan(rune)) {
      han += 1;
    }
  }
  if (coreKana < kJapaneseMinCoreKana) return false;
  return kana / (kana + han) >= kJapaneseMinKanaRatio;
}

/// 平假名/片假名字母本體（含半形片假名字母）。
bool _isCoreKana(int rune) {
  return (rune >= 0x3041 && rune <= 0x3096) || // 平假名
      (rune >= 0x30A1 && rune <= 0x30FA) || // 片假名
      (rune >= 0xFF66 && rune <= 0xFF6F) || // 半形片假名（ｦ–ｯ）
      (rune >= 0xFF71 && rune <= 0xFF9D); // 半形片假名（ｱ–ﾝ）
}

/// 長音、疊字符等輔助符號：算假名但不算「核心」證據
/// （中文擬聲常借用「ー」拖長，不能單獨觸發）。
bool _isAuxiliaryKana(int rune) {
  return rune == 0x30FC || // ー 長音
      rune == 0xFF70 || // ｰ 半形長音
      (rune >= 0x309D && rune <= 0x309E) || // ゝゞ
      (rune >= 0x30FD && rune <= 0x30FE); // ヽヾ
}

bool _isHan(int rune) {
  return (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0x20000 && rune <= 0x323AF);
}
