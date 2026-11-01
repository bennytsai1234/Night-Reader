import 'dart:convert';
import 'dart:io';

import 'package:flutter_js/flutter_js.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/js/js_extensions.dart';

import '../../../support/source_isolate_harness.dart';
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

/// `model/analyzeRule/AnalyzeUrl.kt`：網址裡的 JS 與登入檢查裡的 `java`
/// 是這個請求，多了這些（屬性另外看 `url`、`headerMap`）。
const _analyzeUrl = [
  'initUrl',
  'getStrResponse',
  'getResponse',
  'getByteArray',
  'getInputStream',
  'getUserAgent',
  'isPost',
  'getSource',
  'put',
  'get',
  'evalJS',
];

// 不列的 Legado 公開方法：
// - AnalyzeUrl 的 getGlideUrl、getMediaItem、upload：Legado 自己載圖片、
//   播放與上傳用，書源用不到。
// - AnalyzeRule.splitSourceRule：傳回 Legado 內部的規則物件，書源用不到。
// - BaseSource.loginUi()：和書源的 loginUi 欄位同名，Rhino 裡書源讀到的是欄位。
// - CacheManager.sizeOf：LruCache 內部算大小用的。clearSourceVariables、
//   getQueryTTF 在 Legado 的 AppCacheManager，不是 cache。

