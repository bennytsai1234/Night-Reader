import '../js_extensions_base.dart';

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

        function call(op, id, args) {
          var payload = [op, id];
          for (var i = 0; i < args.length; i++) {
            var arg = args[i];
            payload.push(arg != null && typeof arg === 'object' ? String(arg) : arg);
          }
          return decode(sendMessage('jsoup', JSON.stringify(payload)));
        }

        function LrNode(id, kind) {
          Object.defineProperty(this, '__lrElementId', { value: id, enumerable: false });
          Object.defineProperty(this, '__lrKind', { value: kind, enumerable: false });
        }
        var methods = [
          'text', 'ownText', 'wholeText', 'html', 'outerHtml', 'data', 'val',
          'attr', 'hasAttr', 'removeAttr', 'absUrl', 'id', 'className',
          'hasClass', 'addClass', 'removeClass', 'toggleClass',
          'nodeName', 'normalName', 'select', 'selectFirst', 'is',
          'getElementById', 'getElementsByTag', 'getElementsByClass',
          'getElementsByAttribute', 'getElementsByAttributeValue',
          'getElementsContainingText', 'getElementsContainingOwnText',
          'getAllElements', 'body', 'head', 'title', 'location', 'baseUri',
          'setBaseUri', 'parent', 'parents', 'children', 'child',
          'childrenSize', 'firstElementChild', 'lastElementChild',
          'nextElementSibling', 'previousElementSibling', 'siblingElements',
          'elementSiblingIndex', 'nextSibling', 'previousSibling',
          'childNodes', 'childNodeSize', 'textNodes', 'cssSelector', 'remove',
          'empty', 'clone', 'append', 'prepend', 'appendText', 'before',
          'after', 'unwrap', 'isBlank', 'hasText'
        ];
        methods.forEach(function(name) {
          LrNode.prototype[name] = function() {
            return call(name, this.__lrElementId, Array.prototype.slice.call(arguments));
          };
        });
        LrNode.prototype.tagName = function(name) {
          return name == null
            ? call('tagName', this.__lrElementId, [])
            : call('tagNameSet', this.__lrElementId, [name]);
        };
        LrNode.prototype.getWholeText = LrNode.prototype.wholeText;
        LrNode.prototype.parentNode = LrNode.prototype.parent;
        LrNode.prototype.ownerDocument = function() {
          return call('ownerDocument', this.__lrElementId, []);
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
          hide('next', function() { return union('nextElementSibling', []); });
          hide('prev', function() { return union('previousElementSibling', []); });
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
          }
        };
        var Parser = {
          unescapeEntities: function(text) {
            return sendMessage('jsoup', JSON.stringify(['unescapeEntities', 0, text == null ? '' : String(text)]));
          }
        };
        // Rhino 的 importClass 用類別名稱放進全域。
        Object.defineProperty(Jsoup, '__lrClassName', { value: 'Jsoup', enumerable: false });
        Object.defineProperty(Parser, '__lrClassName', { value: 'Parser', enumerable: false });
        global.org = global.org || {};
        global.org.jsoup = {
          Jsoup: Jsoup,
          parser: { Parser: Parser },
          nodes: { Document: { createShell: function(baseUri) { return Jsoup.parse('', baseUri); } } }
        };
      })(globalThis);
    ''');
  }
}
