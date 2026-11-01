import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:html_unescape/html_unescape.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

import '../../parsers/css/analyze_by_css_support.dart';
import '../../parsers/jsoup_text.dart';

final HtmlUnescape _unescape = HtmlUnescape();

/// Jsoup 方法丟給規則 JS 的錯誤：訊息照 Jsoup 的原文，規則 `catch` 到的
/// `e.message` 就是它，不帶 Dart 錯誤類別的前綴。
class JsoupException implements Exception {
  JsoupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 規則 JS 裡的 Jsoup（`org.jsoup.Jsoup`、`java.getElements` 傳回的元素）。
///
/// 每個交給 JS 的節點在這裡記一個編號，JS 端的物件只帶編號，方法呼叫回來
/// 照編號找到真正的節點操作；選取、走訪、修改都作用在同一棵樹上，和
/// Legado 拿到真的 Jsoup 物件一樣（行為對照 Jsoup 1.15.3）。編號在引擎沒有
/// 規則在跑時清掉（見 `JsEngine`），規則裡巢狀執行別的規則時不清。
class JsoupBridge {
  final Map<int, dom.Node> _nodes = {};
  final Map<dom.Node, int> _ids = Map.identity();

  /// 節點與它底下的網址（`abs:` 屬性用）。查詢時往上找最近有記的祖先，
  /// 所以設在文件上就整份文件適用；節點被移出文件前先記在它自己身上，
  /// 拿出來之後照樣算得出完整網址（Jsoup 也是）。
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

  /// [node] 與它底下的網址，給 `abs:` 屬性與 `absUrl` 用。
  void setBaseUri(dom.Node node, String? baseUri) {
    if (baseUri == null || baseUri.isEmpty) return;
    _baseUris[node] = baseUri;
  }

  String baseUriOf(dom.Node node) {
    dom.Node? current = node;
    while (current != null) {
      final uri = _baseUris[current];
      if (uri != null) return uri;
      current = current.parentNode;
    }
    return '';
  }

  /// 節點要被移出文件：先把現在的網址記在它身上。
  void _pinBaseUri(dom.Node node) {
    final uri = baseUriOf(node);
    if (uri.isNotEmpty) _baseUris.putIfAbsent(node, () => uri);
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
    // <script>、<style> 裡的文字在 Jsoup 是 DataNode。
    dom.Text() when _isDataParent(node.parentNode ?? node) => 'data',
    dom.Text() => 'text',
    dom.Comment() => 'comment',
    _ => 'node',
  };

  /// Jsoup.parse：網址先看頁面裡的 `<base href>`（相對於 [baseUri]）。
  dom.Document parse(String html, String? baseUri) {
    final document = html_parser.parse(html);
    final baseHref = document
        .querySelector('base[href]')
        ?.attributes['href']
        ?.trim();
    var effective = baseUri;
    if (baseHref != null && baseHref.isNotEmpty) {
      final base = Uri.tryParse(baseUri ?? '');
      final href = Uri.tryParse(baseHref);
      if (href != null) {
        effective = href.hasScheme
            ? href.toString()
            : (base != null && base.hasScheme
                  ? base.resolveUri(href).toString()
                  : effective);
      }
    }
    setBaseUri(document, effective);
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
        return toJs(parse('<body>${param(2) ?? ''}</body>', param(3)));
      case 'unescapeEntities':
        return _unescape.convert(param(2) ?? '');
      case 'create':
        return toJs(create(param(2) ?? '', param(3) ?? '', param(4)));
    }
    final target = _nodes[(args[1] as num).toInt()];
    if (target == null) {
      throw JsoupException('這個 Jsoup 物件已經失效（規則執行完後不能再用）');
    }
    return toJs(_dispatch(op, target, args.sublist(2)));
  }

  /// JS 傳來的節點參數（`{__lrNode: 編號}`）；不是節點時是 null。
  dom.Node? _nodeArg(Object? value) {
    if (value is Map && value['__lrNode'] is num) {
      return _nodes[(value['__lrNode'] as num).toInt()];
    }
    return null;
  }

