import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/js/js_extensions.dart';

import '../../../test_helper.dart';

/// Legado 交給書源程式的每個物件、每個公開方法（照 Legado 原始碼
/// `help/JsExtensions.kt`、`help/JsEncodeUtils.kt`、
/// `model/analyzeRule/AnalyzeRule.kt`、`data/entities/BaseSource.kt`、
/// `help/http/CookieStore.kt`、`help/CacheManager.kt` 列出）。夜讀的規則 JS
/// 都要有；刻意不做的列在 [_notProvided]，寫明理由。Legado 加了新方法就加進
/// 這裡，少接一個這個測試就失敗。
const _legado = <String, List<String>>{
  'java': [
    // JsExtensions、JsEncodeUtils
    'HMacBase64', 'HMacHex', 'aesBase64DecodeToByteArray',
    'aesBase64DecodeToString', 'aesDecodeArgsBase64Str', 'aesDecodeToByteArray',
    'aesDecodeToString', 'aesEncodeArgsBase64Str', 'aesEncodeToBase64ByteArray',
    'aesEncodeToBase64String', 'aesEncodeToByteArray', 'aesEncodeToString',
    'ajax', 'ajaxAll', 'androidId', 'base64Decode', 'base64DecodeToByteArray',
    'base64Encode', 'bytesToStr', 'cacheFile', 'connect',
    'createAsymmetricCrypto', 'createSign', 'createSymmetricCrypto',
    'deleteFile', 'desBase64DecodeToString', 'desDecodeToString',
    'desEncodeToBase64String', 'desEncodeToString', 'digestBase64Str',
    'digestHex', 'downloadFile', 'encodeURI', 'get', 'get7zByteArrayContent',
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
    // AnalyzeRule（規則裡的 java 就是規則解析器）
    'getElement', 'getElements', 'getString', 'getStringList', 'put',
    'reGetBook', 'refreshTocUrl', 'setBaseUrl', 'setContent', 'setRedirectUrl',
  ],
  'source': [
    'evalJS',
    'get',
    'getHeaderMap',
    'getKey',
    'getLoginHeader',
    'getLoginHeaderMap',
    'getLoginInfo',
    'getLoginInfoMap',
    'getLoginJs',
    'getSource',
    'getTag',
    'getVariable',
    'login',
    'put',
    'putLoginHeader',
    'putLoginInfo',
    'removeLoginHeader',
    'removeLoginInfo',
    'setVariable',
  ],
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
  'cache': [
    'delete',
    'deleteMemory',
    'get',
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

/// 刻意不做的，和理由。
const _notProvided = <String, String>{
  // 下載與檔案這一組照 Legado 以快取資料夾為準、帶書源標頭與網址選項
  // type，和網址選項一起補（HANDOFF）。
  'java.deleteFile': '下載與檔案一組，隨網址選項 type 一起補',
  'java.getFile': '下載與檔案一組，隨網址選項 type 一起補',
  'java.getZipStringContent': '下載與檔案一組，隨網址選項 type 一起補',
  'java.unzipFile': '下載與檔案一組，隨網址選項 type 一起補',
};

// 不列的 Legado 公開方法（只給 Legado 自己用，書源程式碰不到或不該碰）：
// AnalyzeRule 的 evalJS、getParamSize、makeUpRule、splitSourceRule；
// BaseSource.loginUi（和書源欄位 loginUi 同名，規則 JS 讀到的是欄位）；
// CookieStore 介面以外的內部方法；CacheManager 的 clearSourceVariables（登出
// 時 App 自己清）、getQueryTTF、sizeOf（內部的字型與容量管理）、
// getByteArray（二進位快取，和下載與檔案一組補）。

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
      for (final method in methods) {
        final name = '$object.$method';
        if (_notProvided.containsKey(name)) continue;
        final type = runtime.evaluate('typeof $name').stringResult;
        if (type != 'function') missing.add(name);
      }
    }
    expect(missing, isEmpty, reason: '夜讀少了這些 Legado 方法');
  }, skip: skip);
}
