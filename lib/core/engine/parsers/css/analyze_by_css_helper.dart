import 'package:html/dom.dart';
import 'analyze_by_css_base.dart';
import 'analyze_by_css_support.dart';

/// AnalyzeByCss 的私有輔助邏輯擴展
extension AnalyzeByCssHelper on AnalyzeByCssBase {
  List<Element> getElementsSingle(Element temp, String rule) {
    final single = ElementsSingle();
    return single.getElementsSingle(temp, rule);
  }

  String getElementData(Element element) {
    if (element.localName == 'script' || element.localName == 'style') {
      return element.innerHtml;
    }
    return element.innerHtml;
  }

  List<String> getResultLast(List<Element> elements, String lastRule) {
    final textS = <String>[];
    String attrName = lastRule;
    if (lastRule.startsWith('attr.')) {
      attrName = lastRule.substring(5);
    }

    switch (lastRule) {
      case 'text':
        for (final el in elements) {
          final t = el.text.trim().replaceAll(RegExp(r'\s+'), ' ');
          if (t.isNotEmpty) textS.add(t);
        }
        break;
      case 'textNodes':
        for (final el in elements) {
          final joined = el.nodes
              .where((n) => n.nodeType == Node.TEXT_NODE)
              .map((n) => n.text?.trim() ?? '')
              .where((t) => t.isNotEmpty)
              .join('\n');
          if (joined.isNotEmpty) {
            textS.add(joined);
          }
        }
        break;
      case 'ownText':
        for (final el in elements) {
          final t = el.nodes
              .where((n) => n.nodeType == Node.TEXT_NODE)
              .map((n) => n.text?.trim() ?? '')
              .where((t) => t.isNotEmpty)
              .join(' ');
          if (t.isNotEmpty) textS.add(t);
        }
        break;
      case 'html':
      case 'outerHtml':
        final buffer = StringBuffer();
        for (final el in elements) {
          final clone = el.clone(true);
          clone.querySelectorAll('script').forEach((node) => node.remove());
          clone.querySelectorAll('style').forEach((node) => node.remove());
          buffer.write(clone.outerHtml);
        }
        final html = buffer.toString();
        if (html.isNotEmpty) {
          textS.add(html);
        }
        break;
      case 'innerHtml':
        for (final el in elements) {
          textS.add(el.innerHtml);
        }
        break;
      case 'all':
        final html = elements.map((el) => el.outerHtml).join();
        if (html.isNotEmpty) {
          textS.add(html);
        }
        break;
      default:
        for (final el in elements) {
          final attr = el.attributes[attrName]?.trim();
          if (attr != null && attr.isNotEmpty) {
            textS.add(attr);
          }
        }
    }
    return textS;
  }
}
