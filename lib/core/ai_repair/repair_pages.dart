import 'dart:isolate';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:night_reader/core/network/page_digest.dart';
import 'package:night_reader/core/network/request_log.dart';

/// AI 修復這段時間抓到的一頁：頁碼、網址、回應那一行與整頁原文。
final class RepairPage {
  const RepairPage(this.id, this.url, this.body);

  final int id;

  /// 回應的網址（轉址後的）。
  final String url;

  /// 照編碼解開的整頁原文，沒精簡。
  final String body;
}

/// AI 修復抓到的網頁（ADR 0054）：試抓與看網頁每個回應給一個頁碼，整頁原文
/// 留在這裡，AI 用讀頁、找字、解析、跑程式指著頁碼用。只在這次修復裡，修完
/// 就丟。
final class RepairPages {
  final List<RepairPage> _pages = [];

  /// 頁碼 [id] 的那一頁；沒有是 null。
  RepairPage? operator [](int id) =>
      id >= 1 && id <= _pages.length ? _pages[id - 1] : null;

  int get length => _pages.length;

  /// 登記 [pages] 裡帶原文的回應，傳回給 AI 的 [lines]：每個回應標上頁碼。
  /// [pages] 和 [lines] 一筆對一筆（[RequestLog.pages]）；對不上時不登記。
  List<String> add(List<String> lines, List<LoggedPage> pages) {
    if (pages.length != lines.length) return lines;
    return [
      for (final (i, line) in lines.indexed)
        if (pages[i].body case final body?) _register(line, body) else line,
    ];
  }

  /// 網址與原文都和已經登記的某頁一樣時（例如詳情、目錄、正文是同一個網址），
  /// 標上那一頁的頁碼，內容不再給一次：同一段字每輪都要重送。
  String _register(String line, String body) {
    final url = RegExp(r'^\s*← (\S+)').firstMatch(line)?.group(1) ?? '';
    for (final seen in _pages) {
      if (seen.url != url || seen.body != body) continue;
      final labeled = line.replaceFirst('← ', '← 頁 ${seen.id}｜');
      final colon = labeled.indexOf('：', labeled.indexOf('← '));
      final head = colon < 0 ? labeled : labeled.substring(0, colon);
      return '$head：和頁 ${seen.id} 一樣（網址與內容都相同），內容不再重複';
    }
    final page = RepairPage(_pages.length + 1, url, body);
    _pages.add(page);
    final labeled = line.replaceFirst('← ', '← 頁 ${page.id}｜');
    // 網址不同、內容一字不差：每個網址都回同一份頁面的網站（停放頁、被拿去
    // 轉址的網域、搜尋不理關鍵字）看這句就知道，不用自己比。
    final twin = body.trim().isEmpty
        ? null
        : _pages.where((seen) => seen != page && seen.body == body).firstOrNull;
    if (twin == null) return labeled;
    final colon = labeled.indexOf('：', labeled.indexOf('← '));
    return colon < 0
        ? '$labeled（內容和頁 ${twin.id} 一字不差）'
        : '${labeled.substring(0, colon)}（內容和頁 ${twin.id} 一字不差）'
              '${labeled.substring(colon)}';
  }

  void clear() => _pages.clear();
}

/// 讀頁：[page] 從第 [from] 字起 [length] 字（最多 [maxReadLength]）。[raw]
/// 給原文，否則給精簡後的（[digestPage]，在背景 isolate 做）。
Future<String> readRepairPage(
  RepairPage page, {
  int from = 0,
  int length = defaultReadLength,
  bool raw = false,
}) async {
  final body = page.body;
  final text = raw ? body : await Isolate.run(() => digestPage(body));
  final start = from.clamp(0, text.length);
  final end = (start + length.clamp(1, maxReadLength)).clamp(0, text.length);
  final kind = raw ? '原文' : '精簡後';
  final next = end < text.length ? '；下一段從 "from":$end 接著讀' : '，讀到結尾了';
  return '# 頁 ${page.id}（$kind）第 $start–$end 字，共 ${text.length} 字$next\n'
      '${text.substring(start, end)}';
}