/// Legado 帶的 Jsoup 1.16.2（`gradle/libs.versions.toml`）每個類別的公開
/// 方法，含繼承來的（照 `javap -public` 列出）。規則 JS 拿到的節點、元素
/// 清單、`Jsoup.connect` 的連線都要有；刻意不做的列在 [_jsoupNotProvided]。
const _jsoup = <String, List<String>>{
  'element': [
    'absUrl',
    'addClass',
    'after',
    'append',
    'appendChild',
    'appendChildren',
    'appendElement',
    'appendText',
    'appendTo',
    'attr',
    'attributes',
    'attributesSize',
    'baseUri',
    'before',
    'child',
    'childNode',
    'childNodeSize',
    'childNodes',
    'childNodesCopy',
    'children',
    'childrenSize',
    'className',
    'classNames',
    'clearAttributes',
    'clone',
    'closest',
    'cssSelector',
    'data',
    'dataNodes',
    'dataset',
    'elementSiblingIndex',
    'empty',
    'endSourceRange',
    'equals',
    'expectFirst',
    'filter',
    'firstChild',
    'firstElementChild',
    'firstElementSibling',
    'forEach',
    'forEachNode',
    'getAllElements',
    'getElementById',
    'getElementsByAttribute',
    'getElementsByAttributeStarting',
    'getElementsByAttributeValue',
    'getElementsByAttributeValueContaining',
    'getElementsByAttributeValueEnding',
    'getElementsByAttributeValueMatching',
    'getElementsByAttributeValueNot',
    'getElementsByAttributeValueStarting',
    'getElementsByClass',
    'getElementsByIndexEquals',
    'getElementsByIndexGreaterThan',
    'getElementsByIndexLessThan',
    'getElementsByTag',
    'getElementsContainingOwnText',
    'getElementsContainingText',
    'getElementsMatchingOwnText',
    'getElementsMatchingText',
    'hasAttr',
    'hasClass',
    'hasParent',
    'hasSameValue',
    'hasText',
    'hashCode',
    'html',
    'id',
    'insertChildren',
    'is',
    'isBlock',
    'lastChild',
    'lastElementChild',
    'lastElementSibling',
    'nextElementSibling',
    'nextElementSiblings',
    'nextSibling',
    'nodeName',
    'normalName',
    'outerHtml',
    'ownText',
    'ownerDocument',
    'parent',
    'parentNode',
    'parents',
    'prepend',
    'prependChild',
    'prependChildren',
    'prependElement',
    'prependText',
    'previousElementSibling',
    'previousElementSiblings',
    'previousSibling',
    'remove',
    'removeAttr',
    'removeClass',
    'replaceWith',
    'root',
    'select',
    'selectFirst',
    'selectXpath',
    'setBaseUri',
    'shallowClone',
    'siblingElements',
    'siblingIndex',
    'siblingNodes',
    'sourceRange',
    'tag',
    'tagName',
    'text',
    'textNodes',
    'toString',
    'toggleClass',
    'traverse',
    'unwrap',
    'val',
    'wholeOwnText',
    'wholeText',
    'wrap',
  ],
  // Document 繼承 Element；createShell 是靜態方法，另外看類別。
  'document': [
    'body',
    'charset',
    'connection',
    'createElement',
    'documentType',
    'expectForm',
    'forms',
    'head',
    'location',
    'outputSettings',
    'parser',
    'quirksMode',
    'title',
    'updateMetaCharsetElement',
  ],
  // Node（含 LeafNode）：TextNode、DataNode、Comment 都有。
  'node': [
    'absUrl',
    'after',
    'attr',
    'attributes',
    'attributesSize',
    'baseUri',
    'before',
    'childNode',
    'childNodeSize',
    'childNodes',
    'childNodesCopy',
    'clearAttributes',
    'clone',
    'empty',
    'equals',
    'filter',
    'firstChild',
    'forEachNode',
    'hasAttr',
    'hasParent',
    'hasSameValue',
    'hashCode',
    'html',
    'lastChild',
    'nextSibling',
    'nodeName',
    'normalName',
    'outerHtml',
    'ownerDocument',
    'parent',
    'parentNode',
    'previousSibling',
    'remove',
    'removeAttr',
    'replaceWith',
    'root',
    'setBaseUri',
    'shallowClone',
    'siblingIndex',
    'siblingNodes',
    'sourceRange',
    'toString',
    'traverse',
    'unwrap',
    'wrap',
  ],
  'textNode': ['getWholeText', 'isBlank', 'splitText', 'text'],
  'dataNode': ['getWholeData', 'setWholeData'],
  'comment': ['asXmlDeclaration', 'getData', 'isXmlDeclaration', 'setData'],
  'elements': [
    'addClass',
    'after',
    'append',
    'attr',
    'before',
    'clone',
    'comments',
    'dataNodes',
    'eachAttr',
    'eachText',
    'empty',
    'eq',
    'filter',
    'first',
    'forms',
    'hasAttr',
    'hasClass',
    'hasText',
    'html',
    'is',
    'last',
    'next',
    'nextAll',
    'not',
    'outerHtml',
    'parents',
    'prepend',
    'prev',
    'prevAll',
    'remove',
    'removeAttr',
    'removeClass',
    'select',
    'tagName',
    'text',
    'textNodes',
    'toString',
    'toggleClass',
    'traverse',
    'unwrap',
    'val',
    'wrap',
  ],
  'jsoup': [
    'clean',
    'connect',
    'isValid',
    'newSession',
    'parse',
    'parseBodyFragment',
  ],
  'connection': [
    'cookie',
    'cookieStore',
    'cookies',
    'data',
    'execute',
    'followRedirects',
    'get',
    'header',
    'headers',
    'ignoreContentType',
    'ignoreHttpErrors',
    'maxBodySize',
    'method',
    'newRequest',
    'parser',
    'post',
    'postDataCharset',
    'proxy',
    'referrer',
    'request',
    'requestBody',
    'response',
    'sslSocketFactory',
    'timeout',
    'url',
    'userAgent',
  ],
  'request': [
    'addHeader',
    'cookie',
    'cookies',
    'data',
    'followRedirects',
    'hasCookie',
    'hasHeader',
    'hasHeaderWithValue',
    'header',
    'headers',
    'ignoreContentType',
    'ignoreHttpErrors',
    'maxBodySize',
    'method',
    'multiHeaders',
    'parser',
    'postDataCharset',
    'proxy',
    'removeCookie',
    'removeHeader',
    'requestBody',
    'sslSocketFactory',
    'timeout',
    'url',
  ],
  'response': [
    'addHeader',
    'body',
    'bodyAsBytes',
    'bodyStream',
    'bufferUp',
    'charset',
    'contentType',
    'cookie',
    'cookies',
    'hasCookie',
    'hasHeader',
    'hasHeaderWithValue',
    'header',
    'headers',
    'method',
    'multiHeaders',
    'parse',
    'removeCookie',
    'removeHeader',
    'statusCode',
    'statusMessage',
    'url',
  ],
  'keyVal': ['contentType', 'hasInputStream', 'inputStream', 'key', 'value'],
  'method': ['valueOf', 'values'],
  'methodValue': ['hasBody', 'name', 'ordinal'],
  'statics': [
    'org.jsoup.nodes.Document.createShell',
    'org.jsoup.nodes.TextNode.createFromEncoded',
  ],
};

