import '../js_extensions_base.dart';
import 'js_jsoup_connection.dart';

/// 規則 JS 的 Jsoup：`org.jsoup.Jsoup`、`Packages.org.jsoup`、
/// `java.getElements` 傳回的元素。JS 端的物件只帶 [JsoupBridge] 的編號，
/// 方法呼叫交給 Dart 的真 DOM；清單是加上 Jsoup `Elements` 方法的 JS 陣列，
/// `size()`／`get(i)` 與 `forEach`、`[i]` 都能用。
extension JsJsoupExtensions on JsExtensionsBase {
  void injectJsoupExtensions() {
    runtime.onMessage('jsoup', (dynamic args) {
      try {
        return jsoup.call(args as List);
      } catch (e) {
        // 交回 JS 丟成例外，和 Jsoup 在 Rhino 裡丟的一樣能被規則 catch。
        return {'__lrError': '$e'};
      }
    });

    runtime.evaluate(jsoupConnectionJs);
    runtime.evaluate(r'''
      (function(global) {
        var cache = {};
        global.__lrJsoupForget = function() { cache = {}; };

        function decode(value) {
          if (value == null || typeof value !== 'object') return value;
          if (Array.isArray(value)) return value.map(decode);
          if (value.__lrError !== undefined) throw new Error(value.__lrError);
          if (value.__lrList !== undefined) return elements(value.__lrList.map(decode));
          if (value.__lrNode !== undefined) {
            var node = cache[value.__lrNode];
            if (!node) {
              node = new LrNode(value.__lrNode, value.k);
              cache[value.__lrNode] = node;
            }
            return node;
          }
          return value;
        }
        global.__lrJsoupDecode = decode;

        /// 參數交給 Dart：節點帶編號，節點清單帶編號清單，Java 的 Pattern
        /// （JS 的正規式）用原文，其他物件轉成字串。
        function encodeArg(arg) {
          if (arg == null || typeof arg !== 'object') return arg;
          if (arg instanceof LrNode) return { __lrNode: arg.__lrElementId };
          if (arg instanceof RegExp) return arg.source;
          var items = Array.isArray(arg) ? arg
            : (typeof arg.toArray === 'function' ? arg.toArray() : null);
          if (items && (items.length === 0 || items[0] instanceof LrNode)) {
            return { __lrList: items.map(encodeArg) };
          }
          return String(arg);
        }

        function call(op, id, args) {
          var payload = [op, id];
          for (var i = 0; i < args.length; i++) payload.push(encodeArg(args[i]));
          return decode(sendMessage('jsoup', JSON.stringify(payload)));
        }
        function create(kind, value, baseUri) {
          return decode(sendMessage('jsoup', JSON.stringify(
            ['create', 0, kind, value == null ? '' : String(value), baseUri == null ? null : String(baseUri)])));
        }

        function LrNode(id, kind) {
          Object.defineProperty(this, '__lrElementId', { value: id, enumerable: false });
          Object.defineProperty(this, '__lrKind', { value: kind, enumerable: false });
        }
        var methods = [
          'text', 'ownText', 'wholeText', 'html', 'outerHtml', 'data', 'val',
          'hasAttr', 'removeAttr', 'absUrl', 'className',
          'hasClass', 'addClass', 'removeClass', 'toggleClass',
          'nodeName', 'normalName', 'select', 'selectFirst', 'is',
          'getElementById', 'getElementsByTag', 'getElementsByClass',
          'getElementsByAttribute', 'getElementsByAttributeValue',
          'getElementsContainingText', 'getElementsContainingOwnText',
          'getAllElements', 'body', 'head', 'location', 'baseUri',
          'setBaseUri', 'parent', 'parents', 'children', 'child',
          'childrenSize', 'firstElementChild', 'lastElementChild',
          'nextElementSibling', 'previousElementSibling', 'siblingElements',
          'elementSiblingIndex', 'nextSibling', 'previousSibling',
          'childNodes', 'childNodeSize', 'textNodes', 'cssSelector', 'remove',
          'empty', 'clone', 'append', 'prepend', 'appendText',
          'unwrap', 'isBlank', 'hasText',
          // Node
          'hasParent', 'attributesSize', 'clearAttributes', 'childNode',
          'childNodesCopy', 'firstChild', 'lastChild', 'root', 'siblingIndex',
          'siblingNodes', 'replaceWith', 'wrap', 'shallowClone', 'hasSameValue',
          'hashCode',
          // Element
          'appendChild', 'appendChildren', 'prependChild', 'prependChildren',
          'appendTo', 'appendElement', 'prependElement', 'prependText',
          'closest', 'expectFirst', 'selectXpath', 'dataNodes',
          'firstElementSibling', 'lastElementSibling', 'nextElementSiblings',
          'previousElementSiblings', 'getElementsByAttributeStarting',
          'getElementsByAttributeValueNot', 'getElementsByAttributeValueStarting',
          'getElementsByAttributeValueEnding',
          'getElementsByAttributeValueContaining',
          'getElementsByAttributeValueMatching', 'getElementsByIndexEquals',
          'getElementsByIndexLessThan', 'getElementsByIndexGreaterThan',
          'getElementsMatchingText', 'getElementsMatchingOwnText', 'isBlock',
          'wholeOwnText',
          // Document、TextNode
          'createElement', 'forms', 'expectForm', 'splitText'
        ];
        methods.forEach(function(name) {
          LrNode.prototype[name] = function() {
            return call(name, this.__lrElementId, Array.prototype.slice.call(arguments));
          };
        });
        /// 一個名稱有讀有寫的（`id()`、`id(值)`）：有參數時改用 [setter]。
        function overload(name, setter, isSet) {
          LrNode.prototype[name] = function() {
            var args = Array.prototype.slice.call(arguments);
            return call(isSet(args) ? setter : name, this.__lrElementId, args);
          };
        }
        var hasArgs = function(args) { return args.length > 0 && args[0] != null; };
        overload('id', 'idSet', hasArgs);
        overload('title', 'titleSet', hasArgs);
        overload('attr', 'attrFlag', function(args) { return typeof args[1] === 'boolean'; });
        overload('before', 'beforeNode', function(args) { return args[0] instanceof LrNode; });
        overload('after', 'afterNode', function(args) { return args[0] instanceof LrNode; });
        LrNode.prototype.tagName = function(name) {
          return name == null
            ? call('tagName', this.__lrElementId, [])
            : call('tagNameSet', this.__lrElementId, [name]);
        };
        LrNode.prototype.insertChildren = function(index) {
          return call('insertChildren', this.__lrElementId,
            Array.prototype.slice.call(arguments));
        };
        LrNode.prototype.getWholeText = LrNode.prototype.wholeText;
        LrNode.prototype.parentNode = LrNode.prototype.parent;
        LrNode.prototype.ownerDocument = function() {
          return call('ownerDocument', this.__lrElementId, []);
        };
        // DataNode（<script>、<style> 的內容）與 Comment。
        LrNode.prototype.getWholeData = LrNode.prototype.wholeText;
        LrNode.prototype.setWholeData = function(data) {
          return call('textSet', this.__lrElementId, [data]);
        };
        LrNode.prototype.getData = function() { return call('nodeData', this.__lrElementId, []); };
        LrNode.prototype.setData = LrNode.prototype.setWholeData;
        LrNode.prototype.isXmlDeclaration = function() {
          var data = this.getData();
          return data.length > 1 && (data.charAt(0) === '!' || data.charAt(0) === '?');
        };
        /// Jsoup 的 Tag：書源只會讀名稱、是不是區塊。
        LrNode.prototype.tag = function() {
          var node = this, name = node.tagName();
          return {
            getName: function() { return name; },
            getNormalName: function() { return name.toLowerCase(); },
            normalName: function() { return name.toLowerCase(); },
            isBlock: function() { return node.isBlock(); },
            isInline: function() { return !node.isBlock(); },
            toString: function() { return name; }
          };
        };
        LrNode.prototype.classNames = function(names) {
          if (names == null) return javaList(call('classNames', this.__lrElementId, []));
          var items = typeof names.toArray === 'function' ? names.toArray() : names;
          return this.attr('class', Array.prototype.slice.call(items).join(' '));
        };

        // ── 走訪：NodeVisitor、NodeFilter、Consumer 可以是物件或函式 ──
        function method(target, name) {
          if (typeof target === 'function') return name === 'tail' ? null : target;
          return target != null && typeof target[name] === 'function'
            ? function() { return target[name].apply(target, arguments); } : null;
        }
        function traverseNode(root, visitor) {
          var head = method(visitor, 'head'), tail = method(visitor, 'tail');
          (function walk(node, depth) {
            if (head) head(node, depth);
            var kids = node.childNodes();
            for (var i = 0; i < kids.length; i++) walk(kids[i], depth + 1);
            if (tail) tail(node, depth);
          })(root, 0);
        }
        /// Jsoup NodeTraversor.filter：head 的結果決定要不要往下、要不要拿掉。
        function filterNode(node, depth, filter) {
          var head = method(filter, 'head') || method(filter, 'filter');
          var tail = method(filter, 'tail');
          var result = String(head ? head(node, depth) : 'CONTINUE');
          if (result === 'STOP') return 'STOP';
          if (result === 'CONTINUE') {
            var kids = node.childNodes();
            for (var i = 0; i < kids.length; i++) {
              if (filterNode(kids[i], depth + 1, filter) === 'STOP') return 'STOP';
            }
          }
          if (result === 'CONTINUE' || result === 'SKIP_CHILDREN') {
            var after = String(tail ? tail(node, depth) : 'CONTINUE');
            if (after === 'STOP') return 'STOP';
            if (after === 'REMOVE') node.remove();
          }
          if (result === 'REMOVE') node.remove();
          return 'CONTINUE';
        }
        function accept(consumer) {
          return method(consumer, 'accept') || method(consumer, 'apply');
        }
        LrNode.prototype.traverse = function(visitor) { traverseNode(this, visitor); return this; };
        LrNode.prototype.filter = function(filter) { filterNode(this, 0, filter); return this; };
        LrNode.prototype.forEachNode = function(consumer) {
          var fn = accept(consumer);
          traverseNode(this, function(node) { fn(node); });
          return this;
        };
        LrNode.prototype.forEach = function(consumer) {
          var fn = accept(consumer);
          this.getAllElements().forEach(function(element) { fn(element); });
          return this;
        };
        /// Java 的 List<String>（eachText、classNames 這類）：陣列加上 size/get。
        function javaList(items) {
          var list = items.slice();
          Object.defineProperty(list, 'size', { value: function() { return list.length; }, enumerable: false });
          Object.defineProperty(list, 'get', { value: function(i) { return list[i]; }, enumerable: false });
          Object.defineProperty(list, 'isEmpty', { value: function() { return list.length === 0; }, enumerable: false });
          Object.defineProperty(list, 'contains', { value: function(v) { return list.indexOf(v) >= 0; }, enumerable: false });
          return list;
        }
        LrNode.prototype.classNames = function() {
          return javaList(call('classNames', this.__lrElementId, []));
        };
        LrNode.prototype.attributes = function() {
          return attributes(call('attributes', this.__lrElementId, []));
        };
        LrNode.prototype.dataset = function() {
          var result = {};
          this.attributes().forEach(function(a) {
            if (a.getKey().indexOf('data-') === 0) result[a.getKey().substring(5)] = a.getValue();
          });
          return result;
        };
        LrNode.prototype.equals = function(other) {
          return other != null && other.__lrElementId === this.__lrElementId;
        };
        LrNode.prototype.toString = function() { return this.outerHtml(); };

        function attributes(pairs) {
          var list = pairs.map(function(pair) {
            return {
              getKey: function() { return pair[0]; },
              getValue: function() { return pair[1]; },
              key: pair[0],
              value: pair[1],
              toString: function() { return pair[0] + '="' + pair[1] + '"'; }
            };
          });
          function hide(name, fn) { Object.defineProperty(list, name, { value: fn, enumerable: false }); }
          hide('size', function() { return list.length; });
          hide('get', function(key) {
            for (var i = 0; i < list.length; i++) if (list[i].key === key) return list[i].value;
            return '';
          });
          hide('hasKey', function(key) { return list.some(function(a) { return a.key === key; }); });
          hide('asList', function() { return list.slice(); });
          hide('html', function() { return list.map(String).join(' '); });
          return list;
        }

        function elements(items) {
          var list = items;
          function hide(name, fn) { Object.defineProperty(list, name, { value: fn, enumerable: false, configurable: true }); }
          function each(fn) { for (var i = 0; i < list.length; i++) fn(list[i]); return list; }
          function union(op, args) {
            var seen = {}, out = [];
            each(function(node) {
              var found = node[op].apply(node, args);
              (Array.isArray(found) ? found : (found == null ? [] : [found])).forEach(function(n) {
                if (!seen[n.__lrElementId]) { seen[n.__lrElementId] = true; out.push(n); }
              });
            });
            return elements(out);
          }
          hide('size', function() { return list.length; });
          hide('get', function(i) {
            if (i < 0 || i >= list.length) throw new Error('Index: ' + i + ', Size: ' + list.length);
            return list[i];
          });
          hide('isEmpty', function() { return list.length === 0; });
          hide('first', function() { return list.length ? list[0] : null; });
          hide('last', function() { return list.length ? list[list.length - 1] : null; });
          hide('eq', function(i) { return elements(list[i] ? [list[i]] : []); });
          hide('text', function(value) {
            if (arguments.length) return each(function(n) { n.text(value); });
            return list.map(function(n) { return n.text(); }).filter(function(t) { return t.length; }).join(' ');
          });
          hide('eachText', function() {
            return javaList(list.map(function(n) { return n.text(); }).filter(function(t) { return t.length; }));
          });
          hide('html', function(value) {
            if (arguments.length) return each(function(n) { n.html(value); });
            return list.map(function(n) { return n.html(); }).join('\n');
          });
          hide('outerHtml', function() { return list.map(function(n) { return n.outerHtml(); }).join('\n'); });
          hide('toString', function() { return list.outerHtml(); });
          hide('attr', function(name, value) {
            if (arguments.length > 1) return each(function(n) { n.attr(name, value); });
            for (var i = 0; i < list.length; i++) if (list[i].hasAttr(name)) return list[i].attr(name);
            return '';
          });
          hide('eachAttr', function(name) {
            var out = [];
            each(function(n) { if (n.hasAttr(name)) out.push(n.attr(name)); });
            return javaList(out);
          });
          hide('hasAttr', function(name) { return list.some(function(n) { return n.hasAttr(name); }); });
          hide('hasClass', function(name) { return list.some(function(n) { return n.hasClass(name); }); });
          hide('hasText', function() { return list.some(function(n) { return n.hasText(); }); });
          hide('is', function(css) { return list.some(function(n) { return n.is(css); }); });
          hide('not', function(css) { return elements(list.filter(function(n) { return !n.is(css); })); });
          hide('select', function(css) { return union('select', [css]); });
          hide('parents', function() { return union('parents', []); });
          /// Jsoup Elements.next／nextAll／prev／prevAll：每個元素往後（往前）
          /// 的兄弟元素，符合 [css] 的；和 Jsoup 一樣不去掉重複。
          function siblings(next, all, css) {
            var out = [];
            each(function(node) {
              var current = node;
              do {
                current = next ? current.nextElementSibling() : current.previousElementSibling();
                if (current == null) break;
                if (css == null || current.is(css)) out.push(current);
              } while (all);
            });
            return elements(out);
          }
          hide('next', function(css) { return siblings(true, false, css); });
          hide('nextAll', function(css) { return siblings(true, true, css); });
          hide('prev', function(css) { return siblings(false, false, css); });
          hide('prevAll', function(css) { return siblings(false, true, css); });
          hide('wrap', function(h) { return each(function(n) { n.wrap(h); }); });
          hide('tagName', function(t) { return each(function(n) { n.tagName(t); }); });
          hide('toggleClass', function(c) { return each(function(n) { n.toggleClass(c); }); });
          hide('comments', function() {
            var out = [];
            each(function(n) {
              n.childNodes().forEach(function(c) { if (c.__lrKind === 'comment') out.push(c); });
            });
            return out;
          });
          hide('dataNodes', function() { return union('dataNodes', []); });
          hide('forms', function() { return list.filter(function(n) { return n.tagName() === 'form'; }); });
          hide('traverse', function(visitor) { return each(function(n) { traverseNode(n, visitor); }); });
          // JS 陣列的 filter(函式) 照舊；Jsoup 的 filter(NodeFilter) 是物件。
          hide('filter', function(filter) {
            if (typeof filter === 'function') {
              return elements(Array.prototype.filter.apply(list, arguments));
            }
            return each(function(n) { filterNode(n, 0, filter); });
          });
          hide('forEach', function(consumer) {
            if (typeof consumer === 'function') {
              Array.prototype.forEach.apply(list, arguments);
              return;
            }
            var fn = accept(consumer);
            each(function(n) { fn(n); });
          });
          hide('remove', function() { return each(function(n) { n.remove(); }); });
          hide('empty', function() { return each(function(n) { n.empty(); }); });
          hide('addClass', function(c) { return each(function(n) { n.addClass(c); }); });
          hide('removeClass', function(c) { return each(function(n) { n.removeClass(c); }); });
          hide('removeAttr', function(a) { return each(function(n) { n.removeAttr(a); }); });
          hide('append', function(h) { return each(function(n) { n.append(h); }); });
          hide('prepend', function(h) { return each(function(n) { n.prepend(h); }); });
          hide('before', function(h) { return each(function(n) { n.before(h); }); });
          hide('after', function(h) { return each(function(n) { n.after(h); }); });
          hide('unwrap', function() { return each(function(n) { n.unwrap(); }); });
          hide('clone', function() { return elements(list.map(function(n) { return n.clone(); })); });
          hide('val', function(value) {
            if (arguments.length) return each(function(n) { n.val(value); });
            return list.length ? list[0].val() : '';
          });
          hide('toArray', function() { return list.slice(); });
          // Elements 是 ArrayList<Element>：書源自己組清單時 add、addAll。
          hide('add', function(node) { list.push(node); return true; });
          hide('addAll', function(more) {
            var items = typeof more.toArray === 'function' ? more.toArray() : more;
            for (var i = 0; i < items.length; i++) list.push(items[i]);
            return items.length > 0;
          });
          hide('asList', function() { return list.slice(); });
          hide('textNodes', function() { return union('textNodes', []); });
          return list;
        }
        global.__lrJsoupElements = elements;

        var Jsoup = {
          parse: function(html, baseUri) {
            return decode(sendMessage('jsoup', JSON.stringify(
              ['parse', 0, html == null ? '' : String(html), baseUri == null ? null : String(baseUri)])));
          },
          parseBodyFragment: function(html, baseUri) {
            return decode(sendMessage('jsoup', JSON.stringify(
              ['parseBodyFragment', 0, html == null ? '' : String(html), baseUri == null ? null : String(baseUri)])));
          },
          connect: function(url) { return global.__lrJsoupConnection(url); },
          newSession: function() { return global.__lrJsoupConnection(null); }
        };
        var Parser = {
          unescapeEntities: function(text) {
            return sendMessage('jsoup', JSON.stringify(['unescapeEntities', 0, text == null ? '' : String(text)]));
          }
        };
        /// `new org.jsoup.nodes.Element('div')` 這類建構式：傳回物件的建構式，
        /// `new` 拿到的就是那個物件。
        function Element(tag, baseUri) { return create('element', tag, baseUri); }
        function TextNode(text) { return create('text', text); }
        TextNode.createFromEncoded = function(encoded) { return create('encodedText', encoded); };
        function DataNode(data) { return create('data', data); }
        function Comment(data) { return create('comment', data); }
        function Document(baseUri) { return create('document', '', baseUri); }
        Document.createShell = function(baseUri) { return Jsoup.parse('', baseUri); };
        var FilterResult = {};
        ['CONTINUE', 'SKIP_CHILDREN', 'SKIP_ENTIRELY', 'REMOVE', 'STOP'].forEach(function(name) {
          FilterResult[name] = name;
        });
        // new NodeVisitor({head: …, tail: …})：Rhino 實作 Java 介面的寫法。
        function NodeVisitor(impl) { return impl; }
        function NodeFilter(impl) { return impl; }
        NodeFilter.FilterResult = FilterResult;
        // Rhino 的 importClass 用類別名稱放進全域。
        [[Jsoup, 'Jsoup'], [Parser, 'Parser'], [Element, 'Element'], [TextNode, 'TextNode'],
         [DataNode, 'DataNode'], [Comment, 'Comment'], [Document, 'Document'],
         [NodeVisitor, 'NodeVisitor'], [NodeFilter, 'NodeFilter']].forEach(function(pair) {
          Object.defineProperty(pair[0], '__lrClassName', { value: pair[1], enumerable: false });
        });
        global.org = global.org || {};
        global.org.jsoup = {
          Jsoup: Jsoup,
          Connection: { Method: global.__lrJsoupMethod },
          parser: { Parser: Parser },
          nodes: {
            Document: Document, Element: Element, TextNode: TextNode,
            DataNode: DataNode, Comment: Comment
          },
          select: {
            // new Elements([元素清單])：書源自己組元素清單。
            Elements: function(items) {
              var list = [];
              if (items != null && typeof items === 'object') {
                var source = typeof items.toArray === 'function' ? items.toArray() : items;
                for (var i = 0; i < source.length; i++) list.push(source[i]);
              }
              return elements(list);
            },
            NodeVisitor: NodeVisitor,
            NodeFilter: NodeFilter
          }
        };
      })(globalThis);
    ''');
  }
}
