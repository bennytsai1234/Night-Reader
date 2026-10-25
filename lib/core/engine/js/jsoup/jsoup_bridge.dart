import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:html_unescape/html_unescape.dart';

import '../../parsers/css/analyze_by_css_support.dart';
import '../../parsers/jsoup_text.dart';

/// 規則 JS 裡的 Jsoup（`org.jsoup.Jsoup`、`java.getElements` 傳回的元素）。
///
/// 每個交給 JS 的節點在這裡記一個編號，JS 端的物件只帶編號，方法呼叫回來
/// 照編號找到真正的節點操作；選取、走訪、修改都作用在同一棵樹上，和
/// Legado 拿到真的 Jsoup 物件一樣。編號在引擎沒有規則在跑時清掉（見
/// `JsEngine`），規則裡巢狀執行別的規則時不清。
final HtmlUnescape _unescape = HtmlUnescape();

class JsoupBridge {
  final Map<int, dom.Node> _nodes = {};
  final Map<dom.Node, int> _ids = Map.identity();
  final Map<dom.Node, String> _baseUris = Map.identity();
  int _nextId = 1;

  bool get isEmpty => _nodes.isEmpty && _baseUris.isEmpty;

  void clear() {
    _nodes.clear();
    _ids.clear();
    _baseUris.clear();
  }

  dom.Node? node(int id) => _nodes[id];

  int idOf(dom.Node node) => _ids.putIfAbsent(node, () {
    final id = _nextId++;
    _nodes[id] = node;
    return id;
  });

  /// [node] 所在文件的網址，給 `abs:` 屬性與 `absUrl` 用。
  void setBaseUri(dom.Node node, String? baseUri) {
    if (baseUri == null || baseUri.isEmpty) return;
    _baseUris[_root(node)] = baseUri;
  }

  String baseUriOf(dom.Node node) => _baseUris[_root(node)] ?? '';

  static dom.Node _root(dom.Node node) {
    var current = node;
    while (current.parentNode != null) {
      current = current.parentNode!;
    }
    return current;
  }

  /// 交給 JS 的值：節點換成 `{__lrNode: 編號, k: 種類}`，節點清單包成
  /// `{__lrList: [...]}`（JS 端做成 Jsoup 的 Elements，空的也是），其他清單
  /// 逐項換。
  dynamic toJs(dynamic value) {
    if (value is dom.Node) {
      return {'__lrNode': idOf(value), 'k': _kind(value)};
    }
    if (value is Iterable<dom.Node>) {
      return {'__lrList': value.map(toJs).toList()};
    }
    if (value is Iterable) return value.map(toJs).toList();
    return value;
  }

  static String _kind(dom.Node node) => switch (node) {
    dom.Document() => 'document',
    dom.Element() => 'element',
    dom.Text() => 'text',
    dom.Comment() => 'comment',
    _ => 'node',
  };

  dom.Document parse(String html, String? baseUri) {
    final document = html_parser.parse(html);
    setBaseUri(document, baseUri);
    return document;
  }

  /// JS 端 `sendMessage('jsoup', [操作, 編號, 參數…])`；`Jsoup.parse` 這類
  /// 不屬於某個節點的操作，編號是 0。
  dynamic call(List args) {
    final op = args[0] as String;
    String? param(int index) =>
        args.length > index ? args[index]?.toString() : null;
    switch (op) {
      case 'parse':
        return toJs(parse(param(2) ?? '', param(3)));
      case 'parseBodyFragment':
        final document = html_parser.parse('<body>${param(2) ?? ''}</body>');
        setBaseUri(document, param(3));
        return toJs(document);
      case 'unescapeEntities':
        return _unescape.convert(param(2) ?? '');
    }
    final target = _nodes[(args[1] as num).toInt()];
    if (target == null) {
      throw StateError('這個 Jsoup 物件已經失效（規則執行完後不能再用）');
    }
    final rest = args.sublist(2);
    return toJs(_dispatch(op, target, rest));
  }

