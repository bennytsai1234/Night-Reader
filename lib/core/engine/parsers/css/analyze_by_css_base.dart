import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

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
    } else if (doc is String) {
      element = _parseRootElement(doc);
    } else {
      element = html_parser.parse(doc.toString()).documentElement!;
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
    final trimmed = html.trimLeft();
    if (RegExp(
      r'^<(?:!doctype\s+html|html|body)\b',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return html_parser.parse(html).documentElement!;
    }
    final fragment = html_parser.parseFragment(html);
    final meaningfulNodes =
        fragment.nodes.where((node) {
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
