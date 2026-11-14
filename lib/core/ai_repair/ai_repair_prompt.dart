import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:night_reader/core/models/source/source_site.dart';
import 'package:night_reader/core/engine/web_book/book_list_parser.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/chapter_content_kind.dart';

import 'ai_chat_client.dart';
import 'repair_pages.dart';
import 'source_probe.dart';

/// AI 呼叫的工具（[aiRepairTools]，ADR 0054）。
sealed class AiRepairCommand {
  const AiRepairCommand();

  /// 呼叫工具 [name]、參數 [json] 是哪個指令；沒有這個工具或少了必要的
  /// 參數時是 null（[aiRepairBadCall] 說哪裡不對）。
  static AiRepairCommand? fromCall(String name, Map<String, dynamic> json) {
    final note = (json['note'] ?? json['reason'])?.toString().trim() ?? '';
    final patch = json['patch'];
    final AiChange? change = patch is Map<String, dynamic>
        ? (source: null, patch: patch)
        : null;
    final page = _int(json['page']);
    return switch (name) {
      // 選填的參數型別不對也算讀不懂，不讓轉型丟出例外中止整件。
      'test'
          when change != null &&
              _stringOrNull(json['from']) &&
              _stringOrNull(json['url']) =>
        AiTest(
          change,
          note,
          from: json['from'] as String? ?? 'search',
          url: json['url'] as String?,
        ),
      'submit' when change != null => AiSubmit(change, note),
      'fetch' when json['url'] is String => AiFetch(
        json['url'] as String,
        note,
      ),
      'read' when page != null => AiRead(
        page,
        from: _int(json['from']) ?? 0,
        length: _int(json['length']) ?? defaultReadLength,
        raw: json['raw'] == true,
      ),
      'find' when page != null && json['text'] is String => AiFind(
        page,
        json['text'] as String,
        from: _int(json['from']) ?? 0,
      ),
      'parse' when page != null && json['as'] is String => AiParse(
        page,
        json['as'] as String,
        change,
      ),
      'js' when json['code'] is String => AiJs(json['code'] as String),
      'give_up' when aiGiveUpLabels.containsKey(json['why']) => AiGiveUp(
        note,
        why: json['why'] as String,
      ),
      _ => null,
    };
  }

  static bool _stringOrNull(Object? value) => value == null || value is String;

  /// JSON 裡的整數：數字或寫成字串的數字。
  static int? _int(Object? value) => switch (value) {
    final num number => number.toInt(),
    final String text => int.tryParse(text.trim()),
    _ => null,
  };
}

/// AI 改的書源：整份 [source]，或只有改動的欄位 [patch]（[applyAiChange]）。
typedef AiChange = ({
  Map<String, dynamic>? source,
  Map<String, dynamic>? patch,
});

/// 把 AI 的改動套到 [current]（[sourceForAi] 的格式）上：整份的照用；改動的
/// 逐欄蓋上去，規則物件逐項蓋，值是空字串或 null 的那一項拿掉。
Map<String, dynamic> applyAiChange(
  Map<String, dynamic> current,
  AiChange change,
) {
  if (change.source case final source?) return source;
  final out = jsonDecode(jsonEncode(current)) as Map<String, dynamic>;
  for (final MapEntry(:key, :value) in change.patch!.entries) {
    final existing = out[key];
    if (value is Map<String, dynamic> && existing is Map<String, dynamic>) {
      for (final MapEntry(key: field, value: rule) in value.entries) {
        if (rule == null || rule == '') {
          existing.remove(field);
        } else {
          existing[field] = rule;
        }
      }
    } else if (value == null || value == '') {
      out.remove(key);
    } else {
      out[key] = value;
    }
  }
  return out;
}

/// AI 的改動用了書源沒有的欄位時，說哪一個不對、可以用哪些；沒有是 null。
/// 不擋的話寫錯的欄位照收、什麼都沒改，解析與試抓的結果一片空白：2026-11-12
/// AI 修涨姿势把詳情規則寫成 `ruleInfo`（Legado 叫 `ruleBookInfo`），兩次各
/// 繞了好幾輪才發現。
String? aiChangeProblem(AiChange change) {
  final fields = change.source ?? change.patch ?? const {};
  final unknown = [
    for (final key in fields.keys)
      if (!_sourceFields.contains(key)) key,
  ];
  if (unknown.isNotEmpty) {
    return '書源沒有 ${unknown.join('、')} 這個欄位。規則物件是 '
        '${_ruleFields.keys.join('、')}；其他欄位：'
        '${_sourceFields.where((key) => !_ruleFields.containsKey(key)).join('、')}';
  }
  for (final MapEntry(:key, :value) in fields.entries) {
    final allowed = _ruleFields[key];
    if (allowed == null || value is! Map<String, dynamic>) continue;
    final wrong = [
      for (final item in value.keys)
        if (!allowed.contains(item)) item,
    ];
    if (wrong.isNotEmpty) {
      return '$key 沒有 ${wrong.join('、')} 這一項，可以用的：${allowed.join('、')}';
    }
  }
  return null;
}