  dynamic _dispatch(String op, dom.Node node, List args) {
    String arg(int i) => i < args.length ? '${args[i] ?? ''}' : '';
    final element = node is dom.Element ? node : null;
    final document = node is dom.Document ? node : null;
    final container = document?.documentElement ?? element;
    switch (op) {
      // ── 文字與內容 ──
      case 'text':
        if (args.isNotEmpty) return _setText(node, arg(0));
        return jsoupText(node);
      case 'ownText':
        return jsoupOwnText(node);
      case 'wholeText':
        return node.text ?? '';
      case 'html':
        if (args.isNotEmpty) {
          _setHtml(node, arg(0));
          return node;
        }
        return node is dom.Element
            ? node.innerHtml
            : (document?.documentElement?.outerHtml ?? node.text ?? '');
      case 'outerHtml':
        return switch (node) {
          dom.Element() => node.outerHtml,
          dom.Document() => node.documentElement?.outerHtml ?? '',
          _ => node.text ?? '',
        };
      case 'data':
        return _data(node);
      case 'val':
        if (element == null) return '';
        if (args.isNotEmpty) {
          element.attributes['value'] = arg(0);
          return element;
        }
        return element.localName == 'textarea'
            ? element.text
            : element.attributes['value'] ?? '';
      // ── 屬性 ──
      case 'attr':
        if (element == null) return '';
        if (args.length > 1) {
          element.attributes[arg(0)] = arg(1);
          return element;
        }
        return _attr(element, arg(0));
      case 'hasAttr':
        if (element == null) return false;
        final name = arg(0);
        if (name.startsWith('abs:')) {
          return _absUrl(element, name.substring(4)).isNotEmpty;
        }
        return element.attributes.containsKey(name);
      case 'removeAttr':
        element?.attributes.remove(arg(0));
        return node;
      case 'absUrl':
        return element == null ? '' : _absUrl(element, arg(0));
      case 'attributes':
        if (element == null) return const <List<String>>[];
        return [
          for (final entry in element.attributes.entries)
            ['${entry.key}', entry.value],
        ];
      case 'id':
        return element?.id ?? '';
      case 'className':
        return element?.className ?? '';
      case 'classNames':
        return element?.classes.toList() ?? const <String>[];
      case 'hasClass':
        return element?.classes.contains(arg(0)) ?? false;
      case 'addClass':
        element?.classes.add(arg(0));
        return node;
      case 'removeClass':
        element?.classes.remove(arg(0));
        return node;
      case 'toggleClass':
        if (element != null && !element.classes.remove(arg(0))) {
          element.classes.add(arg(0));
        }
        return node;
      case 'tagName':
      case 'nodeName':
      case 'normalName':
        return switch (node) {
          dom.Element() => node.localName ?? '',
          dom.Document() => '#document',
          dom.Text() => '#text',
          dom.Comment() => '#comment',
          _ => '',
        };
      // ── 選取 ──
      case 'select':
        if (container == null) return const <dom.Element>[];
        return jsoupSelect(container, arg(0));
      case 'selectFirst':
        if (container == null) return null;
        final found = jsoupSelect(container, arg(0));
        return found.isEmpty ? null : found.first;
      case 'is':
        return element != null &&
            element.parent != null &&
            jsoupSelect(element.parent!, arg(0)).contains(element);
      case 'getElementById':
        return container == null
            ? null
            : jsoupSelect(container, '#${arg(0)}').firstOrNull;
      case 'getElementsByTag':
        return container == null
            ? const <dom.Element>[]
            : jsoupSelect(container, arg(0));
      case 'getElementsByClass':
        return container == null
            ? const <dom.Element>[]
            : jsoupSelect(container, '.${arg(0)}');
      case 'getElementsByAttribute':
        return container == null
            ? const <dom.Element>[]
            : jsoupSelect(container, '[${arg(0)}]');
      case 'getElementsByAttributeValue':
        return container == null
            ? const <dom.Element>[]
            : jsoupSelect(container, '[${arg(0)}="${arg(1)}"]');
      case 'getElementsContainingText':
        return container == null
            ? const <dom.Element>[]
            : jsoupSelect(container, '*:contains(${arg(0)})');
      case 'getElementsContainingOwnText':
        return container == null
            ? const <dom.Element>[]
            : jsoupSelect(container, '*:containsOwn(${arg(0)})');
      case 'getAllElements':
        return container == null
            ? const <dom.Element>[]
            : [container, ...container.querySelectorAll('*')];
      // ── 文件 ──
      case 'body':
        return document?.body;
      case 'head':
        return document?.head;
      case 'title':
        return document == null
            ? ''
            : jsoupText(document.querySelector('title') ?? dom.Text(''));
      case 'location':
      case 'baseUri':
        return baseUriOf(node);
      case 'setBaseUri':
        _baseUris[_root(node)] = arg(0);
        return null;
      // ── 走訪 ──
      case 'parent':
        return node.parent;
      case 'parents':
        final parents = <dom.Element>[];
        var current = node.parent;
        while (current != null) {
          parents.add(current);
          current = current.parent;
        }
        return parents;
      case 'children':
        return element?.children ??
            document?.documentElement?.children ??
            const <dom.Element>[];
      case 'child':
        final children = element?.children ?? const <dom.Element>[];
        final index = int.tryParse(arg(0)) ?? 0;
        if (index < 0 || index >= children.length) {
          throw RangeError.index(index, children, 'child');
        }
        return children[index];
      case 'childrenSize':
        return element?.children.length ?? 0;
      case 'firstElementChild':
        return element?.children.firstOrNull;
      case 'lastElementChild':
        return element?.children.lastOrNull;
      case 'nextElementSibling':
        return element?.nextElementSibling;
      case 'previousElementSibling':
        return element?.previousElementSibling;
      case 'siblingElements':
        final siblings = element?.parent?.children ?? const <dom.Element>[];
        return [
          for (final sibling in siblings)
            if (!identical(sibling, element)) sibling,
        ];
      case 'elementSiblingIndex':
        return element?.parent?.children.indexOf(element) ?? 0;
      case 'nextSibling':
        return _sibling(node, 1);
      case 'previousSibling':
        return _sibling(node, -1);
      case 'childNodes':
        return node.nodes.toList();
      case 'childNodeSize':
        return node.nodes.length;
      case 'textNodes':
        return node.nodes.whereType<dom.Text>().toList();
      case 'cssSelector':
        return element == null ? '' : _cssSelector(element);
      // ── 修改 ──
      case 'remove':
        node.remove();
        return null;
      case 'empty':
        node.nodes.clear();
        return node;
      case 'clone':
        final copy = node.clone(true);
        _baseUris[copy] = baseUriOf(node);
        return copy;
      case 'append':
        _insertHtml(node, arg(0), (parsed) => node.nodes.addAll(parsed));
        return node;
      case 'prepend':
        _insertHtml(node, arg(0), (parsed) => node.nodes.insertAll(0, parsed));
        return node;
      case 'appendText':
        node.nodes.add(dom.Text(arg(0)));
        return node;
      case 'before':
        _insertSibling(node, arg(0), after: false);
        return node;
      case 'after':
        _insertSibling(node, arg(0), after: true);
        return node;
      case 'unwrap':
        final parent = node.parentNode;
        if (parent == null) return null;
        final children = node.nodes.toList();
        final index = parent.nodes.indexOf(node);
        node.remove();
        parent.nodes.insertAll(index, children);
        return children.firstOrNull;
      case 'tagNameSet':
        if (element == null) return node;
        final replacement = dom.Element.tag(arg(0))
          ..attributes.addAll(element.attributes)
          ..nodes.addAll(element.nodes.toList());
        element.replaceWith(replacement);
        return replacement;
      case 'isBlank':
        return (node.text ?? '').trim().isEmpty;
      case 'hasText':
        return jsoupText(node).isNotEmpty;
    }
    throw UnsupportedError('Jsoup 沒有這個方法：$op');
  }