  /// JS 傳來的節點清單參數（`{__lrList: [...]}`，或單一個節點）。
  List<dom.Node> _nodesArg(Object? value) {
    if (value is Map && value['__lrList'] is List) {
      return [for (final item in value['__lrList'] as List) ?_nodeArg(item)];
    }
    return [?_nodeArg(value)];
  }

  dynamic _dispatch(String op, dom.Node node, List args) {
    String arg(int i) => i < args.length ? '${args[i] ?? ''}' : '';
    dom.Node? nodeArg(int i) => i < args.length ? _nodeArg(args[i]) : null;
    int intArg(int i) =>
        int.tryParse(arg(i)) ?? num.tryParse(arg(i))?.toInt() ?? 0;
    final element = node is dom.Element ? node : null;
    final document = node is dom.Document ? node : null;
    // 文件本身不會符合選擇器，從 <html> 開始選，和 Jsoup 一樣含 <html>。
    final container = document?.documentElement ?? element;
    switch (op) {
      // ── 文字與內容 ──
      case 'text':
        if (args.isNotEmpty) return _setText(node, arg(0));
        return jsoupText(node);
      case 'ownText':
        return jsoupOwnText(node);
      case 'wholeText':
        return jsoupWholeText(node);
      case 'html':
        if (args.isNotEmpty) {
          _setHtml(node, arg(0));
          return node;
        }
        return switch (node) {
          dom.Element() => node.innerHtml,
          dom.Document() => node.documentElement?.outerHtml ?? '',
          _ => node.text ?? '',
        };
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
        final isTextarea = element.localName == 'textarea';
        if (args.isNotEmpty) {
          if (isTextarea) {
            _setText(element, arg(0));
          } else {
            element.attributes['value'] = arg(0);
          }
          return element;
        }
        return isTextarea ? element.text : _attributeValue(element, 'value');
      // ── 屬性：名稱不分大小寫（Jsoup） ──
      case 'attr':
        if (element == null) return '';
        if (args.length > 1) {
          _setAttribute(element, arg(0), arg(1));
          return element;
        }
        final name = arg(0);
        if (name.toLowerCase().startsWith('abs:')) {
          return _absUrl(element, name.substring(4));
        }
        return _attributeValue(element, name);
      case 'hasAttr':
        if (element == null) return false;
        final name = arg(0);
        if (name.toLowerCase().startsWith('abs:')) {
          return _absUrl(element, name.substring(4)).isNotEmpty;
        }
        return _attributeKey(element, name) != null;
      case 'removeAttr':
        if (element != null) {
          final key = _attributeKey(element, arg(0));
          if (key != null) element.attributes.remove(key);
        }
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
        return selectWithSelfCompat(container, arg(0));
      case 'selectFirst':
        if (container == null) return null;
        return selectWithSelfCompat(container, arg(0)).firstOrNull;
      case 'is':
        return element != null && elementMatchesSelectorCompat(element, arg(0));
      case 'getElementById':
        return container == null
            ? null
            : selectWithSelfCompat(container, '#${arg(0)}').firstOrNull;
      case 'getElementsByTag':
        return container == null
            ? const <dom.Element>[]
            : selectWithSelfCompat(container, arg(0));
      case 'getElementsByClass':
        return container == null
            ? const <dom.Element>[]
            : selectWithSelfCompat(container, '.${arg(0)}');
      case 'getElementsByAttribute':
        return container == null
            ? const <dom.Element>[]
            : selectWithSelfCompat(container, '[${arg(0)}]');
      case 'getElementsByAttributeValue':
        return container == null
            ? const <dom.Element>[]
            : selectWithSelfCompat(container, '[${arg(0)}="${arg(1)}"]');
      case 'getElementsContainingText':
        return container == null
            ? const <dom.Element>[]
            : selectWithSelfCompat(container, '*:contains(${arg(0)})');
      case 'getElementsContainingOwnText':
        return container == null
            ? const <dom.Element>[]
            : selectWithSelfCompat(container, '*:containsOwn(${arg(0)})');
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
        final title = document?.querySelector('title');
        return title == null ? '' : jsoupText(title);
      case 'location':
      case 'baseUri':
        return baseUriOf(node);
      case 'setBaseUri':
        setBaseUri(node, arg(0));
        return null;
      case 'ownerDocument':
        var root = node;
        while (root.parentNode != null) {
          root = root.parentNode!;
        }
        return root is dom.Document ? root : null;
      // ── 走訪：文件是 <html> 的父節點（Jsoup 的 Document 也是元素） ──
      case 'parent':
        final parent = node.parentNode;
        return parent is dom.Element || parent is dom.Document ? parent : null;
      case 'parents':
        final parents = <dom.Element>[];
        var current = node.parent;
        while (current != null) {
          parents.add(current);
          current = current.parent;
        }
        return parents;
      case 'children':
        return _children(node);
      case 'child':
        final children = _children(node);
        final index = int.tryParse(arg(0)) ?? 0;
        if (index < 0 || index >= children.length) {
          throw RangeError.index(index, children, 'child');
        }
        return children[index];
      case 'childrenSize':
        return _children(node).length;
      case 'firstElementChild':
        return _children(node).firstOrNull;
      case 'lastElementChild':
        return _children(node).lastOrNull;
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
        _pinBaseUri(node);
        node.remove();
        return null;
      case 'empty':
        _detachChildren(node);
        return node;
      case 'clone':
        final copy = node.clone(true);
        setBaseUri(copy, baseUriOf(node));
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
        _pinBaseUri(node);
        node.remove();
        parent.nodes.insertAll(index, children);
        return children.firstOrNull;
      case 'tagNameSet':
        return element == null ? node : _rename(element, arg(0));
      case 'isBlank':
        return (node.text ?? '').trim().isEmpty;
      case 'hasText':
        return jsoupText(node).isNotEmpty;
    }
    return _dispatchMore(op, node, args, arg, nodeArg, intArg);
  }