/// 書源 JSON 的欄位（Legado 3.0 格式，[BookSource.toJson]）。
final Set<String> _sourceFields = BookSource.fromJson(const {
  'bookSourceUrl': '',
  'bookSourceName': '',
}).toJson().keys.toSet();

/// 每個規則物件可以寫的項目。
final Map<String, Set<String>> _ruleFields = {
  'ruleSearch': SearchRule().toJson().keys.toSet(),
  'ruleExplore': ExploreRule().toJson().keys.toSet(),
  'ruleBookInfo': BookInfoRule().toJson().keys.toSet(),
  'ruleToc': TocRule().toJson().keys.toSet(),
  'ruleContent': ContentRule().toJson().keys.toSet(),
  'ruleReview': ReviewRule().toJson().keys.toSet(),
};

/// 打開一頁看看（網站首頁、搜尋頁這類），不改書源。
final class AiFetch extends AiRepairCommand {
  const AiFetch(this.url, this.note);
  final String url;
  final String note;
}

/// 拿改過的書源試抓一次：從 [from]（`search`、`explore`、`info`、`toc`、`content`）
/// 開始，搜尋以外的段從 [url] 那一頁開始。
final class AiTest extends AiRepairCommand {
  const AiTest(this.change, this.note, {this.from = 'search', this.url});
  final AiChange change;
  final String note;
  final String from;
  final String? url;
}

/// 讀已經抓到的第 [page] 頁的一段。
final class AiRead extends AiRepairCommand {
  const AiRead(
    this.page, {
    this.from = 0,
    this.length = defaultReadLength,
    this.raw = false,
  });
  final int page;
  final int from;
  final int length;
  final bool raw;
}

/// 在第 [page] 頁找 [text]（正則，編不了時當純文字），從第 [from] 處起列。
final class AiFind extends AiRepairCommand {
  const AiFind(this.page, this.text, {this.from = 0});
  final int page;
  final String text;
  final int from;
}

/// 用改過的規則（[change]，沒給是目前的書源）把第 [page] 頁當成 [stage]
/// 解析。
final class AiParse extends AiRepairCommand {
  const AiParse(this.page, this.stage, this.change);
  final int page;
  final String stage;
  final AiChange? change;
}

/// 在書源規則 JS 的環境跑 [code]。
final class AiJs extends AiRepairCommand {
  const AiJs(this.code);
  final String code;
}

/// 交出改好的書源，夜讀校驗後套用。
final class AiSubmit extends AiRepairCommand {
  const AiSubmit(this.change, this.note);
  final AiChange change;
  final String note;
}

/// 修不好：[why] 是 [aiGiveUpLabels] 的其中一個，[reason] 是看到的證據。
final class AiGiveUp extends AiRepairCommand {
  const AiGiveUp(this.reason, {required this.why});
  final String reason;
  final String why;
}

/// 放棄的原因，固定這幾種（`agent-harness`：判定用固定選項）。修復頁照它寫
/// 「AI：要登入」這類。
const Map<String, String> aiGiveUpLabels = {
  'site_gone': '網站不在了',
  'login': '要登入',
  'paid': '要付費',
  'human_check': '要真人在網頁上驗證',
  'blocked': '網站擋下所有請求',
  'not_a_book': '不是小說、漫畫或有聲書',
  'site_broken': '網站的功能壞了',
  'rate_limited': '網站限流',
};

/// 同樣的指令與參數用同一個 key（迴圈數第幾次，`AgentCommand.key`）：指令的
/// JSON 拿掉說明（note、reason），欄位照名稱排序。
String aiRepairCommandKey(Map<String, dynamic> json) {
  Object? sorted(Object? value) => switch (value) {
    final Map<String, dynamic> map => {
      for (final key in map.keys.toList()..sort()) key: sorted(map[key]),
    },
    final List<dynamic> list => [for (final item in list) sorted(item)],
    _ => value,
  };
  final command = {...json}
    ..removeWhere((key, _) => key == 'note' || key == 'reason');
  try {
    return jsonEncode(sorted(command));
  } on JsonUnsupportedObjectError {
    // 數字超出範圍這類寫不回 JSON 的值。
    return '${sorted(command)}';
  }
}

/// AI 回的話與貼回的內容最多幾個字：一個書源的 JSON 遠小於這個。
const int aiRepairMaxReplyLength = 300000;

/// [text] 裡第一個讀得懂的 JSON 物件：AI 常在前後加說明、或包在 ``` 裡。
/// Legado 匯出的書源是陣列，取第一個物件。每個 `{` 都要往後數到配對的
/// `}`，最多試前 [_maxJsonStarts] 個，一堆沒配對的括號不會數很久。
Map<String, dynamic>? extractJsonObject(String text) {
  if (text.length > aiRepairMaxReplyLength) return null;
  var tries = 0;
  for (
    var start = text.indexOf('{');
    start >= 0 && tries < _maxJsonStarts;
    start = text.indexOf('{', start + 1), tries++
  ) {
    final end = _matchingBrace(text, start);
    if (end == null) {
      // AI 寫長的書源常少了最後幾個 `}`：補上再試。
      final closed = _closeUnbalanced(text.substring(start));
      if (closed == null) continue;
      try {
        final decoded = jsonDecode(closed);
        if (decoded is Map<String, dynamic>) return decoded;
      } on FormatException {
        continue;
      }
      continue;
    }
    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      continue;
    }
  }
  return null;
}

