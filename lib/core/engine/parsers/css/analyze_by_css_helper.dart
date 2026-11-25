import 'package:html/dom.dart';

import 'package:night_reader/core/engine/parsers/jsoup_text.dart';

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
      // text、ownText 照 Jsoup（Legado）：區塊之間與 <br> 處留一個空格，
      // <script>、<style> 的內容不算。
      case 'text':
        for (final el in elements) {
          final t = jsoupText(el);
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
          final t = jsoupOwnText(el);
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
        // 同 Legado：同一個值只留一個（分類「玄幻,玄幻」、插圖重複）。
        for (final el in elements) {
          final attr = _attr(el, attrName);
          if (attr != null && attr.isNotEmpty && !textS.contains(attr)) {
            textS.add(attr);
          }
        }
    }
    return textS;
  }

  /// Jsoup 的 `attr`：`abs:` 開頭的是那個屬性的完整網址。Legado 解析網頁時
  /// 沒給頁面網址（`Jsoup.parse(html)`），只認網頁 `<base href>` 給的基準，
  /// 本來就是完整網址的照原樣，其他的是空的。
  static String? _attr(Element el, String name) {
    if (!name.toLowerCase().startsWith('abs:')) {
      return el.attributes[name]?.trim();
    }
    final value = el.attributes[name.substring(4).toLowerCase()]?.trim();
    if (value == null) return null;
    if (value.isNotEmpty) {
      final uri = Uri.tryParse(value);
      if (uri == null) return null;
      if (uri.hasScheme) return value;
    }
    final base = _documentBase(el);
    if (base == null) return null;
    try {
      return base.resolve(value).toString();
    } on FormatException {
      return null;
    }
  }

  /// 每份網頁的 `<base href>` 只找一次（沒有也記著），一頁幾千個連結時
  /// 不用每個都整頁找。
  static final Expando<Object> _baseOfRoot = Expando();
  static final Object _noBase = Object();

  static Uri? _documentBase(Element el) {
    Node top = el;
    while (top.parentNode != null) {
      top = top.parentNode!;
    }
    final cached = _baseOfRoot[top];
    if (cached != null) {
      return identical(cached, _noBase) ? null : cached as Uri;
    }
    final href = switch (top) {
      Document() => top.querySelector('base[href]')?.attributes['href'],
      Element() => top.querySelector('base[href]')?.attributes['href'],
      _ => null,
    };
    final parsed = href == null ? null : Uri.tryParse(href.trim());
    final base = parsed != null && parsed.hasScheme ? parsed : null;
    _baseOfRoot[top] = base ?? _noBase;
    return base;
  }
}