/// 讀頁沒說要幾字時給的字數。
const int defaultReadLength = 8000;

/// 讀頁一次最多給的字數。
const int maxReadLength = 20000;

/// 找字：在 [page] 找 [query]，在背景 isolate 解析網頁（[findInPage]）。
Future<String> findInRepairPage(RepairPage page, String query, {int from = 0}) {
  final body = page.body;
  final id = page.id;
  return Isolate.run(
    () => '# 在頁 $id 找「$query」：${findInPage(body, query, from: from)}',
  );
}

/// 在網頁 [body] 裡找 [query]：[query] 當正則，編不了時當純文字（回覆寫明）。
/// 每處給那個元素的選擇器路徑與它的 HTML（太長只留開頭）；字在屬性值裡的
/// 也算。不是 HTML 的（JSON、純文字）給前後文。從第 [from] 處起最多
/// [_maxFinds] 處，寫出共幾處與下一段怎麼拿。
String findInPage(String body, String query, {int from = 0}) {
  if (query.isEmpty) return '沒有要找的字';
  RegExp pattern;
  var note = '';
  try {
    pattern = RegExp(query);
    if (pattern.hasMatch('')) {
      return '這個正則連空字串都對得上，找不出位置';
    }
  } on FormatException {
    pattern = RegExp(RegExp.escape(query));
    note = '（不是合法的正則，照純文字找）';
  }
  final found = <String>[];
  if (!body.trimLeft().startsWith('<')) {
    for (final match in pattern.allMatches(body)) {
      found.add(_around(body, match.start, match.end - match.start));
    }
  } else {
    final document = html_parser.parse(body);
    void visit(Node node) {
      if (node is Text && pattern.hasMatch(node.text)) {
        final parent = node.parent;
        if (parent != null) found.add(_element(parent));
      } else if (node is Element) {
        for (final MapEntry(:key, :value) in node.attributes.entries) {
          if (pattern.hasMatch(value)) {
            found.add(_element(node, attribute: '$key'));
            break;
          }
        }
      }
      for (final child in node.nodes) {
        visit(child);
      }
    }

    visit(document);
  }
  if (found.isEmpty) return '$note沒有找到';
  final start = from.clamp(0, found.length);
  final end = (start + _maxFinds).clamp(0, found.length);
  final more = end < found.length ? '；從 "from":$end 接著拿' : '';
  return '$note共 ${found.length} 處，這裡給第 ${start + 1}–$end 處$more\n'
      '${[for (var i = start; i < end; i++) '${i + 1}. ${found[i]}'].join('\n')}';
}

const int _maxFinds = 10;

/// 一處的說明：選擇器路徑，下一行是元素的 HTML。
String _element(Element element, {String? attribute}) {
  final html = element.outerHtml.replaceAll(RegExp(r'\s+'), ' ');
  final clipped = html.length > 300 ? '${html.substring(0, 300)}…' : html;
  return '${selectorPath(element)}'
      '${attribute == null ? '' : '（在屬性 $attribute 裡）'}\n   $clipped';
}

/// [element] 的選擇器路徑，例如 `div.list > div.row.item > span.title > a`：
/// 往上到有 id 的元素或 body 為止，最多 [_maxDepth] 層。
String selectorPath(Element element) {
  final parts = <String>[];
  Element? current = element;
  while (current != null && parts.length < _maxDepth) {
    final tag = current.localName ?? '';
    if (tag == 'body' || tag == 'html') break;
    final id = current.id;
    final classes = current.classes.where((c) => c.isNotEmpty).join('.');
    parts.add(
      id.isNotEmpty ? '$tag#$id' : (classes.isEmpty ? tag : '$tag.$classes'),
    );
    if (id.isNotEmpty) break;
    current = current.parent;
  }
  return parts.reversed.join(' > ');
}

const int _maxDepth = 8;

String _around(String text, int start, int length) {
  final from = (start - 150).clamp(0, text.length);
  final to = (start + length + 150).clamp(0, text.length);
  return '…${text.substring(from, to).replaceAll(RegExp(r'\s+'), ' ')}…';
}
