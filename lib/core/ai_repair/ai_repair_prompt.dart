import 'dart:convert';

import 'package:night_reader/core/models/book_source.dart';

import 'ai_chat_client.dart';
import 'repair_pages.dart';
import 'site_check.dart';
import 'source_probe.dart';

/// AI 還沒試過任何修改就要放棄時回它的話。
const String aiRepairTryFirst =
    '你還沒試抓過任何修改。除非網站已經不在（網域查不到、整個網站只回錯誤頁），'
    '請先照你看到的網頁改規則並試抓一次；試過真的不行再放棄。';

/// AI 每一輪回的指令（ADR 0054）。
sealed class AiRepairCommand {
  const AiRepairCommand();

  /// 從 AI 回的話取出指令；讀不懂時是 null。
  static AiRepairCommand? parse(String reply) {
    final json = extractJsonObject(reply);
    if (json == null) return null;
    final note = (json['note'] ?? json['reason'])?.toString().trim() ?? '';
    final source = json['source'];
    final patch = json['patch'];
    final change = source is Map<String, dynamic>
        ? (source: source, patch: null)
        : patch is Map<String, dynamic>
        ? (source: null, patch: patch)
        : null;
    final page = _int(json['page']);
    return switch (json['action']) {
      'test' when change != null => AiTest(
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
      ),
      'parse' when page != null && json['as'] is String => AiParse(
        page,
        json['as'] as String,
        change,
      ),
      'js' when json['code'] is String => AiJs(json['code'] as String),
      'give_up' => AiGiveUp(note),
      _ => null,
    };
  }

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

/// 打開一頁看看（網站首頁、搜尋頁這類），不改書源。
final class AiFetch extends AiRepairCommand {
  const AiFetch(this.url, this.note);
  final String url;
  final String note;
}

/// 拿改過的書源試抓一次：從 [from]（`search`、`info`、`toc`、`content`）
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

/// 在第 [page] 頁找 [text]。
final class AiFind extends AiRepairCommand {
  const AiFind(this.page, this.text);
  final int page;
  final String text;
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

/// 修不好。
final class AiGiveUp extends AiRepairCommand {
  const AiGiveUp(this.reason);
  final String reason;
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

const String _rules = '''
書源是 Legado 3.0（閱讀 App）格式的 JSON，夜讀照同樣的規則解析。
- bookSourceType：0 小說（正文是成段文字）、1 有聲（正文是音訊網址）、2 漫畫（正文是圖片網址）。照抓到的正文判斷，不照名稱猜。規則裡用 book.type = … 逐本書設定類型的書源（聚合源，正文是哪一類看登入表單選的模式）不改類型。
- 規則語法照 Legado：JSOUP Default（class.xxx.0@tag.a@href）、CSS（@css:）、XPath（//）、JSONPath（\$.）、正則替換（##正則##替換）、<js></js> 與 @js:、{{ }} 內嵌、@put／@get。網址規則可以接 ,{"method":"POST","body":"...","charset":"gbk"}。
- 規則 JS 裡可用（同 Legado）：變數 result、baseUrl、key、page、book、source。
  - 抓網頁：java.ajax(網址) 直接傳回內容字串（網址可以接 ,{"method":"POST","body":"..."}）；java.post(網址, 內文, 標頭物件)、java.get(網址, 標頭物件)、java.connect(網址) 傳回回應物件，內容要用 .body()，狀態碼 .code()、網址 .url()、標頭 .headers()。
  - 解析：java.setContent(html) 之後 java.getString(規則)、java.getStringList(規則)、java.getElements(規則)。
  - 編碼：java.base64Decode(字串)、java.base64Encode、java.md5Encode、java.encodeURI、java.t2s、java.s2t、java.createSymmetricCrypto(…)。
  - 變數與 Cookie：java.put(名稱, 值)、java.get(名稱)；cookie.getCookie(網址)、cookie.setCookie(網址, 值)。
  - 沒有 Android 的類別（android.util.Base64 這類）。試抓報「TypeError: not a function」多半是把回應物件當字串用（少了 .body()），或用了這裡沒有的函式。
- 名稱、分組這些不用改，夜讀會照原本的；只改需要改的規則，其他照原樣留著。網站搬了家，或只有某個開頭（https、有沒有 www、新網域）連得上時，可以改 bookSourceUrl 的開頭（https://網域），後面的部分夜讀照原本的；書架上用這個書源的書會跟著搬。
''';

const String _method = '''
## 怎麼查
- 先看開場的校驗結果與試抓：哪一段失敗、網站實際回了什麼。網站回了正常的內容、規則卻抓不到（例如「未獲取到書籍」但回應裡有書單），問題在解析規則，網址與參數照舊；網站回的是錯誤、提示、驗證頁或轉址程式，才查網址、參數、標頭或網站本身。
- 每個抓到的網頁都有頁碼（頁 N），整頁存在夜讀這邊；回給你的只是精簡後的開頭。後面的內容用 read 讀；要知道某段文字在哪、它的選擇器怎麼寫，用 find；要看程式、<head> 與所有屬性，用 read 的 raw。
- 改規則前先用 parse 在已經抓到的頁面上試，抓得到再 test：parse 不連網站，test 會連，網站可能限流。
- 沒有次數限制，但每一步都要有目的，把想確認什麼寫在 note。
- 書源規則只放書源要用的規則；要跑程式查東西用 js。
''';

const String _commands =
    '''
## 指令
每次只回一個 JSON 物件，前後不要其他文字：
- 看網頁：{"action":"fetch","url":"網址","note":"…"}。照書源的標頭與 Cookie 抓。網址照書源網址規則的寫法：可以是相對書源網址的路徑，可以接 ,{"method":"POST","body":"..."}，{{key}} 是試抓用的關鍵字；要看書源搜尋實際拿到什麼，直接用書源的 searchUrl。回覆寫出實際送出的方法與內容。
- 讀頁：{"action":"read","page":頁碼,"from":從第幾字,"length":字數,"raw":false}。raw 是 true 時給原文，否則給精簡後的；一次最多 $maxReadLength 字。
- 找字：{"action":"find","page":頁碼,"text":"要找的字"}。回最多 10 處：那個元素的選擇器路徑與它的 HTML。
- 解析：{"action":"parse","page":頁碼,"as":"search|explore|info|toc|content","patch":{…}}。把 patch 蓋到目前的書源上（沒有 patch 就用目前的），用夜讀的解析程式把這一頁當成那一段解析；回解析到幾筆與前 5 筆的每個欄位，正文回字數、類型與開頭。
- 跑程式：{"action":"js","code":"…"}。在書源規則 JS 的環境跑，可用上面列的 java.* 與 source，page(頁碼) 傳回那一頁的原文；回傳回值與錯誤。
- 試抓：{"action":"test","patch":{…},"from":"search|info|toc|content","url":"…","note":"…"}。patch 會蓋到目前的書源上：規則物件（ruleSearch 這類）逐項蓋，沒寫的項目照舊，值給空字串就拿掉那一項。from 預設 search（用試抓的關鍵字搜尋）；其他段要給 url（詳情頁、目錄頁或正文頁的網址），從那一段一路抓到第一章正文。抓到正文就自動跑書源校驗（換第二本書、抽查前幾章），通過就套用；沒過把結果回給你接著改。
- 交出：{"action":"submit","patch":{…},"note":"…"}。試抓走不到正文、但你確定改對了才用（例如正文要付費）；夜讀跑一次書源校驗，通過才套用。
- 放棄：{"action":"give_up","reason":"…"}。網站不在了或只剩停放頁、要登入或付費、要真人在網頁上驗證、擋下所有請求時用；reason 寫你看到的證據（哪一頁、什麼內容）。
''';

/// 第一輪送給 AI 的話：系統提示與這個書源的現況。[probe] 的回應已經標上
/// 頁碼（[RepairPages.add]）。
List<AiMessage> aiRepairOpening({
  required BookSource source,
  required String checkResult,
  required SourceProbeReport probe,
}) => [
  (role: 'system', content: aiRepairSystemPrompt),
  (role: 'user', content: _situation(source, checkResult, probe)),
];

/// 系統提示：每個書源都一樣，服務的快取每次都打得中。
const String aiRepairSystemPrompt =
    '你是夜讀的書源修復員：書源壞了，你要查出原因、改好規則，再用試抓證明修好了；'
    '或拿出證據說明修不好。也要判斷書源的類型。\n\n$_rules\n$_method\n$_commands';

/// 沒有金鑰時複製給 AI 的整段話：使用者貼到任何 AI，再把回的書源貼回來。
String aiRepairClipboardPrompt({
  required BookSource source,
  required String checkResult,
  required SourceProbeReport probe,
}) =>
    '幫我修好這個書源，並判斷它的類型。\n\n$_rules\n'
    '修好後只回完整的書源 JSON（一個物件），不用其他說明。\n\n'
    '${_situation(source, checkResult, probe)}';

String _situation(
  BookSource source,
  String checkResult,
  SourceProbeReport probe,
) =>
    '# 書源\n```json\n'
    '${const JsonEncoder.withIndent('  ').convert(sourceForAi(source))}\n```\n\n'
    '# 書源校驗的結果\n$checkResult\n\n'
    '# 試抓這個書源\n${probe.fullText}';

/// 看網頁之後回給 AI 的話：[lines] 是送出的請求與標了頁碼的回應。
String aiRepairFetchReply(String url, List<String> lines) =>
    '# 看網頁 $url（精簡後，每頁只給開頭；其他段用 read）\n${lines.join('\n')}';

/// 試抓之後回給 AI 的話。
String aiRepairProbeReply(SourceProbeReport probe) =>
    '# 試抓結果：${probe.summary}\n${probe.fullText}';

/// 交出或試抓到正文、校驗卻沒過時回給 AI 的話：校驗的結論與它的診斷
/// （出錯的那一段送了什麼請求、網站回了什麼）。
String aiRepairCheckReply(String checkText, List<String> diagnostics) => [
  '# 書源校驗沒過：$checkText',
  if (diagnostics.isNotEmpty) diagnostics.join('\n\n'),
  '校驗會換第二本書、抽查前幾章；照上面的結果接著改。',
].join('\n');

/// AI 回的話讀不懂時回給它的話。
const String aiRepairBadReply = '讀不懂你回的內容。請照說明只回一個 JSON 物件。';

/// AI 回的話讀不懂時回給它的話，說出哪裡不對。
String aiRepairBadReplyFor(String reply) {
  final start = reply.indexOf('{');
  if (start < 0) return '$aiRepairBadReply（裡面沒有 JSON 物件）';
  try {
    jsonDecode(reply.substring(start, reply.lastIndexOf('}') + 1));
    return '$aiRepairBadReply（JSON 讀得懂，但 action 或欄位不對：test 與 submit 要有 patch 物件，'
        'fetch 要有 url，read、find、parse 要有 page，find 要有 text，parse 要有 as，js 要有 code）';
  } on FormatException catch (error) {
    return '$aiRepairBadReply（JSON 格式錯：${error.message}，在第 ${error.offset} 字附近。'
        '常見原因是括號沒配對完、字串裡的 " 或換行沒跳脫；只寫要改的欄位可以少出錯）';
  } on RangeError {
    return '$aiRepairBadReply（JSON 沒有結尾的 }）';
  }
}
