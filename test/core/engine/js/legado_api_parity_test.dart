import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/js/js_extensions.dart';

import '../../../test_helper.dart';

/// Legado 交給書源程式的每個物件、每個公開方法，照 Legado 原始碼列出。夜讀的
/// 規則 JS 都要有；刻意不做的列在 [_notProvided] 寫明理由，其他一律要有。
/// Legado 加了新方法就加進這裡，少接一個這個測試就失敗。

/// `help/JsExtensions.kt` 與 `help/JsEncodeUtils.kt`：規則裡的 `java`，也是
/// `source` 繼承的（BaseSource 實作 JsExtensions）。
const _jsExtensions = [
  'HMacBase64', 'HMacHex', 'aesBase64DecodeToByteArray',
  'aesBase64DecodeToString', 'aesDecodeArgsBase64Str', 'aesDecodeToByteArray',
  'aesDecodeToString', 'aesEncodeArgsBase64Str', 'aesEncodeToBase64ByteArray',
  'aesEncodeToBase64String', 'aesEncodeToByteArray', 'aesEncodeToString',
  'ajax', 'ajaxAll', 'androidId', 'base64Decode', 'base64DecodeToByteArray',
  'base64Encode', 'bytesToStr', 'cacheFile', 'connect',
  'createAsymmetricCrypto', 'createSign', 'createSymmetricCrypto',
  'deleteFile', 'desBase64DecodeToString', 'desDecodeToString',
  'desEncodeToBase64String', 'desEncodeToString', 'digestBase64Str',
  'digestHex', 'downloadFile', 'encodeURI', 'get7zByteArrayContent',
  'get7zStringContent', 'getCookie', 'getFile', 'getRarByteArrayContent',
  'getRarStringContent', 'getSource', 'getTxtInFolder', 'getVerificationCode',
  'getWebViewUA', 'getZipByteArrayContent', 'getZipStringContent', 'head',
  'hexDecodeToByteArray', 'hexDecodeToString', 'hexEncodeToString',
  'htmlFormat', 'importScript', 'log', 'logType', 'longToast', 'md5Encode',
  'md5Encode16', 'openUrl', 'post', 'queryBase64TTF', 'queryTTF',
  'randomUUID', 'readFile', 'readTxtFile', 'replaceFont', 's2t',
  'startBrowser', 'startBrowserAwait', 'strToBytes', 't2s', 'timeFormat',
  'timeFormatUTC', 'toNumChapter', 'toURL', 'toast',
  'tripleDESDecodeArgsBase64Str', 'tripleDESDecodeStr',
  'tripleDESEncodeArgsBase64Str', 'tripleDESEncodeBase64Str', 'un7zFile',
  'unArchiveFile', 'unrarFile', 'unzipFile', 'webView',
  'webViewGetOverrideUrl', 'webViewGetSource',
  // JsExtensions 的 get(url, headers)；source 的 get 是讀變數（BaseSource 自己的）。
  'get',
];

const _legado = <String, List<String>>{
  'java': [
    ..._jsExtensions,
    // model/analyzeRule/AnalyzeRule.kt：規則裡的 java 就是規則解析器。
    'evalJS', 'getElement', 'getElements', 'getString', 'getStringList', 'put',
    'reGetBook', 'refreshTocUrl', 'setBaseUrl', 'setContent', 'setRedirectUrl',
  ],
  'source': [
    ..._jsExtensions,
    // data/entities/BaseSource.kt
    'evalJS', 'getHeaderMap', 'getKey', 'getLoginHeader', 'getLoginHeaderMap',
    'getLoginInfo', 'getLoginInfoMap', 'getLoginJs', 'getTag', 'getVariable',
    'login', 'put', 'putLoginHeader', 'putLoginInfo', 'removeLoginHeader',
    'removeLoginInfo', 'setVariable',
  ],
  // help/http/CookieStore.kt
  'cookie': [
    'clear',
    'cookieToMap',
    'getCookie',
    'getKey',
    'mapToCookie',
    'removeCookie',
    'replaceCookie',
    'setCookie',
  ],
  // help/CacheManager.kt
  'cache': [
    'delete',
    'deleteMemory',
    'get',
    'getByteArray',
    'getDouble',
    'getFile',
    'getFloat',
    'getFromMemory',
    'getInt',
    'getLong',
    'put',
    'putFile',
    'putMemory',
  ],
};

/// 刻意不做的，和理由（java 與 source 都適用）。
const _notProvided = <String, String>{
  // 這一組照 Legado 以快取資料夾為準、帶書源標頭與網址選項 type，和網址
  // 選項一起補（HANDOFF）。
  'deleteFile': '下載與檔案一組，隨網址選項 type 一起補',
  'getFile': '下載與檔案一組，隨網址選項 type 一起補',
  'getZipStringContent': '下載與檔案一組，隨網址選項 type 一起補',
  'unzipFile': '下載與檔案一組，隨網址選項 type 一起補',
};

// 不列的 Legado 公開方法：
// - AnalyzeRule.splitSourceRule：傳回 Legado 內部的規則物件，書源用不到。
// - BaseSource.loginUi()：和書源的 loginUi 欄位同名，Rhino 裡書源讀到的是欄位。
// - CacheManager.sizeOf：LruCache 內部算大小用的。clearSourceVariables、
//   getQueryTTF 在 Legado 的 AppCacheManager，不是 cache。

void main() {
  setupTestDI();
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = quickJsUnavailableReason();

  test('rule JS has every method Legado gives source programs', () {
    final runtime = getJavascriptRuntime();
    addTearDown(runtime.dispose);
    JsExtensions(runtime).inject();

    final missing = <String>[];
    for (final MapEntry(key: object, value: methods) in _legado.entries) {
      for (final method in methods.toSet()) {
        final fromJsExtensions = object == 'java' || object == 'source';
        if (fromJsExtensions && _notProvided.containsKey(method)) continue;
        final name = '$object.$method';
        final type = runtime.evaluate('typeof $name').stringResult;
        if (type != 'function') missing.add(name);
      }
    }
    expect(missing, isEmpty, reason: '夜讀少了這些 Legado 方法');
  }, skip: skip);
}
