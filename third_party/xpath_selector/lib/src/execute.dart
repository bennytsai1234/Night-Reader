import 'package:xpath_selector/src/utils/dom_selector.dart';
import 'package:xpath_selector/src/selector.dart';
import 'package:xpath_selector/src/utils/utils.dart';
import 'model/base.dart';
import 'expression.dart';

List<XPathNode<T>> execute<T>({
  required List<Selector> selectorList,
  required XPathNode<T> element,
}) {
  var tmp = <XPathNode<T>>[element];

  for (final selector in selectorList) {
    final rootMatch = <XPathNode<T>>[];
    for (final element in tmp) {
      final pathXPathNode = _matchSelectPath<T>(selector, element);
      final selectorMatch = <XPathNode<T>>[];
      for (final element in pathXPathNode) {
        final axisXPathNode = _matchAxis<T>(selector, element);
        final removeIndex = [];

        // _matchSelector
        for (var i = 0; i < axisXPathNode.length; i++) {
          final element = axisXPathNode[i];
          if (!_matchSelector(
              selector: selector,
              element: element,
              position: i,
              length: axisXPathNode.length)) {
            removeIndex.add(i);
          }
        }
        for (final index in removeIndex.reversed) {
          axisXPathNode.removeAt(index);
        }
        removeIndex.clear();

        // matchPredicates
        for (final predicate in selector.axes.predicate) {
          for (var i = 0; i < axisXPathNode.length; i++) {
            final element = axisXPathNode[i];
            if (!_matchPredicates(
              selector: selector,
              element: element,
              position: i,
              length: axisXPathNode.length,
              predicate: predicate,
            )) {
              removeIndex.add(i);
            }
          }
          for (final index in removeIndex.reversed) {
            axisXPathNode.removeAt(index);
          }
          removeIndex.clear();
        }

        selectorMatch.addAllIfNotExist(axisXPathNode);
      }
      rootMatch.addAllIfNotExist(selectorMatch);
    }
    tmp = rootMatch;
  }
  return tmp;
}

/// Get element by path
List<XPathNode<T>> _matchSelectPath<T>(Selector selector, XPathNode<T> node) {
  final waitingSelect = <XPathNode<T>>[];
  switch (selector.selectorType) {
    case SelectorType.descendant:
      waitingSelect.addAllIfNotExist(descentOrSelf<T>(node));
      break;
    case SelectorType.self:
      waitingSelect.addIfNotExist(node);
      break;
  }
  return waitingSelect;
}

/// Get element by Axis
List<XPathNode<T>> _matchAxis<T>(Selector selector, XPathNode<T> node) {
  final waitingSelect = <XPathNode<T>>[];
  switch (selector.axes.axis) {
    case AxesAxis.child:
    case null:
      waitingSelect.addAllIfNotExist(node.children);
      break;
    case AxesAxis.ancestor:
      waitingSelect.addAllIfNotExist(ancestor(node));
      break;
    case AxesAxis.ancestorOrSelf:
      waitingSelect.addAllIfNotExist(ancestorOrSelf(node));
      break;
    case AxesAxis.descendant:
      waitingSelect.addAllIfNotExist(descendant(node));
      break;
    case AxesAxis.descendantOrSelf:
      waitingSelect.addAllIfNotExist(descentOrSelf(node));
      break;
    case AxesAxis.following:
      waitingSelect.addAllIfNotExist(following(top(node) ?? node, node));
      break;
    case AxesAxis.parent:
      if (node.parent != null) waitingSelect.add(node.parent!);
      break;
    case AxesAxis.followingSibling:
      waitingSelect.addAllIfNotExist(followingSibling(node));
      break;
    case AxesAxis.precedingSibling:
      waitingSelect.addAllIfNotExist(precedingSibling(node));
      break;
    case AxesAxis.attribute:
    case AxesAxis.self:
      waitingSelect.addIfNotExist(node);
      break;
    case AxesAxis.preceding:
      waitingSelect.addAllIfNotExist(preceding(node));
      break;
    case AxesAxis.followingSiblingOne:
      waitingSelect.addAllIfNotExist(followingSiblingOne(node));
      break;
    case AxesAxis.precedingSiblingOne:
      waitingSelect.addAllIfNotExist(precedingSiblingOne(node));
      break;
  }
  return waitingSelect;
}

/// Is element match [Selector]'s [selector.axes.nodeTest] and [predicate]
bool _matchSelector({
  required Selector selector,
  required XPathNode element,
  required int position,
  required int length,
}) {
  if (selector.attr != null) return true;
  if (selector.axes.axis == AxesAxis.attribute) return true;

  // node-test
  final nodeTest = selector.axes.nodeTest;

  if (nodeTest != 'node()') {
    if (!element.isElement) return false;
    if (nodeTest != '*' && element.name?.qualified != nodeTest) return false;
  }
  return true;
}

/// Is element match [selector.axes.predicate]
///
/// Night Reader patch: the predicate is evaluated as an expression
/// ([evaluateExpression], JsoupXpath 2.5.3). A number is a position among
/// the nodes being filtered, counted from the end when negative (`[-1]` is
/// the last, JsoupXpath); anything else holds when it is true or not empty.
bool _matchPredicates({
  required Selector selector,
  required XPathNode element,
  required int position,
  required int length,
  required String predicate,
}) {
  final value = evaluateExpression(
    predicate,
    XContext(element, position: position + 1, size: length),
  );
  if (value is XNumber) {
    var index = value.value.toInt();
    if (index < 0) index = length + index + 1;
    return index == position + 1;
  }
  return value.asBool;
}