  String _attr(dom.Element element, String name) {
    if (name.startsWith('abs:')) return _absUrl(element, name.substring(4));
    return element.attributes[name] ?? '';
  }

  String _absUrl(dom.Element element, String name) {
    final value = element.attributes[name];
    if (value == null || value.isEmpty) return '';
    final base = Uri.tryParse(baseUriOf(element));
    final relative = Uri.tryParse(value.trim());
    if (relative == null) return '';
    if (relative.hasScheme) return relative.toString();
    if (base == null || !base.hasScheme) return '';
    return base.resolveUri(relative).toString();
  }

  String _data(dom.Node node) {
    if (node is dom.Element &&
        (node.localName == 'script' || node.localName == 'style')) {
      return node.text;
    }
    final buffer = StringBuffer();
    if (node is dom.Element || node is dom.Document) {
      for (final script
          in (node is dom.Document
              ? node.querySelectorAll('script, style')
              : (node as dom.Element).querySelectorAll('script, style'))) {
        buffer.write(script.text);
      }
    }
    return buffer.toString();
  }

  dom.Node _setText(dom.Node node, String text) {
    node.nodes
      ..clear()
      ..add(dom.Text(text));
    return node;
  }

  void _setHtml(dom.Node node, String html) {
    node.nodes.clear();
    _insertHtml(node, html, (parsed) => node.nodes.addAll(parsed));
  }

  void _insertHtml(
    dom.Node node,
    String html,
    void Function(List<dom.Node> parsed) insert,
  ) {
    final context = node is dom.Element ? node.localName ?? 'div' : 'div';
    final fragment = html_parser.parseFragment(html, container: context);
    insert(fragment.nodes.toList());
  }

  void _insertSibling(dom.Node node, String html, {required bool after}) {
    final parent = node.parentNode;
    if (parent == null) return;
    final context = parent is dom.Element ? parent.localName ?? 'div' : 'div';
    final parsed = html_parser
        .parseFragment(html, container: context)
        .nodes
        .toList();
    final index = parent.nodes.indexOf(node) + (after ? 1 : 0);
    parent.nodes.insertAll(index, parsed);
  }

  dom.Node? _sibling(dom.Node node, int step) {
    final siblings = node.parentNode?.nodes;
    if (siblings == null) return null;
    final index = siblings.indexOf(node) + step;
    return index >= 0 && index < siblings.length ? siblings[index] : null;
  }

  String _cssSelector(dom.Element element) {
    if (element.id.isNotEmpty) return '#${element.id}';
    final parts = <String>[];
    dom.Element? current = element;
    while (current != null && current.localName != 'html') {
      final parent = current.parent;
      final tag = current.localName ?? '*';
      if (parent == null) {
        parts.insert(0, tag);
        break;
      }
      final index = parent.children.indexOf(current) + 1;
      parts.insert(0, '$tag:nth-child($index)');
      current = parent;
    }
    return parts.join(' > ');
  }
}

/// Jsoup 的 `select`：CSS 加上 Jsoup 的擴充（`:eq`、`:contains`、`:has`、
/// `:lt`、`:gt`、`:matches` 等），找的範圍包含 [root] 自己。
List<dom.Element> jsoupSelect(dom.Element root, String selector) =>
    querySelectorAllCompat(root, selector);