/// Kotlin 欄位在 Java 的 getter／setter：`var x` 是 getX()／setX()，
/// `var isX: Boolean` 是 isX()／setX()。
List<String> _beanMethods(List<String> fields) => [
  for (final field in fields)
    if (RegExp(r'^is[A-Z]').hasMatch(field)) ...[
      field,
      'set${field.substring(2)}',
    ] else ...[
      'get${field[0].toUpperCase()}${field.substring(1)}',
      'set${field[0].toUpperCase()}${field.substring(1)}',
    ],
];

/// 規則 JS 拿到的 `book`、`chapter`、`source`（Legado 的 Book、BookChapter、
/// BookSource 實體）的公開方法，照 `data/entities/` 的原始碼列。
final _entities = <String, List<String>>{
  'book': [
    ..._beanMethods([
      'bookUrl',
      'tocUrl',
      'origin',
      'originName',
      'name',
      'author',
      'kind',
      'customTag',
      'coverUrl',
      'customCoverUrl',
      'intro',
      'customIntro',
      'charset',
      'type',
      'group',
      'latestChapterTitle',
      'latestChapterTime',
      'lastCheckTime',
      'lastCheckCount',
      'totalChapterNum',
      'durChapterTitle',
      'durChapterIndex',
      'durChapterPos',
      'durChapterTime',
      'wordCount',
      'canUpdate',
      'order',
      'originOrder',
      'variable',
      'readConfig',
      'syncTime',
      'infoHtml',
      'tocHtml',
      'downloadUrls',
    ]),
    // Book.kt、BaseBook.kt、RuleDataInterface.kt
    'getRealAuthor', 'getUnreadChapterNum', 'getDisplayCover',
    'getDisplayIntro', 'setReverseToc', 'getReverseToc', 'setUseReplaceRule',
    'getUseReplaceRule', 'putCustomVariable', 'getCustomVariable',
    'getKindList', 'getVariable', 'putVariable', 'getBigVariable',
    'putBigVariable', 'upCustomIntro', 'fileCharset', 'setReSegment',
    'getReSegment', 'setPageAnim', 'getPageAnim', 'setImageStyle',
    'getImageStyle', 'setTtsEngine', 'getTtsEngine', 'setSplitLongChapter',
    'getSplitLongChapter', 'setReadSimulating', 'getReadSimulating',
    'setStartDate', 'getStartDate', 'setStartChapter', 'getStartChapter',
    'setDailyChapters', 'getDailyChapters', 'getDelTag', 'addDelTag',
    'removeDelTag', 'getFolderName', 'toSearchBook', 'migrateTo',
    'createBookMark', 'save', 'delete', 'getLastChapterIndex', 'getConfig',
    'getVariableMap',
  ],
  'chapter': [
    ..._beanMethods([
      'url',
      'title',
      'isVolume',
      'baseUrl',
      'bookUrl',
      'index',
      'isVip',
      'isPay',
      'resourceUrl',
      'tag',
      'wordCount',
      'start',
      'end',
      'startFragmentId',
      'endFragmentId',
      'variable',
      'titleMD5',
    ]),
    'primaryStr',
    'getDisplayTitle',
    'getAbsoluteURL',
    'getFileName',
    'getFontName',
    'getVariable',
    'putVariable',
    'getBigVariable',
    'putBigVariable',
    'getVariableMap',
  ],
  'source': _beanMethods([
    'bookSourceUrl',
    'bookSourceName',
    'bookSourceGroup',
    'bookSourceType',
    'bookUrlPattern',
    'customOrder',
    'enabled',
    'enabledExplore',
    'jsLib',
    'enabledCookieJar',
    'concurrentRate',
    'header',
    'loginUrl',
    'loginUi',
    'loginCheckJs',
    'coverDecodeJs',
    'bookSourceComment',
    'variableComment',
    'lastUpdateTime',
    'respondTime',
    'weight',
    'exploreUrl',
    'exploreScreen',
    'ruleExplore',
    'searchUrl',
    'ruleSearch',
    'ruleBookInfo',
    'ruleToc',
    'ruleContent',
    'ruleReview',
  ]),
};