  /// [_dispatch] 的後半：Jsoup 1.16.2 其他的公開方法（規則 JS 的
  /// `legado_api_parity_test` 列了全部）。
  dynamic _dispatchMore(
    String op,
    dom.Node node,
    List args,
    String Function(int) arg,
    dom.Node? Function(int) nodeArg,
    int Function(int) intArg,
  ) {
    final element = node is dom.Element ? node : null;
    final document = node is dom.Document ? node : null;
    final container = document?.documentElement ?? element;
    dom.Node requireNode(int i) =>
        nodeArg(i) ?? (throw JsoupException('參數不是 Jsoup 的節點'));
    switch (op) {
      // ── 節點 ──
      case 'hasParent':
        return node.parentNode != null;
      case 'attributesSize':
        return element?.attributes.length ?? 0;
      case 'clearAttributes':
        element?.attributes.clear();
        return node;
      case 'childNode':
        final index = intArg(0);
        if (index < 0 || index >= node.nodes.length) {
          throw RangeError.index(index, node.nodes, 'childNode');
        }
        return node.nodes[index];
      case 'childNodesCopy':
        return [for (final child in node.nodes) _copy(child, deep: true)];
      case 'firstChild':
        return node.nodes.firstOrNull;
      case 'lastChild':
        return node.nodes.lastOrNull;
      case 'root':
        var root = node;
        while (root.parentNode != null) {
          root = root.parentNode!;
        }
        return root;
      case 'siblingIndex':
        return node.parentNode?.nodes.indexOf(node) ?? 0;
      case 'siblingNodes':
        final parent = node.parentNode;
        if (parent == null) return const <dom.Node>[];
        return [
          for (final sibling in parent.nodes)
            if (!identical(sibling, node)) sibling,
        ];
      case 'replaceWith':
        _replace(node, requireNode(0));
        return null;
      case 'wrap':
        _wrap(node, arg(0));
        return node;
      case 'shallowClone':
        return _copy(node, deep: false);
      case 'hasSameValue':
        final other = nodeArg(0);
        return other != null && _outerHtml(other) == _outerHtml(node);
      case 'hashCode':
        return idOf(node);
      case 'beforeNode':
        _insertNodeSibling(node, requireNode(0), after: false);
        return node;
      case 'afterNode':
        _insertNodeSibling(node, requireNode(0), after: true);
        return node;
      // ── 子節點：加進來的節點先從原本的位置拿走（Jsoup 也是搬過去） ──
      case 'appendChild':
        node.nodes.add(requireNode(0));
        return node;
      case 'appendChildren':
        _insertChildren(node, node.nodes.length, _nodesArg(args.firstOrNull));
        return node;
      case 'prependChild':
        node.nodes.insert(0, requireNode(0));
        return node;
      case 'prependChildren':
        _insertChildren(node, 0, _nodesArg(args.firstOrNull));
        return node;
      case 'insertChildren':
        var index = intArg(0);
        final size = node.nodes.length;
        if (index < 0) index += size + 1;
        if (index < 0 || index > size) {
          throw RangeError.range(index, 0, size, 'index', '位置超出範圍');
        }
        _insertChildren(node, index, [
          for (final value in args.skip(1)) ..._nodesArg(value),
        ]);
        return node;
      case 'appendTo':
        requireNode(0).nodes.add(node);
        return node;
      case 'appendElement':
        final child = dom.Element.tag(arg(0).toLowerCase());
        node.nodes.add(child);
        return child;
      case 'prependElement':
        final child = dom.Element.tag(arg(0).toLowerCase());
        node.nodes.insert(0, child);
        return child;
      case 'prependText':
        node.nodes.insert(0, dom.Text(arg(0)));
        return node;
      case 'nodeData':
        // Comment.getData、DataNode 的內容。
        if (node is dom.Comment) return node.data ?? '';
        return node is dom.Text ? node.data : '';
      case 'textSet':
        // TextNode.text(String)、DataNode.setWholeData、Comment.setData。
        if (node is dom.Text) node.data = arg(0);
        if (node is dom.Comment) node.data = arg(0);
        return node;
      case 'splitText':
        if (node is! dom.Text) throw JsoupException('只有文字節點能切開');
        final text = node.data;
        final offset = intArg(0);
        if (offset < 0 || offset > text.length) {
          throw RangeError.range(offset, 0, text.length, 'offset');
        }
        final tail = dom.Text(text.substring(offset));
        node.data = text.substring(0, offset);
        final parent = node.parentNode;
        if (parent != null) {
          parent.nodes.insert(parent.nodes.indexOf(node) + 1, tail);
        }
        return tail;
      // ── 元素 ──
      case 'idSet':
        element?.attributes['id'] = arg(0);
        return node;
      case 'attrFlag':
        // attr(名稱, true／false)：布林屬性，true 是只有名稱的屬性。
        if (element == null) return node;
        final key = _attributeKey(element, arg(0));
        if (args.length > 1 && args[1] == true) {
          element.attributes[key ?? arg(0).toLowerCase()] = '';
        } else if (key != null) {
          element.attributes.remove(key);
        }
        return node;
      case 'closest':
        dom.Element? current = element;
        while (current != null) {
          if (elementMatchesSelectorCompat(current, arg(0))) return current;
          current = current.parent;
        }
        return null;
      case 'expectFirst':
        final found = container == null
            ? null
            : selectWithSelfCompat(container, arg(0)).firstOrNull;
        if (found != null) return found;
        throw JsoupException(
          node.parentNode != null
              ? "No elements matched the query '${arg(0)}' on element "
                    "'${_nodeName(node)}'."
              : "No elements matched the query '${arg(0)}' in the document.",
        );
      case 'selectXpath':
        if (container == null) return const <dom.Element>[];
        return [
          for (final found in HtmlXPath.node(container).query(arg(0)).nodes)
            if (found.node case final dom.Element element) element,
        ];
      case 'dataNodes':
        if (!_isDataParent(node)) return const <dom.Node>[];
        return node.nodes.whereType<dom.Text>().toList();
      case 'comments':
        return node.nodes.whereType<dom.Comment>().toList();
      case 'firstElementSibling':
        return element?.parent?.children.firstOrNull ?? element;
      case 'lastElementSibling':
        return element?.parent?.children.lastOrNull ?? element;
      case 'nextElementSiblings':
        final siblings = element?.parent?.children;
        if (siblings == null) return const <dom.Element>[];
        return siblings.sublist(siblings.indexOf(element!) + 1);
      case 'previousElementSiblings':
        final siblings = element?.parent?.children;
        if (siblings == null) return const <dom.Element>[];
        return siblings
            .sublist(0, siblings.indexOf(element!))
            .reversed
            .toList();
      case 'getElementsByAttributeStarting':
        final prefix = arg(0).trim().toLowerCase();
        return _allElements(container)
            .where(
              (e) => e.attributes.keys.any(
                (key) => '$key'.toLowerCase().startsWith(prefix),
              ),
            )
            .toList();
      case 'getElementsByAttributeValueNot':
        final value = arg(1).trim().toLowerCase();
        return _allElements(container)
            .where(
              (e) => _attributeValue(e, arg(0).trim()).toLowerCase() != value,
            )
            .toList();
      case 'getElementsByAttributeValueStarting':
      case 'getElementsByAttributeValueEnding':
      case 'getElementsByAttributeValueContaining':
        final name = arg(0).trim();
        final value = arg(1).trim().toLowerCase();
        bool test(String attr) => switch (op) {
          'getElementsByAttributeValueStarting' => attr.startsWith(value),
          'getElementsByAttributeValueEnding' => attr.endsWith(value),
          _ => attr.contains(value),
        };
        return _allElements(container)
            .where(
              (e) =>
                  _attributeKey(e, name) != null &&
                  test(_attributeValue(e, name).toLowerCase()),
            )
            .toList();
      case 'getElementsByAttributeValueMatching':
        final name = arg(0).trim();
        final pattern = RegExp(arg(1));
        return _allElements(container)
            .where(
              (e) =>
                  _attributeKey(e, name) != null &&
                  pattern.hasMatch(_attributeValue(e, name)),
            )
            .toList();
      case 'getElementsByIndexEquals':
      case 'getElementsByIndexLessThan':
      case 'getElementsByIndexGreaterThan':
        final index = intArg(0);
        return _allElements(container).where((e) {
          final position = e.parent?.children.indexOf(e) ?? 0;
          return switch (op) {
            'getElementsByIndexEquals' => position == index,
            'getElementsByIndexLessThan' =>
              !identical(e, container) && position < index,
            _ => position > index,
          };
        }).toList();
      case 'getElementsMatchingText':
        final pattern = RegExp(arg(0));
        return _allElements(container)
            .where((e) => pattern.hasMatch(jsoupText(e)))
            .toList();
      case 'getElementsMatchingOwnText':
        final pattern = RegExp(arg(0));
        return _allElements(container)
            .where((e) => pattern.hasMatch(jsoupOwnText(e)))
            .toList();
      case 'isBlock':
        return element != null && jsoupIsBlock(element.localName ?? '');
      case 'wholeOwnText':
        final buffer = StringBuffer();
        for (final child in node.nodes) {
          if (child is dom.Text) buffer.write(child.data);
          if (child is dom.Element && child.localName == 'br') {
            buffer.write('\n');
          }
        }
        return buffer.toString();
      // ── 文件 ──
      case 'createElement':
        final created = dom.Element.tag(arg(0));
        setBaseUri(created, baseUriOf(node));
        return created;
      case 'titleSet':
        if (document == null) return null;
        var title = document.querySelector('title');
        if (title == null) {
          title = dom.Element.tag('title');
          (document.head ?? document.documentElement)?.nodes.add(title);
        }
        _setText(title, arg(0));
        return null;
      case 'forms':
        return container == null
            ? const <dom.Element>[]
            : selectWithSelfCompat(container, 'form');
      case 'expectForm':
        final form = container == null
            ? null
            : selectWithSelfCompat(
                container,
                arg(0),
              ).where((e) => e.localName == 'form').firstOrNull;
        if (form != null) return form;
        throw JsoupException(
          "No form elements matched the query '${arg(0)}' in "
          'the document.',
        );
    }
    throw UnsupportedError('Jsoup 沒有這個方法：$op');
  }

