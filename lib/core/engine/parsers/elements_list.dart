import 'package:html/dom.dart';
import 'package:xpath_selector/xpath_selector.dart';

/// 上一條規則找到的一組元素交給下一條規則時的讀法，同 Legado 把 Jsoup 的
/// `Elements` 交下去：`Elements.toString()` 是每個元素的 HTML 用換行接起來。
/// 清單裡可能是網頁元素，或 XPath 找到的節點（[XPathNode]）。

Element? _elementOf(Object? item) => switch (item) {
  final Element element => element,
  XPathNode(:final node) when node is Element => node,
  _ => null,
};

/// 清單只有一個元素時傳回它，下一條規則直接從它查。
Element? elementsListSingle(List<dynamic> items) =>
    items.length == 1 ? _elementOf(items.single) : null;

/// 每一項的 HTML 用換行接起來；不是元素的照文字。
String elementsListHtml(List<dynamic> items) =>
    [for (final item in items) _elementOf(item)?.outerHtml ?? '${item ?? ''}']
        .join('\n');