/// `book`、`chapter`、`source` 刻意不做的方法與理由。
const _entitiesNotProvided = <String, Set<String>>{
  'book': {
    // 夜讀不留書籍詳情、目錄的網頁原文，也沒有下載網址清單（Legado 給
    // 聽書、檔案書用）。
    'getInfoHtml', 'setInfoHtml', 'getTocHtml', 'setTocHtml',
    'getDownloadUrls', 'setDownloadUrls',
    // 閱讀器的設定（分段、翻頁動畫、圖片樣式、朗讀引擎、長章節、模擬
    // 追讀、去標籤）是 Legado 閱讀介面的，夜讀的閱讀器沒有這些設定。
    'upCustomIntro', 'fileCharset', 'setReSegment', 'getReSegment',
    'setPageAnim', 'getPageAnim', 'setImageStyle', 'getImageStyle',
    'setTtsEngine', 'getTtsEngine', 'setSplitLongChapter',
    'getSplitLongChapter', 'setReadSimulating', 'getReadSimulating',
    'setStartDate', 'getStartDate', 'setStartChapter', 'getStartChapter',
    'setDailyChapters', 'getDailyChapters', 'getDelTag', 'addDelTag',
    'removeDelTag', 'getConfig',
    // 存檔、刪書、換源搬移、書籤、轉成搜尋結果：App 自己的動作，書源程式
    // 不該在抓取途中做。
    'getFolderName', 'toSearchBook', 'migrateTo', 'createBookMark', 'save',
    'delete',
    // Kotlin 內部用的計算值與變數表；書源用 getVariable／putVariable。
    'getLastChapterIndex', 'getVariableMap',
  },
  'chapter': {
    // 顯示用（套替換規則與繁簡、檔名、字型名），書源程式用不到。
    'primaryStr', 'getDisplayTitle', 'getAbsoluteURL', 'getFileName',
    'getFontName', 'getTitleMD5', 'setTitleMD5', 'getVariableMap',
  },
  'source': {
    // 書源的規則物件與發現篩選：夜讀交給 JS 的書源只有欄位文字，規則
    // 物件不在裡面。
    'getRuleExplore', 'setRuleExplore', 'getRuleSearch', 'setRuleSearch',
    'getRuleBookInfo', 'setRuleBookInfo', 'getRuleToc', 'setRuleToc',
    'getRuleContent', 'setRuleContent', 'getRuleReview', 'setRuleReview',
    'getExploreScreen', 'setExploreScreen',
  },
};

