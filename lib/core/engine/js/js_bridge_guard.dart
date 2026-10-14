/// 背景解析（`ParseWorker`）裡的 JS 只能呼叫只做計算的橋接。
///
/// 規則 JS 經 `sendMessage` 進到 Dart 的每一個頻道都會先問這裡。背景
/// isolate 沒有主 isolate 的網路、Cookie、快取、紀錄與書源變數，`book`／
/// `chapter` 也是複本：這類呼叫在背景執行會默默給出不同結果或遺失寫入。
/// 不管 JS 怎麼寫（中括號、複合賦值、別名、直接呼叫 `sendMessage`），都要
/// 經過這一層，所以在這裡擋才擋得完整；`ParseWorker.fit` 的字面比對只是
/// 先把明顯不行的規則留在原地，省一趟來回。
abstract final class JsBridgeGuard {
  /// 只在背景解析的 isolate 開啟。
  static bool restricted = false;

  /// 被擋下的呼叫次數。背景解析在任務前後比對，有變就整個任務改回原地。
  static int blockedCalls = 0;

  /// 結果只取決於參數與這次規則自己的頁面、元素與 `book`／`chapter` 複本的頻道。
  static const Set<String> computeOnly = {
    '__ruleDone',
    // 編碼、雜湊、加解密
    '_base64Decode',
    '_base64DecodeToBytes',
    '_base64Encode',
    '_desEncodeToBase64String',
    '_digest',
    '_gunzipBytes',
    '_hexDecode',
    '_hexEncode',
    '_hmacHex',
    '_md5Encode',
    '_md5Encode16',
    '_randomUUID',
    'symmetricCrypto',
    // 字串與時間
    '_htmlFormat',
    '_timeFormat',
    '_toNumChapter',
    'bytesToStr',
    'strToBytes',
    'timeFormatUTC',
    // 這次規則的頁面與元素
    'htmlRemove',
    'htmlSelectAttr',
    'htmlSelectAttributes',
    'htmlSelectCount',
    'htmlSelectData',
    'htmlSelectHtml',
    'htmlSelectText',
    'htmlSelectTextList',
    'ruleGetElement',
    'ruleGetElements',
    'ruleGetString',
    'ruleGetStringList',
    'ruleSetContent',
    // 讀 book／chapter 複本
    'scopedObjectGetField',
    'scopedObjectGetVariable',
  };

  /// [channel] 要不要擋；擋下時記一次，呼叫端不執行、回 null。
  static bool blocks(String channel) {
    if (!restricted || computeOnly.contains(channel)) return false;
    blockedCalls++;
    return true;
  }
}
