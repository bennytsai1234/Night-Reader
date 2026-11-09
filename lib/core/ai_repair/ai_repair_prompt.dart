import 'dart:convert';

import 'package:night_reader/core/models/book_source.dart';

import 'ai_chat_client.dart';
import 'source_probe.dart';

/// AI 修書源最多來回幾輪（每輪是 AI 回一次、夜讀試抓一次）。
const int aiRepairMaxRounds = 5;

/// AI 每一輪回的指令（ADR 0054）。
sealed class AiRepairCommand {
  const AiRepairCommand();

  /// 從 AI 回的話取出指令；讀不懂時是 null。
  static AiRepairCommand? parse(String reply) {
    final json = extractJsonObject(reply);
    if (json == null) return null;
    final note = (json['note'] ?? json['reason'])?.toString().trim() ?? '';
    final source = json['source'];
    return switch (json['action']) {
      'test' when source is Map<String, dynamic> => AiTest(source, note),
      'submit' when source is Map<String, dynamic> => AiSubmit(source, note),
      'give_up' => AiGiveUp(note),
      _ => null,
    };
  }
}

/// 拿改過的書源試抓一次。
final class AiTest extends AiRepairCommand {
  const AiTest(this.source, this.note);
  final Map<String, dynamic> source;
  final String note;
}

/// 交出改好的書源，夜讀校驗後套用。
final class AiSubmit extends AiRepairCommand {
  const AiSubmit(this.source, this.note);
  final Map<String, dynamic> source;
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
    if (end == null) continue;
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

/// AI 改過的書源：規則照 AI 的，身分與使用者自己的設定照原本的——網址、
/// 名稱、分組、排序、開關、權重與註解。
BookSource candidateFrom(BookSource original, Map<String, dynamic> json) {
  final base = BookSource.fromJson(original.toJson())..removeErrorComment();
  return BookSource.fromJson(json)
    ..bookSourceUrl = original.bookSourceUrl
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

/// AI 改了哪幾類規則，例如「正文、目錄」；沒改是空字串。
String changedParts(BookSource before, BookSource after) {
  final a = _flatten(sourceForAi(before));
  final b = _flatten(sourceForAi(after));
  final keys = {...a.keys, ...b.keys}.where((key) => a[key] != b[key]);
  final parts = <String>{
    for (final key in keys) _partLabel(key.split('.').first),
  };
  const order = ['類型', '搜尋', '發現', '詳情', '目錄', '正文', '標頭', '程式庫', '登入', '其他'];
  return [
    for (final part in order)
      if (parts.contains(part)) part,
  ].join('、');
}

String _partLabel(String key) => switch (key) {
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
- bookSourceType：0 小說（正文是成段文字）、1 有聲（正文是音訊網址）、2 漫畫（正文是圖片網址）。照抓到的正文判斷，不照名稱猜。
- 規則語法照 Legado：JSOUP Default（class.xxx.0@tag.a@href）、CSS（@css:）、XPath（//）、JSONPath（\$.）、正則替換（##正則##替換）、<js></js> 與 @js:、{{ }} 內嵌、@put／@get。網址規則可以接 ,{"method":"POST","body":"...","charset":"gbk"}。
- 網址、名稱、分組這些不用改，夜讀會照原本的；只改需要改的規則，其他照原樣留著。
''';

const String _commands = '''
每次只回一個 JSON 物件，前後不要其他文字：
- 試抓：{"action":"test","source":{完整的書源},"note":"這次改了什麼"}。夜讀會從搜尋一路試抓到第一章正文，把除錯紀錄與每個網頁回給你。
- 交出：{"action":"submit","source":{完整的書源},"note":"改了什麼、類型為什麼是這個"}。試抓成功之後再交出；夜讀會跑一次書源校驗，通過才套用。
- 放棄：{"action":"give_up","reason":"為什麼修不好"}。例如網站已經關了、要登入或付費才看得到。
''';

/// 第一輪送給 AI 的話：系統提示與這個書源的現況。
List<AiMessage> aiRepairOpening({
  required BookSource source,
  required String checkResult,
  required SourceProbeReport probe,
}) => [
  (
    role: 'system',
    content:
        '你幫使用者修好壞掉的書源，並判斷它的類型。\n\n$_rules\n$_commands'
        '最多 $aiRepairMaxRounds 輪，用完還沒交出就算修不好。',
  ),
  (role: 'user', content: _situation(source, checkResult, probe)),
];

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

/// 試抓之後回給 AI 的話。
String aiRepairProbeReply(SourceProbeReport probe, {required int roundsLeft}) =>
    '# 試抓結果：${probe.summary}\n${probe.fullText}\n\n'
    '${roundsLeft > 0 ? '還剩 $roundsLeft 輪。' : '這是最後一輪，請交出或放棄。'}';

/// AI 回的話讀不懂時回給它的話。
const String aiRepairBadReply = '讀不懂你回的內容。請照說明只回一個 JSON 物件。';
