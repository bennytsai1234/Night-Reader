import 'package:html/dom.dart' as dom;

/// Jsoup 節點身上的網址：`Node.baseUri`（底下相對網址的基準）與
/// `Document.location`（解析時給的頁面網址）。
///
/// 和規則引擎交給 JS 的節點編號不同，這份跟著節點本身走：規則結束時
/// [JsoupBridge] 會忘掉交給 JS 的節點，但節點還是解析中的內容。
/// `java.setContent(Jsoup.parse(html, url))` 交出的文件換到下一條規則，
/// CSS 的 `abs:` 屬性與元素的 `baseUri()`、`location()` 讀到的還是同一個
/// 網址，同 Legado 拿到真的 Jsoup 元素。
final Expando<String> _baseUris = Expando();
final Expando<String> _locations = Expando();

/// [node] 自己記的網址（不含祖先的）。
String ownNodeBaseUri(dom.Node node) => _baseUris[node] ?? '';

void setNodeBaseUri(dom.Node node, String? baseUri) {
  if (baseUri == null || baseUri.isEmpty) return;
  _baseUris[node] = baseUri;
}

/// [node] 或最近一個記了網址的祖先：設在文件上就整份文件適用，被拿出文件
/// 的節點和 Jsoup 一樣沒有網址。
String nodeBaseUriOf(dom.Node node) {
  dom.Node? current = node;
  while (current != null) {
    final uri = _baseUris[current];
    if (uri != null) return uri;
    current = current.parentNode;
  }
  return '';
}

/// 文件的 `location()`：解析時給的頁面網址（Jsoup `Document.location`），
/// 和網頁 `<base href>` 改過的基準分開。
void setDocumentLocation(dom.Document document, String? location) {
  _locations[document] = location ?? '';
}

String? documentLocation(dom.Document document) => _locations[document];