  /// 不屬於某個節點的建立：`new Element(tag)`、`new TextNode(text)` 這類。
  dom.Node create(String kind, String value, String? baseUri) {
    final dom.Node created = switch (kind) {
      'element' => dom.Element.tag(value),
      'text' || 'data' => dom.Text(value),
      'encodedText' => dom.Text(_unescape.convert(value)),
      'comment' => dom.Comment(value),
      _ => html_parser.parse(''),
    };
    if (created is dom.Document) created.nodes.clear();
    setBaseUri(created, baseUri);
    return created;
  }

  static bool _isDataParent(dom.Node node) =>
      node is dom.Element &&
      (node.localName == 'script' || node.localName == 'style');

  static String _nodeName(dom.Node node) => switch (node) {
    dom.Element() => node.localName ?? '',
    dom.Document() => '#document',
    dom.Text() => '#text',
    dom.Comment() => '#comment',
    _ => '',
  };

  static String _outerHtml(dom.Node node) => switch (node) {
    dom.Element() => node.outerHtml,
    dom.Document() => node.outerHtml,
    dom.Text() => node.data,
    dom.Comment() => '<!--${node.data ?? ''}-->',
    _ => node.text ?? '',
  };

  /// [container] 自己與底下的每個元素，文件順序。
  static List<dom.Element> _allElements(dom.Element? container) =>
      container == null
      ? const []
      : [container, ...container.querySelectorAll('*')];