const int _maxJsonStarts = 50;

/// [text] 從 `{` 開始、到結尾都沒配對完：去掉結尾的空白與 ``` 後補上缺的
/// `]` 與 `}`（最多六層）；字串沒結束、或括號配錯時是 null。
String? _closeUnbalanced(String text) {
  var body = text.trimRight();
  if (body.endsWith('```')) {
    body = body.substring(0, body.length - 3).trimRight();
  }
  // 照順序記下還沒關的 { 與 [，最後倒著補上。
  final open = <String>[];
  var inString = false;
  for (var i = 0; i < body.length; i++) {
    final char = body[i];
    if (inString) {
      if (char == r'\') {
        i++;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }
    switch (char) {
      case '"':
        inString = true;
      case '{' || '[':
        open.add(char);
      case '}' || ']':
        if (open.isEmpty || open.removeLast() != (char == '}' ? '{' : '[')) {
          return null;
        }
    }
  }
  if (inString || open.isEmpty || open.length > 6) return null;
  return body +
      [for (final char in open.reversed) char == '{' ? '}' : ']'].join();
}

/// 從 [start] 的 `{` 數到配對的 `}`，跳過字串裡的括號。
int? _matchingBrace(String text, int start) {
  var depth = 0;
  var inString = false;
  for (var i = start; i < text.length; i++) {
    final char = text[i];
    if (inString) {
      if (char == r'\') {
        i++;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }
    switch (char) {
      case '"':
        inString = true;
      case '{':
        depth++;
      case '}':
        depth--;
        if (depth == 0) return i;
    }
  }
  return null;
}

/// 貼回來的內容裡的書源：AI 照提示詞回的是書源本身，也接受包成指令的。
Map<String, dynamic>? pastedSourceJson(String text) {
  final json = extractJsonObject(text);
  if (json == null) return null;
  if (json['source'] case final Map<String, dynamic> source) return source;
  return json.containsKey('bookSourceUrl') ? json : null;
}

/// 送給 AI 的書源：去掉校驗加的狀態分組與錯誤註解，空的欄位、排序與開關
/// 這類夜讀照原本留著的（[candidateFrom]）不送；規則攤開成物件。登入資料、
/// Cookie 與書源變數不在書源 JSON 裡（ADR 0054）。
Map<String, dynamic> sourceForAi(BookSource source) {
  final copy = BookSource.fromJson(source.toJson())
    ..removeInvalidGroups()
    ..removeErrorComment();
  final json = copy.toJson()
    ..removeWhere((key, _) => _keptFromOriginal.contains(key));
  for (final MapEntry(:key, :value) in json.entries.toList()) {
    if (key.startsWith('rule') && value is String) {
      try {
        if (jsonDecode(value) case final Map<String, dynamic> rule) {
          json[key] = rule;
        }
      } on FormatException {
        // 不是 JSON 的照原字串送。
      }
    }
  }
  return _withoutEmpty(json);
}

const Set<String> _keptFromOriginal = {
  'customOrder',
  'weight',
  'enabled',
  'enabledExplore',
  'lastUpdateTime',
  'respondTime',
};

Map<String, dynamic> _withoutEmpty(Map<String, dynamic> json) {
  final out = <String, dynamic>{};
  for (final MapEntry(:key, :value) in json.entries) {
    if (value is Map<String, dynamic>) {
      final inner = _withoutEmpty(value);
      if (inner.isNotEmpty) out[key] = inner;
    } else if (value != null && value != '') {
      out[key] = value;
    }
  }
  return out;
}

/// AI 改過的書源：規則照 AI 的，名稱與使用者自己的設定照原本的——名稱、
/// 分組、排序、開關、權重與註解。網址只接受換開頭（[siteMovedUrl]）：網站
/// 搬家、或只有 https、沒有 www 的那個開頭能用時。改完還是聚合源的，類型也
/// 照原本的（ADR 0056）。
BookSource candidateFrom(BookSource original, Map<String, dynamic> json) {
  final base = BookSource.fromJson(original.toJson())..removeErrorComment();
  final candidate = BookSource.fromJson(json);
  if (candidate.isAggregateSource) {
    candidate.bookSourceType = original.bookSourceType;
  }
  return candidate
    ..bookSourceUrl = siteMovedUrl(
      original.bookSourceUrl,
      json['bookSourceUrl'] as String?,
    )
    ..bookSourceName = original.bookSourceName
    ..bookSourceGroup = original.bookSourceGroup
    ..bookSourceComment = base.bookSourceComment
    ..customOrder = original.customOrder
    ..enabled = original.enabled
    ..enabledExplore = original.enabledExplore
    ..weight = original.weight
    ..respondTime = original.respondTime
    ..lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
}

/// 書源網址換開頭：[proposed] 的協定與主機（含連接埠）接上 [original] 開頭
/// 之後的部分（路徑與 `#` 後面的標記）。[proposed] 讀不出主機、或開頭一樣
/// 時照 [original]。
String siteMovedUrl(String original, String? proposed) {
  final from = siteOrigin(original);
  final to = proposed == null ? null : siteOrigin(proposed)?.toLowerCase();
  if (from == null || to == null || from.toLowerCase() == to) return original;
  return '$to${original.trimLeft().substring(from.length)}';
}

/// AI 改了哪幾類規則，例如「正文、目錄」；沒改是空字串。
String changedParts(BookSource before, BookSource after) {
  final a = _flatten(sourceForAi(before));
  final b = _flatten(sourceForAi(after));
  final keys = {...a.keys, ...b.keys}.where((key) => a[key] != b[key]);
  final parts = <String>{
    for (final key in keys) _partLabel(key.split('.').first),
  };
  const order = [
    '網址',
    '類型',
    '搜尋',
    '發現',
    '詳情',
    '目錄',
    '正文',
    '標頭',
    '程式庫',
    '登入',
    '其他',
  ];
  return [
    for (final part in order)
      if (parts.contains(part)) part,
  ].join('、');
}

String _partLabel(String key) => switch (key) {
  'bookSourceUrl' => '網址',
  'bookSourceType' => '類型',
  'searchUrl' || 'ruleSearch' => '搜尋',
  'exploreUrl' || 'ruleExplore' || 'exploreScreen' => '發現',
  'ruleBookInfo' || 'bookUrlPattern' => '詳情',
  'ruleToc' => '目錄',
  'ruleContent' => '正文',
  'header' => '標頭',
  'jsLib' => '程式庫',
  'loginUrl' || 'loginUi' || 'loginCheckJs' => '登入',
  _ => '其他',
};

Map<String, Object?> _flatten(Map<String, dynamic> json, [String prefix = '']) {
  final out = <String, Object?>{};
  for (final MapEntry(:key, :value) in json.entries) {
    final path = prefix.isEmpty ? key : '$prefix.$key';
    if (value is Map<String, dynamic>) {
      out.addAll(_flatten(value, path));
    } else {
      out[path] = value is List ? jsonEncode(value) : value;
    }
  }
  return out;
}

const String _rules =
    '''
書源是 Legado 3.0（閱讀 App）格式的 JSON，夜讀照同樣的規則解析。
- bookSourceType：0 小說（正文是成段文字）、1 有聲（正文是音訊網址）、2 漫畫（正文是圖片網址）。照抓到的正文判斷，不照名稱猜。規則裡用 book.type = … 逐本書設定類型的書源（聚合源，正文是哪一類看登入表單選的模式）不改類型。
  - 正文怎樣算抓到（試抓與校驗都照這個）：小說去掉圖片後至少 $chapterTextMinRunes 字，整章只有圖不算；漫畫至少一張圖；有聲至少一個網址。校驗也照抓到的正文改類型：去掉圖片與網址後至少 ${ChapterContentKind.novelMinRunes} 字是小說，至少 ${ChapterContentKind.comicMinImages} 張圖、不到 ${ChapterContentKind.comicMaxRunes} 字是漫畫，其他照書源原本的類型。
- 規則語法照 Legado：JSOUP Default（class.xxx.0@tag.a@href）、CSS（@css:）、XPath（//）、JSONPath（\$.）、正則替換（##正則##替換）、<js></js> 與 @js:、{{ }} 內嵌、@put／@get。網址規則可以接 ,{"method":"POST","body":"...","charset":"gbk"}。
- 目錄或一章正文分成好幾頁時，用 ruleToc.nextTocUrl、ruleContent.nextContentUrl 寫抓「下一頁」網址的規則（例如 a#next@href），夜讀照它一頁一頁抓下去、接成完整的目錄或一章。
- 規則 JS 裡可用（同 Legado）：變數 result、baseUrl、book、source；key、page 只有網址規則（searchUrl、exploreUrl 這類）的 JS 有，解析規則（bookList 這類）的 JS 沒有。
  - result 是這條規則前一段的結果。書單裡每本書的欄位規則（name、bookUrl 這類）直接用 JS 時，result 是這本書那一塊網頁元素（接成字串是它的 HTML），java.getString(規則) 也在這一塊裡找。
  - 抓網頁：java.ajax(網址) 直接傳回內容字串，只收網址一個參數，方法、內文、標頭寫在網址後面（網址,{"method":"POST","body":"...","headers":{"名稱":"值"}}）；java.post(網址, 內文, 標頭物件)、java.get(網址, 標頭物件)、java.connect(網址) 或 java.connect(網址, 標頭物件) 傳回回應物件，內容要用 .body()，狀態碼 .code()、網址 .url()、標頭 .headers()。標頭物件直接是 {"名稱":"值"}，外面不包 headers。java.ajax、java.connect 照書源的標頭與 Cookie 送；java.get、java.post 只送你給的標頭，enabledCookieJar 是 1 時再加上存著的 Cookie。java.get 抓網頁一定要給標頭物件（可以是 {}）：只給一個參數的 java.get(名稱) 是讀變數。
  - 解析：java.setContent(html) 之後 java.getString(規則)、java.getStringList(規則)、java.getElements(規則)。
  - 編碼：java.base64Decode(字串)、java.base64Encode、java.md5Encode、java.encodeURI、java.t2s、java.s2t、java.createSymmetricCrypto(…)。
  - 變數與 Cookie：java.put(名稱, 值)、java.get(名稱)；cookie.getCookie(網址)、cookie.setCookie(網址, 值)。
  - 沒有 Android 的類別（android.util.Base64 這類）。字串是 JS 字串：長度是 .length，不是 Java 的 .length()。報「TypeError: not a function」多半是把回應物件當字串用（少了 .body()）、對字串呼叫 Java 的方法，或用了這裡沒有的函式。
- enabledCookieJar（Cookie 罐）：1 時網站回的 Cookie 存下來，這個書源之後的請求都帶上，網站靠工作階段 Cookie 記住驗證、登入或搜尋狀態時要開；0 時網站回的 Cookie 不存，每個請求都像第一次來（請求紀錄會寫出沒存的 Cookie）。cookie.setCookie 存的兩種都帶。
- 名稱、分組這些不用改，夜讀會照原本的；只改需要改的規則，其他照原樣留著。網站搬了家，或只有某個開頭（https、有沒有 www、新網域）連得上時，可以改 bookSourceUrl 的開頭（https://網域），後面的部分夜讀照原本的；書架上用這個書源的書會跟著搬。
''';

const String _method =
    '''
## 怎麼查
- 先看開場的校驗結果與試抓：哪一段失敗、網站實際回了什麼。網站回了正常的內容、規則卻抓不到（例如「未獲取到書籍」但回應裡有書單），問題在解析規則，網址與參數照舊；網站回的是錯誤、提示、驗證頁或轉址程式，才查網址、參數、標頭或網站本身。
- 每個抓到的網頁都有頁碼（頁 N），整頁存在夜讀這邊；回給你的只是精簡後的開頭。後面的內容用 read 讀；要知道某段文字在哪、它的選擇器怎麼寫，用 find；要看程式、<head> 與所有屬性，用 read 的 raw。
- 改了規則就 test：一次從指定的那一段（搜尋、發現頁、詳情頁、目錄頁或正文頁）一路抓到正文，每一段送了什麼、抓到什麼都回給你；要確認後面幾段，從那一段 test。test 不會交出：看過結果（書名、作者、目錄、正文都對）再用 submit 交出。試抓與校驗都從搜尋結果的第一本往下走；校驗遇到第一本打不開（詳情、目錄或正文失效）會改試第二本，兩本都打不開才算壞。第一本是下架或打不開的書時，用 test 的 from info 拿另一本試，不用為它改規則。parse 不連網站，只在已經抓到的那頁試解析，網站在限流時用它。
- 要試的是書源本身的設定（Cookie 罐、標頭、網址參數、編碼）時，寫進 patch 直接 test：比自己寫程式一步步模擬快，送出的也是夜讀實際會送的樣子。
- 網站對請求直接斷線、逾時或連回應都沒有時，先換送出的條件試：User-Agent（手機、桌機）、http 或 https、有沒有 www；換了哪一項就通，就把那一項寫進書源。
- 網站回的那頁不是內容時，先認出是哪一種再照做。要你隔一段時間再來的（限流）：等它說的間隔過了，再送一次同一個請求（試抓與校驗也會送，連續送太快被擋的算在裡面）；照常拿得到結果就照常修，等過一次還是被擋就用 give_up 的 rate_limited 放棄，不再等第二次，寫出網站說的話：限流到一般使用拿不到結果，找得到繞過的寫法也算壞了。要瀏覽器驗證或答題的（防護頁）：看能不能照它要的（例如寫入 Cookie）通過。用程式轉走的：照轉去的網址查。
- 這個網站做不到書源要的某一段，或慢到超過校驗的時限時（回應那一行寫了花幾秒，超時的訊息寫了時限），開場列出的別的網域與同一個網站的其他開頭可能做得到：鏡像、新網域、姊妹站，或同一個網站的電腦版（www.）與手機版（m.），這兩版常是不同的程式，同一段的網址與快慢都不一樣。先拿同一本書到那裡看同一段，做得到就換書源網址的開頭、規則照舊直接 test，沒過再看是哪一段要改；只有一段換到另一版時，那一段抓到的書籍網址要轉成書源其他段用的那一版。別的網域只看開場列出的、或網頁裡寫到的，不自己猜新網域；同一個網站換成 www. 或 m. 開頭不算猜。
- 搜尋與詳情抓到的書名、作者要一樣：書名加作者是夜讀認一本書的依據（搜尋結果合併、換源、書籤）。同一套網站的搜尋頁、分類頁常長得不一樣，借用同一份規則時兩種頁都要看。
- 回應那一行寫了（快取 HIT…）時，那頁是網站前面的快取伺服器存著的舊頁面：換關鍵字、加網址參數、等多久都一樣。搜尋頁這樣時，拿站上有的書名與不可能的詞各搜一次，回的一樣就是網站的搜尋壞了（site_broken）。
- 搜尋規則要抓的是搜尋結果：通過校驗後夜讀會用一個不可能有的詞再搜一次，前 5 本書名和用試抓關鍵字搜到的前 5 本一樣，就不算修好；網站搜不到時回固定的推薦書也沒關係，只要和搜得到時不一樣。網站的搜尋本身壞了時用 give_up 的 site_broken 放棄，證據是拿站上確實有的書名（首頁、排行列出的）搜，網站回的跟搜不可能的詞一樣。
- 試抓與校驗搜尋用的關鍵字是書源的 ruleSearch.checkKeyWord，沒寫時是開場除錯紀錄寫的那個（「開始搜尋關鍵字」）。站上搜不到這個詞，或這個詞的結果多到網站要很久才回時，把 checkKeyWord 改成站上確實有的書名（首頁、排行列出的）再 test，不用為這個詞改搜尋規則。
- 網站的內容不是小說、漫畫或有聲書時（例如一篇貼文當一本書的段子、新聞站，有的文章只有圖、有的只有字），用 give_up 的 not_a_book 放棄：不為了過校驗改類型，也不只抓其中一種文章。
- 放棄的證據到這樣就夠：那個功能在網站自己頁面上的做法（表單、連結送的地方）與開場列出的別的網域都試過，都做不到；不用把網站每個入口都試一遍。網站整個連不上或都轉到別處時，開場列出的別的網域試過就夠。
- 一個書源最多 ${AiAgentKnobs.maxRounds} 輪（每次回覆算一輪），用完算沒修完；每一步都要有目的，把想確認什麼寫在 note。
- 書源規則只放書源要用的規則；要跑程式查東西用 js。
''';

/// 改規則的參數：蓋到目前的書源上的欄位。
const Map<String, Object?> _patch = {
  'type': 'object',
  'description':
      '要改的欄位，蓋到目前的書源上：規則物件（ruleSearch 這類）逐項蓋，'
      '沒寫的項目照舊，值給空字串就拿掉那一項。只寫要改的欄位。',
};

const Map<String, Object?> _note = {
  'type': 'string',
  'description': '這一步想確認什麼',
};

const Map<String, Object?> _page = {
  'type': 'integer',
  'description': '頁碼：每個抓到的網頁都有一個（頁 N）',
};

Map<String, Object?> _object(
  Map<String, Object?> properties, [
  List<String> required = const [],
]) => {'type': 'object', 'properties': properties, 'required': required};

/// AI 修書源用的工具（服務的 function calling，ADR 0054）。說明寫這個工具
/// 做什麼、參數的意思；怎麼查寫在系統提示。
final List<AiTool> aiRepairTools = [
  (
    name: 'fetch',
    description:
        '看網頁：照書源的標頭與 Cookie 抓一頁。回覆寫出實際送出的方法與內容，'
        '回應標上頁碼，只給精簡後的開頭。',
    parameters: _object(
      {
        'url': {
          'type': 'string',
          'description':
              '網址，照書源網址規則的寫法：可以是相對書源網址的路徑，可以接 '
              ',{"method":"POST","body":"..."}；{{key}} 是試抓用的關鍵字。要看書源'
              '搜尋實際拿到什麼，直接用書源的 searchUrl。',
        },
        'note': _note,
      },
      ['url'],
    ),
  ),
  (
    name: 'read',
    description: '讀頁：讀已經抓到的一頁的一段，一次最多 $maxReadLength 字。',
    parameters: _object(
      {
        'page': _page,
        'from': {'type': 'integer', 'description': '從第幾字讀起，預設 0'},
        'length': {
          'type': 'integer',
          'description': '讀幾字，預設 $defaultReadLength',
        },
        'raw': {
          'type': 'boolean',
          'description': 'true 給原文（含程式、<head> 與所有屬性），預設給精簡後的',
        },
      },
      ['page'],
    ),
  ),
  (
    name: 'find',
    description:
        '找字：在一頁的文字與屬性值裡找，回共幾處與從第 from 處起最多 10 處：'
        '那個元素的選擇器路徑與它的 HTML。',
    parameters: _object(
      {
        'page': _page,
        'text': {'type': 'string', 'description': '要找的正則；編不了時當純文字找，回覆會說'},
        'from': {'type': 'integer', 'description': '從第幾處起列，預設 0'},
      },
      ['page', 'text'],
    ),
  ),
  (
    name: 'parse',
    description:
        '解析：用夜讀的解析程式把已經抓到的一頁當成某一段解析，不連網站。回解析'
        '到幾筆與前 5 筆的每個欄位；正文回字數、類型與開頭。',
    parameters: _object(
      {
        'page': _page,
        'as': {
          'type': 'string',
          'enum': ['search', 'explore', 'info', 'toc', 'content'],
          'description': '當成哪一段',
        },
        'patch': {
          ..._patch,
          'description': '${_patch['description']}沒給就用目前的書源。',
        },
      },
      ['page', 'as'],
    ),
  ),
  (
    name: 'js',
    description:
        '跑程式：在書源規則 JS 的環境跑，可用系統提示列的 java.* 與 source；'
        'page(頁碼) 傳回那一頁的原文，頁碼直接寫成數字（程式先照寫出的數字把'
        '那幾頁帶進來，用變數算出來的頁碼讀不到）。回傳回值與錯誤。',
    parameters: _object(
      {
        'code': {'type': 'string', 'description': '要跑的 JS'},
      },
      ['code'],
    ),
  ),
  (
    name: 'test',
    description:
        '試抓：拿改過的書源從某一段一路抓到第一章正文，回每一段送了什麼、抓到'
        '什麼。不會交出。',
    parameters: _object(
      {
        'patch': _patch,
        'from': {
          'type': 'string',
          'enum': ['search', 'explore', 'info', 'toc', 'content'],
          'description': '從哪一段開始，預設 search（用試抓的關鍵字搜尋）',
        },
        'url': {
          'type': 'string',
          'description':
              'from 不是 search 時要給：發現頁（照 exploreUrl 裡的寫法）、詳情頁、'
              '目錄頁或正文頁的網址',
        },
        'note': _note,
      },
      ['patch'],
    ),
  ),
  (
    name: 'submit',
    description:
        '交出：看過試抓結果、確定改對了就用（試抓走不到正文但確定改對了也用，'
        '例如正文要付費）。夜讀跑一次書源校驗（換第二本書、抽查前幾章），通過'
        '才套用；沒過會回校驗的結論與診斷。',
    parameters: _object({'patch': _patch, 'note': _note}, ['patch']),
  ),
  (
    name: 'give_up',
    description: '放棄：拿出修不好的證據。',
    parameters: _object(
      {
        'why': {
          'type': 'string',
          'enum': aiGiveUpLabels.keys.toList(),
          'description':
              '原因：照順序問，第一個答「是」的就選它。'
              'site_gone：網域查不到、每個網址都連不上（沒有回應、連線被拒）、只剩'
              '停放頁，或每個網址最後落到的頁面都沒有這個書源的書（例如整站都回同一個'
              '錯誤頁：5xx、資料庫連不上）？login：內容要登入帳號才給？'
              'paid：有要付費、VIP 或解鎖才給的章節（前面幾章免費也算）？'
              'human_check：這個網站自己的頁面要真人驗證，驗證過後給的是這個網站的內容？'
              'blocked：網站擋下夜讀的所有請求？'
              'not_a_book：網站的內容不是小說、漫畫或有聲書（例如一篇貼文當一本書的'
              '段子、新聞站）？'
              'rate_limited：網站要你隔一段時間再來，等過它說的間隔再送同一個請求'
              '還是被擋（功能壞掉的一種：一般使用拿不到結果）？'
              'site_broken：網站在、其他頁面正常，書源要用的功能網站自己也做不到'
              '（例如搜什麼都回空的搜尋頁；網站另有做得到的地方，像 API 或別的網址，'
              '就不算）？',
        },
        'reason': {'type': 'string', 'description': '看到的證據：哪一頁、什麼內容'},
      },
      ['why', 'reason'],
    ),
  ),
];

/// 第一輪送給 AI 的話：系統提示與這個書源的現況。[probe] 的回應已經標上
/// 頁碼（[RepairPages.add]）。
List<AiMessage> aiRepairOpening({
  required BookSource source,
  required String checkResult,
  required SourceProbeReport probe,
}) => [
  const AiMessage.system(aiRepairSystemPrompt),
  AiMessage.user(_situation(source, checkResult, probe.indexText)),
];

/// 系統提示：每個書源都一樣，服務的快取每次都打得中。
const String aiRepairSystemPrompt =
    '你是夜讀的書源修復員：書源壞了，你要查出原因、改好規則，再用試抓證明修好了；'
    '或拿出證據說明修不好。也要判斷書源的類型。互不相依的查詢放在同一次回覆一起呼叫，要看前一個結果才知道下一步的留到下一次。\n\n'
    '$_rules\n$_method';

/// 提示詞的版本：系統提示與工具清單的雜湊開頭，寫進修復紀錄，比較前後時
/// 知道兩次用的是不是同一份。
final String aiRepairPromptVersion = sha1
    .convert(
      utf8.encode(
        '$aiRepairSystemPrompt\n${jsonEncode(aiToolsJson(aiRepairTools))}',
      ),
    )
    .toString()
    .substring(0, 8);

/// 完整紀錄裡一件的統計那一行的開頭，後面接 JSON（`tool/ai_repair_table.dart`
/// 照它整理成表）。
const String aiRepairStatsMarker = 'NR-AI-REPAIR-STATS ';

/// 沒有金鑰時複製給 AI 的整段話：使用者貼到任何 AI，再把回的書源貼回來。
String aiRepairClipboardPrompt({
  required BookSource source,
  required String checkResult,
  required SourceProbeReport probe,
}) =>
    '幫我修好這個書源，並判斷它的類型。\n\n$_rules\n'
    '修好後只回完整的書源 JSON（一個物件），不用其他說明。\n\n'
    // 貼給網頁版 AI：沒有讀頁的工具，照舊附網頁開頭。
    '${_situation(source, checkResult, probe.fullText)}';

String _situation(BookSource source, String checkResult, String probe) =>
    '# 書源\n```json\n'
    '${const JsonEncoder.withIndent('  ').convert(sourceForAi(source))}\n```\n\n'
    // 改了搜尋規則、發現頁跟著壞，原本要等交件被退才知道（2026-11-12、13
    // 涨姿势三次都是這樣）。
    '${_exploreBorrowsSearch(source) ? '$aiRepairExploreBorrowsSearch\n\n' : ''}'
    '${_sentBecause(source)}'
    '# 書源校驗的結果\n$checkResult\n\n'
    '# 試抓這個書源\n$probe';

/// 書源上次校驗留下的結論（狀態標記與錯誤註解）：整批修復沿用一天內的
/// 校驗送來，開場那次校驗可能已經沒問題（網站時好時壞）。2026-11-13 品书楼
/// 開場就沒問題，AI 不知道為什麼送來，把每一段都查了一遍（8 輪）。沒有留下
/// 結論是空字串。
String _sentBecause(BookSource source) {
  final health = source.runtimeHealth;
  final error = source.errorComment;
  if (health.category == SourceHealthCategory.healthy && error == null) {
    return '';
  }
  final label = health.category == SourceHealthCategory.healthy
      ? ''
      : health.label;
  final detail = [label, ?error].join('：');
  return '# 送來修的原因\n上一次校驗的結論：$detail。開場重新校驗的結果在下面；'
      '兩次不一樣時，先照上一次壞的那一段查。\n\n';
}

bool _exploreBorrowsSearch(BookSource source) =>
    (source.exploreUrl ?? '').trim().isNotEmpty &&
    BookListParser.exploreUsesSearchRule(source);

/// 發現頁沒有自己的書單規則、借用搜尋規則時告訴 AI 的話：開場一次，改了
/// 搜尋規則、只剩發現頁壞時再說一次。
const String aiRepairExploreBorrowsSearch = '這個書源的發現沒有自己的書單規則，發現頁用搜尋規則解析';

/// 搜尋規則抓到的是頁面上固定的書時的話：交出的書源，與開場原本的書源。
const String aiRepairUnrelatedSearch =
    '搜尋結果跟關鍵字無關：搜一個不可能有的詞也回同樣的書，抓到的是頁面上固定的推薦書';

/// 看網頁之後回給 AI 的話：[lines] 是送出的請求與標了頁碼的回應。
String aiRepairFetchReply(String url, List<String> lines) =>
    '# 看網頁 $url（精簡後，每頁只給開頭；其他段用 read）\n${lines.join('\n')}';

/// 試抓之後回給 AI 的話；搜尋與詳情的書名或作者不一樣時寫在最後
/// （[mismatch]，`searchInfoMismatch`）。
String aiRepairProbeReply(SourceProbeReport probe, {String? mismatch}) =>
    '# 試抓結果：${probe.summary}\n${probe.fullText}'
    '${mismatch == null ? '' : '\n\n# 書名或作者對不上：$mismatch'}';

/// 交出或試抓到正文、校驗卻沒過時回給 AI 的話：校驗的結論與它的診斷
/// （出錯的那一段送了什麼請求、網站回了什麼）。
String aiRepairCheckReply(String checkText, List<String> diagnostics) => [
  '# 書源校驗沒過：$checkText',
  if (diagnostics.isNotEmpty) diagnostics.join('\n\n'),
].join('\n');

/// 工具呼叫讀不懂時回給 AI 的話的開頭。
const String aiRepairBadCall = '# 讀不懂這個工具呼叫';

/// 改過的書源組不起來時回給它的話。
const String aiRepairBadSourceReply =
    '$aiRepairBadCall：改過的書源組不起來（欄位的型別或數值不對，例如數字超出範圍）';

/// 讀 AI 呼叫的一個工具：讀得懂時是指令與它的 key（[aiRepairCommandKey]），
/// 讀不懂時 [fact] 說哪裡不對（沒有這個工具、參數不是 JSON 物件、少了必要
/// 的參數）。
({AiRepairCommand? command, String key, String fact}) readAiRepairCall(
  AiToolCall call,
) {
  final tool = aiRepairTools
      .where((tool) => tool.name == call.name)
      .firstOrNull;
  if (tool == null) {
    return (
      command: null,
      key: '',
      fact:
          '$aiRepairBadCall：沒有叫 ${call.name} 的工具，有的是 '
          '${aiRepairTools.map((tool) => tool.name).join('、')}',
    );
  }
  final Object? args;
  try {
    args = call.arguments.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(call.arguments);
  } on FormatException catch (error) {
    return (
      command: null,
      key: '',
      fact: '$aiRepairBadCall（${call.name}）：參數不是合法的 JSON：${error.message}',
    );
  }
  if (args is! Map<String, dynamic>) {
    return (
      command: null,
      key: '',
      fact: '$aiRepairBadCall（${call.name}）：參數要是一個 JSON 物件',
    );
  }
  final command = AiRepairCommand.fromCall(call.name, args);
  if (command == null) {
    final required = tool.parameters['required']! as List<String>;
    return (
      command: null,
      key: '',
      fact:
          '$aiRepairBadCall（${call.name}）：少了必要的參數或值不對，'
          '要有 ${required.join('、')}',
    );
  }
  return (
    command: command,
    key: aiRepairCommandKey({...args, 'action': call.name}),
    fact: '',
  );
}
