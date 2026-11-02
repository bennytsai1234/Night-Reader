import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../elements_list.dart';
import '../xml_document.dart';

/// AnalyzeByCss 的基礎類別
/// (原 Android model/analyzeRule/AnalyzeByJSoup.kt)
abstract class AnalyzeByCssBase {
  late Element element;

  void setContent(dynamic doc) {
    final htmlLike = _extractHtmlLikeContent(doc);
    if (doc is Element) {
      element = doc;
    } else if (htmlLike != null) {
      element = _parseRootElement(htmlLike);
    } else if (doc is List) {
      // 上一條規則找到的一組元素（同 Legado 交給 Jsoup 的 Elements）。
      final single = elementsListSingle(doc);
      element = single ?? _parseRootElement(elementsListHtml(doc));
    } else if (doc is String) {
      element = _parseRootElement(doc);
    } else {
      element = _parseRootElement(doc.toString());
    }
  }

  String? _extractHtmlLikeContent(dynamic doc) {
    if (doc is! Map) return null;
    for (final key in const <String>['__html', 'outerHtml', 'html']) {
      final candidate = doc[key];
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate;
      }
    }
    return null;
  }

  Element _parseRootElement(String html) {
    // 網站回的是 XML 時照 Legado 用 XML 解析器讀，規則從整份文件往下找
    // （同 Jsoup 的 Document）。
    final xml = XmlContent.parse(html, lowerCaseNames: true);
    if (xml != null) return xml;
    final trimmed = html.trimLeft();
    if (RegExp(
      r'^<(?:!doctype\s+html|html|body)\b',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return html_parser.parse(html).documentElement!;
    }
    final fragment = html_parser.parseFragment(html);
    final meaningfulNodes = fragment.nodes.where((node) {
      if (node is Element) return true;
      final text = node.text?.trim() ?? '';
      return text.isNotEmpty;
    }).toList();
    if (meaningfulNodes.length == 1 && meaningfulNodes.first is Element) {
      return meaningfulNodes.first as Element;
    }
    final document = html_parser.parse(html);
    return document.documentElement!;
  }
}
