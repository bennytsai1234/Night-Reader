import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
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

  static bool looksLikeXml(String text) {
    final start = text.trimLeft();
    return start.length >= 5 && start.substring(0, 5).toLowerCase() == '<?xml';
  }

  /// [text] 是 XML 時傳回包住根元素的那一層，不是 XML 時傳回 null。
  ///
  /// [lowerCaseNames]：CSS 規則用。Jsoup 比對 CSS 選擇器時用小寫的標籤名稱
  /// （`chapter` 找得到 `<Chapter>`），XPath 照原文比對（JsoupXpath 用
  /// `nodeName()`），所以 CSS 讀出來的標籤名稱改成小寫。
  ///
  /// XML 寫壞了（標籤沒配對）時 Legado 的 Jsoup XML 解析器照樣讀下去；`xml`
  /// 套件會丟錯，這時改用網頁的解析器讀，但先把 `<page/>` 這種自己結束的標籤
  /// 展開成一對，結構才不會走樣。
  static Element? parse(String text, {bool lowerCaseNames = false}) {
    if (!looksLikeXml(text)) return null;
    final document = Element.tag(documentTag);
    try {
      final xml = XmlDocument.parse(text.trimLeft());
      for (final child in xml.children) {
        final node = _convert(child, lowerCaseNames);
        if (node != null) document.append(node);
      }
    } on XmlException {
      final body = text.trimLeft().replaceFirst(_declaration, '');
      document.nodes.addAll(
        html_parser
            .parseFragment(
              body.replaceAllMapped(_selfClosing, (m) {
                return '<${m[1]}${m[2]}></${m[1]}>';
              }),
            )
            .nodes,
      );
    }
    return document;
  }

  static final RegExp _declaration = RegExp(r'^<\?xml[^>]*\?>');
  static final RegExp _selfClosing = RegExp(
    r'<([A-Za-z_][\w:.-]*)([^<>]*?)\s*/>',
  );

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

  static Node? _convert(XmlNode node, bool lowerCaseNames) {
    switch (node) {
      case XmlElement():
        final name = node.name.qualified;
        final element = Element.tag(lowerCaseNames ? name.toLowerCase() : name);
        for (final attribute in node.attributes) {
          element.attributes[attribute.name.qualified] = attribute.value;
        }
        for (final child in node.children) {
          final converted = _convert(child, lowerCaseNames);
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