  dom.Node _copy(dom.Node node, {required bool deep}) {
    final dom.Node copy;
    if (deep || node is! dom.Element) {
      copy = node is dom.Document && !deep
          ? (html_parser.parse('')..nodes.clear())
          : node.clone(deep);
    } else {
      copy = dom.Element.tag(node.localName)
        ..attributes.addAll(node.attributes);
    }
    setBaseUri(copy, baseUriOf(node));
    return copy;
  }

  /// Jsoup `Node.replaceWith`：[node] 要在某個父節點底下。
  void _replace(dom.Node node, dom.Node replacement) {
    final parent = node.parentNode;
    if (parent == null) throw JsoupException('這個節點沒有父節點，不能取代');
    if (identical(node, replacement)) return;
    replacement.remove();
    final index = parent.nodes.indexOf(node);
    _pinBaseUri(node);
    node.remove();
    parent.nodes.insert(index, replacement);
  }

  /// Jsoup `Node.wrap(html)`：用 html 的第一個元素包住 [node]，放進它最深
  /// 的第一個子元素；html 剩下的節點接在外框後面。
  void _wrap(dom.Node node, String html) {
    final parent = node.parentNode;
    final context = parent is dom.Element
        ? parent.localName ?? 'div'
        : (node is dom.Element ? node.localName ?? 'div' : 'div');
    final parsed = html_parser
        .parseFragment(html, container: context)
        .nodes
        .toList();
    final wrap = parsed.firstOrNull;
    if (wrap is! dom.Element) return;
    var deepest = wrap;
    while (deepest.children.isNotEmpty) {
      deepest = deepest.children.first;
    }
    if (parent != null) _replace(node, wrap);
    deepest.nodes.add(node);
    final wrapParent = wrap.parentNode;
    for (final remainder in parsed.skip(1)) {
      remainder.remove();
      if (wrapParent != null) {
        wrapParent.nodes.insert(wrapParent.nodes.indexOf(wrap) + 1, remainder);
      }
    }
  }