/// Jsoup 刻意不做的方法與理由。
const _jsoupNotProvided = <String, Set<String>>{
  // 解析時的原始位置：Jsoup 預設不記，Legado 也沒開，書源拿到的永遠是空的。
  'element': {'sourceRange', 'endSourceRange'},
  'node': {'sourceRange'},
  // 輸出設定、解析器、文件類型與 Java 的字元集物件：夜讀用另一套 HTML
  // 函式庫解析與輸出，沒有這些設定，書源讀網頁用 html()、text()。
  // connection() 只有 Jsoup 自己抓來的文件才有，書源的文件來自規則。
  'document': {
    'charset',
    'connection',
    'documentType',
    'outputSettings',
    'parser',
    'quirksMode',
    'updateMetaCharsetElement',
  },
  // 傳回 XmlDeclaration 物件，只有 XML 宣告用得到。
  'comment': {'asXmlDeclaration'},
  // 要 Safelist 整套白名單規則；源倉庫的書源沒有用到。
  'jsoup': {'clean', 'isValid'},
  // Java 的網路物件與解析器設定。
  'connection': {'cookieStore', 'parser', 'proxy', 'sslSocketFactory'},
  'request': {'parser', 'proxy', 'sslSocketFactory'},
  // Java 的串流；書源用 body()、bodyAsBytes()。
  'response': {'bodyStream'},
};

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
        final name = '$object.$method';
        final type = runtime.evaluate('typeof $name').stringResult;
        if (type != 'function') missing.add(name);
      }
    }
    expect(missing, isEmpty, reason: '夜讀少了這些 Legado 方法');
  }, skip: skip);

  test('book、chapter、source 有 Legado 實體的每個公開方法', () {
    final rule = AnalyzeRule(
      ruleData: Book(bookUrl: 'https://a.test/b', name: '書'),
      source: BookSource(bookSourceUrl: 'https://a.test'),
    )..setChapter(BookChapter(url: 'https://a.test/c', title: '章'));
    addTearDown(rule.dispose);
    final missing = rule.evalJS('''
      var lists = ${jsonEncode(_entities)};
      var skipped = ${jsonEncode(_entitiesNotProvided.map((k, v) => MapEntry(k, v.toList())))};
      var targets = { book: book, chapter: chapter, source: source };
      var missing = [];
      Object.keys(lists).forEach(function(kind) {
        lists[kind].forEach(function(name) {
          if ((skipped[kind] || []).indexOf(name) >= 0) return;
          if (typeof targets[kind][name] !== 'function') missing.push(kind + '.' + name);
        });
      });
      missing.join(',')
    ''', null);
    expect(missing, isEmpty, reason: '夜讀的 book、chapter、source 少了這些方法');
  }, skip: skip);

  test('java in URL JS is the request, like Legado AnalyzeUrl', () {
    final url = AnalyzeUrl(
      'https://example.com/a<js>'
      'var missing = ${jsonEncode(_analyzeUrl)}.filter(function(m) {'
      '  return typeof java[m] !== "function"; });'
      'if (typeof java.url !== "string") missing.push("url");'
      'if (typeof java.headerMap.get !== "function") missing.push("headerMap");'
      'result + "?missing=" + missing.join("+")'
      '</js>',
    );
    expect(Uri.parse(url.url).queryParameters['missing'], isEmpty);
  }, skip: skip);

  // 回應要真的發一次請求，請求只能在書源 isolate 裡等（ADR 0034）。
  group('in the source isolate', () {
    final isolates = SourceIsolateHarness();
    late HttpServer server;
    late String baseUrl;
    setUpAll(() async {
      await isolates.start();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = 'http://${server.address.address}:${server.port}';
      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write('<p>ok</p>');
        await request.response.close();
      });
    });
    tearDownAll(() async {
      await server.close(force: true);
      await isolates.stop();
    });

    test('rule JS Jsoup has every public method of Jsoup 1.16.2', () async {
      final missing = await evaluateInSourceIsolate('''
      var doc = org.jsoup.Jsoup.parse('<p>a<!--c--></p><script>x</script>');
      var p = doc.selectFirst('p');
      var conn = org.jsoup.Jsoup.connect('$baseUrl/');
      var targets = {
        element: p, document: doc, textNode: p.childNode(0),
        dataNode: doc.selectFirst('script').childNode(0), comment: p.childNode(1),
        elements: doc.select('p'), jsoup: org.jsoup.Jsoup, connection: conn,
        request: conn.request(), response: conn.execute(),
        keyVal: conn.data('k', 'v').data('k'),
        method: org.jsoup.Connection.Method,
        methodValue: org.jsoup.Connection.Method.GET
      };
      var lists = ${jsonEncode(_jsoup)};
      var skipped = ${jsonEncode(_jsoupNotProvided.map((k, v) => MapEntry(k, v.toList())))};
      var missing = [];
      Object.keys(lists).forEach(function(kind) {
        lists[kind].forEach(function(name) {
          if ((skipped[kind] || []).indexOf(name) >= 0) return;
          if (kind === 'statics') {
            if (typeof eval(name) !== 'function') missing.push(name);
            return;
          }
          var checks = kind === 'node' ? ['textNode', 'dataNode', 'comment'] : [kind];
          checks.forEach(function(target) {
            if (typeof targets[target][name] !== 'function') missing.push(target + '.' + name);
          });
        });
      });
      missing.join(',')
    ''');
      expect(missing, isEmpty, reason: '夜讀的 Jsoup 少了這些方法');
    }, skip: skip);
  });
}
