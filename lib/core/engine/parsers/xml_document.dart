import 'package:html/dom.dart';
import 'package:xml/xml.dart';

/// 網站回的是 XML（`<?xml` 開頭）時，照 Legado 用 XML 解析器讀
/// （`AnalyzeByJSoup.parse`、`AnalyzeByXPath.strToJXDocument` 都是
/// `Jsoup.parse(…, Parser.xmlParser())`）。HTML 解析器會把 `<page num='1'/>`
/// 這種自己結束的標籤當成開頭，後面的兄弟節點全被包進去；XML 裡叫 `title`、
/// `p` 的標籤也會被當成網頁的標籤搬動。
///
/// 讀出來的結構轉成和網頁一樣的節點（`package:html` 的 [Element]），CSS 與
/// XPath 規則照常用；標籤名稱、屬性照原文（不改小寫，同 Jsoup 的 XML 解析器）。
abstract final class XmlContent {
  /// 包住 XML 根元素的那一層，當成 Jsoup 的 Document：規則從它往下找，
  /// 它自己不是 XML 裡的元素。
  static const String documentTag = '#xml-document';

  static bool looksLikeXml(String text) =>
      text.trimLeft().toLowerCase().startsWith('<?xml');

  /// [text] 是 XML 時傳回包住根元素的那一層；不是 XML、或 XML 寫壞了讀不懂
  /// 時傳回 null，照網頁讀（Legado 讀 XML 失敗時也改用網頁的解析器）。
  static Element? parse(String text) {
    if (!looksLikeXml(text)) return null;
    final XmlDocument xml;
    try {
      xml = XmlDocument.parse(text.trimLeft());
    } on XmlException {
      return null;
    }
    final document = Element.tag(documentTag);
    for (final child in xml.children) {
      final node = _convert(child);
      if (node != null) document.append(node);
    }
    return document;
  }

  /// [element] 是從 XML 讀出來的（在 [parse] 那一層底下）。
  static bool isFromXml(Element element) {
    Node? node = element;
    while (node != null) {
      if (node is Element && node.localName == documentTag) return true;
      node = node.parentNode;
    }
    return false;
  }

  /// XML 的根元素（[parse] 那一層底下第一個元素）。
  static Element? rootOf(Element document) =>
      document.children.isEmpty ? null : document.children.first;

  static Node? _convert(XmlNode node) {
    switch (node) {
      case XmlElement():
        final element = Element.tag(node.name.qualified);
        for (final attribute in node.attributes) {
          element.attributes[attribute.name.qualified] = attribute.value;
        }
        for (final child in node.children) {
          final converted = _convert(child);
          if (converted != null) element.append(converted);
        }
        return element;
      case XmlText():
      case XmlCDATA():
        return Text(node.value);
      default:
        // 宣告、註解、處理指令不是內容。
        return null;
    }
  }
}