  /// Jsoup `Element.insertChildren`：先把要加的節點從原本的位置拿走，再照
  /// 原本算好的位置插進去。
  void _insertChildren(dom.Node parent, int index, List<dom.Node> children) {
    for (final child in children) {
      child.remove();
    }
    final at = index.clamp(0, parent.nodes.length);
    parent.nodes.insertAll(at, children);
  }

  void _insertNodeSibling(
    dom.Node node,
    dom.Node sibling, {
    required bool after,
  }) {
    final parent = node.parentNode;
    if (parent == null) throw JsoupException('這個節點沒有父節點');
    sibling.remove();
    final index = parent.nodes.indexOf(node) + (after ? 1 : 0);
    parent.nodes.insert(index, sibling);
  }

  List<dom.Element> _children(dom.Node node) => switch (node) {
    dom.Document() => [?node.documentElement],
    dom.Element() => node.children,
    _ => const <dom.Element>[],
  };

  /// Jsoup 原地改名、傳回自己。這裡的 DOM 不能改標籤名稱，只能換一個
  /// 新元素：同一個編號改指向新元素，JS 手上的物件和之後拿到的都是它。
  dom.Element _rename(dom.Element element, String tag) {
    final replacement = dom.Element.tag(tag.toLowerCase())
      ..attributes.addAll(element.attributes)
      ..nodes.addAll(element.nodes.toList());
    final uri = _baseUris.remove(element);
    if (uri != null) _baseUris[replacement] = uri;
    if (element.parentNode != null) {
      element.replaceWith(replacement);
    } else {
      setBaseUri(replacement, baseUriOf(element));
    }
    final id = _ids.remove(element);
    if (id != null) {
      _ids[replacement] = id;
      _nodes[id] = replacement;
    }
    return replacement;
  }

