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

  String _register(String line, String body) {
    final url = RegExp(r'^\s*← (\S+)').firstMatch(line)?.group(1) ?? '';
    final page = RepairPage(_pages.length + 1, url, body);
    _pages.add(page);
    return line.replaceFirst('← ', '← 頁 ${page.id}｜');
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
  return '# 頁 ${page.id}（$kind）第 $start–$end 字，共 ${text.length} 字\n'
      '${text.substring(start, end)}';
}

/// 讀頁沒說要幾字時給的字數。
const int defaultReadLength = 8000;

/// 讀頁一次最多給的字數。
const int maxReadLength = 20000;

/// 找字：在 [page] 找 [query]，在背景 isolate 解析網頁（[findInPage]）。
Future<String> findInRepairPage(RepairPage page, String query) {
  final body = page.body;
  final id = page.id;
  return Isolate.run(() => '# 在頁 $id 找「$query」：${findInPage(body, query)}');
}

/// 在網頁 [body] 裡找 [query]：最多 [_maxFinds] 處，每處給那個元素的選擇器
/// 路徑與它的 HTML（太長只留開頭）；字在屬性值裡的也算。不是 HTML 的（JSON、
/// 純文字）只給前後文。
String findInPage(String body, String query) {
  if (query.isEmpty) return '沒有要找的字';
  final total = query.allMatches(body).length;
  if (total == 0) return '沒有找到';
  final found = <String>[];
  if (!body.trimLeft().startsWith('<')) {
    for (final match in query.allMatches(body).take(_maxFinds)) {
      found.add(_around(body, match.start, query.length));
    }
  } else {
    final document = html_parser.parse(body);
    void visit(Node node) {
      if (found.length >= _maxFinds) return;
      if (node is Text && node.text.contains(query)) {
        final parent = node.parent;
        if (parent != null) found.add(_element(parent));
      } else if (node is Element) {
        for (final MapEntry(:key, :value) in node.attributes.entries) {
          if (value.contains(query)) {
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
  final shown = found.length < total ? '（列出前 ${found.length} 處）' : '';
  return '原文裡共 $total 處$shown\n'
      '${[for (final (i, text) in found.indexed) '${i + 1}. $text'].join('\n')}';
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