  /// HTML 屬性名稱不分大小寫：找出實際存的那個鍵。
  static Object? _attributeKey(dom.Element element, String name) {
    final lower = name.toLowerCase();
    for (final key in element.attributes.keys) {
      if ('$key'.toLowerCase() == lower) return key;
    }
    return null;
  }

  static String _attributeValue(dom.Element element, String name) {
    final key = _attributeKey(element, name);
    return key == null ? '' : element.attributes[key] ?? '';
  }

  static void _setAttribute(dom.Element element, String name, String value) {
    element.attributes[_attributeKey(element, name) ?? name.toLowerCase()] =
        value;
  }

  String _absUrl(dom.Element element, String name) {
    final value = _attributeValue(element, name);
    if (value.isEmpty) return '';
    final relative = Uri.tryParse(value.trim());
    if (relative == null) return '';
    if (relative.hasScheme) return relative.toString();
    final base = Uri.tryParse(baseUriOf(element));
    if (base == null || !base.hasScheme) return '';
    return base.resolveUri(relative).toString();
  }

  String _data(dom.Node node) {
    if (node is dom.Element &&
        (node.localName == 'script' || node.localName == 'style')) {
      return node.text;
    }
    final root = node is dom.Document ? node.documentElement : node;
    if (root is! dom.Element) return '';
    return root
        .querySelectorAll('script, style')
        .map((script) => script.text)
        .join();
  }

  /// `text(文字)`：元素換掉底下的全部；文字節點改自己的內容；文件改
  /// `<body>` 的（Jsoup 的 Document.text）。
  dom.Node _setText(dom.Node node, String text) {
    if (node is dom.Text) {
      node.data = text;
      return node;
    }
    final target = node is dom.Document ? node.body ?? node : node;
    _detachChildren(target);
    target.nodes.add(dom.Text(text));
    return node;
  }

  void _setHtml(dom.Node node, String html) {
    _detachChildren(node);
    _insertHtml(node, html, (parsed) => node.nodes.addAll(parsed));
  }

  /// 清掉底下的節點；規則可能還拿著其中的元素，先把網址記在它們身上。
  void _detachChildren(dom.Node node) {
    for (final child in node.nodes) {
      _pinBaseUri(child);
    }
    node.nodes.clear();
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
