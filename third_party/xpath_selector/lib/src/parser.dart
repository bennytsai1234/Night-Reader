import 'package:xpath_selector/src/expression.dart';
import 'package:xpath_selector/src/selector.dart';

import 'model/base.dart';

/// parse xpath selector
List<List<Selector>> parseSelectGroup(String xpath) {
  final combine = splitXPathUnion(xpath);
  final selectorList = <List<Selector>>[];

  for (final _path in combine) {
    final path = _path.trim();
    final xpathItem = splitXPathSteps(path);
    selectorList.add([
      for (var i = 0; i < xpathItem.length; i++)
        _parseSelector(xpathItem[i], first: i == 0),
    ]);
  }

  return selectorList;
}

/// Night Reader patch: split a union on its top-level `|` only. A `|` inside
/// quotes, `[...]` or `(...)` belongs to a value or a predicate
/// (`a[@data-ref='v1|part']`), as in XPath 1.0 and JsoupXpath.
List<String> splitXPathUnion(String xpath) {
  final parts = <String>[];
  var depth = 0;
  String? quote;
  var start = 0;
  for (var i = 0; i < xpath.length; i++) {
    final char = xpath[i];
    if (quote != null) {
      if (char == quote) quote = null;
    } else if (char == '"' || char == "'") {
      quote = char;
    } else if (char == '[' || char == '(') {
      depth++;
    } else if (char == ']' || char == ')') {
      if (depth > 0) depth--;
    } else if (char == '|' && depth == 0) {
      parts.add(xpath.substring(start, i));
      start = i + 1;
    }
  }
  parts.add(xpath.substring(start));
  return parts;
}

/// Night Reader patch: split a location path into its steps, each with its
/// leading `/` or `//`, on the slashes outside quotes, `[...]` and `(...)`.
/// Upstream matched steps with a regular expression that dropped `..` and
/// `.`, and cut predicates holding `]` or a function with arguments.
List<String> splitXPathSteps(String path) {
  final steps = <String>[];
  var depth = 0;
  String? quote;
  var start = 0;
  for (var i = 0; i < path.length; i++) {
    final char = path[i];
    if (quote != null) {
      if (char == quote) quote = null;
    } else if (char == '"' || char == "'") {
      quote = char;
    } else if (char == '[' || char == '(') {
      depth++;
    } else if (char == ']' || char == ')') {
      if (depth > 0) depth--;
    } else if (char == '/' && depth == 0 && i > start) {
      // A `//` starts at its first slash.
      if (i > 0 && path[i - 1] == '/') continue;
      final step = path.substring(start, i).trim();
      if (step.isNotEmpty && step != '/' && step != '//') steps.add(step);
      start = i;
    }
  }
  final last = path.substring(start).trim();
  if (last.isNotEmpty && last != '/' && last != '//') steps.add(last);
  return steps;
}

/// Night Reader patch: the predicates of a step (`li[@class='a'][2]`),
/// matching brackets outside quotes so a predicate may hold `]` or a nested
/// predicate. Returns the node test without them and the predicates.
(String, List<String>) _splitPredicates(String step) {
  final predicates = <String>[];
  final nodeTest = StringBuffer();
  var depth = 0;
  String? quote;
  var start = -1;
  for (var i = 0; i < step.length; i++) {
    final char = step[i];
    if (quote != null) {
      if (char == quote) quote = null;
      continue;
    }
    if (depth > 0 && (char == '"' || char == "'")) {
      quote = char;
    } else if (char == '[') {
      if (depth == 0) start = i + 1;
      depth++;
      continue;
    } else if (char == ']') {
      depth--;
      if (depth == 0) predicates.add(step.substring(start, i).trim());
      continue;
    }
    if (depth == 0) nodeTest.write(char);
  }
  return (nodeTest.toString().trim(), predicates);
}

Selector _parseSelector(String input, {required bool first}) {
  late String source;
  late SelectorType selectorType;
  if (input.startsWith('//')) {
    // descendant
    selectorType = SelectorType.descendant;
    source = input.substring(2);
  } else if (input.startsWith('/')) {
    // self
    selectorType = SelectorType.self;
    source = input.substring(1);
  } else if (first && RegExp(r'^[A-Za-z_*][\w.:-]*(?:\[|$)').hasMatch(input)) {
    // Night Reader patch: a relative location path (`div[2]/a/@href`) starts
    // with a child step from the node being queried, the same as `/div[2]`
    // from that node (XPath 1.0, JsoupXpath). Only the first step, and only
    // an element name: later steps still need their `/`, and a path starting
    // with `@`, `text()` or `.` is still rejected.
    selectorType = SelectorType.self;
    source = input;
  } else {
    throw FormatException("'$input' is not a valid xpath query string");
  }

  final simpleSelector = _parseSimpleSelector(selectorType, source);
  if (simpleSelector != null) return simpleSelector;

  // Axis
  AxesAxis? axis;
  late String withoutAxis;
  if (source.contains('::')) {
    final pattern = source.split('::');
    if (pattern.length > 2) throw UnsupportedError('Not support multiple axis');
    axis = SelectorAxes.createAxis(pattern.first.trim());
    withoutAxis = pattern.last.trim();
  } else {
    withoutAxis = source;
  }

  var (nodeTest, predicateList) = _splitPredicates(withoutAxis);
  // Night Reader patch: a node test is a name, `*`, `.`, `..` or `node()`;
  // anything else (`div[2] div`, a missing `/`) is not a valid path.
  if (!RegExp(r'^(?:[A-Za-z_*][\w.:*-]*|\.\.?|node\(\))$').hasMatch(nodeTest)) {
    throw FormatException("'$input' is not a valid xpath query string");
  }

  if (nodeTest == '.') {
    axis = AxesAxis.self;
    nodeTest = '*';
  } else if (nodeTest == '..') {
    axis = AxesAxis.parent;
    nodeTest = '*';
  }

  return Selector(
      selectorType: selectorType,
      axes: SelectorAxes(
        nodeTest: nodeTest,
        axis: axis,
        predicate: predicateList,
      ));
}

Selector? _parseSimpleSelector(SelectorType selectorType, String source) {
  // attr
  if (source.startsWith('@')) {
    return Selector(
      selectorType: selectorType,
      axes: SelectorAxes(axis: AxesAxis.self, nodeTest: '*', predicate: []),
      attr: source.substring(1),
    );
  }

  // parents
  if (source == '..') {
    return Selector(
        selectorType: selectorType,
        axes: SelectorAxes(
          axis: AxesAxis.parent,
          nodeTest: '*',
          predicate: [],
        ));
  }

  // self
  if (source == '.') {
    return Selector(
        selectorType: selectorType,
        axes: SelectorAxes(
          axis: AxesAxis.self,
          nodeTest: '*',
          predicate: [],
        ));
  }

  // node()
  if (source == 'node()') {
    return Selector(
      selectorType: selectorType,
      axes: SelectorAxes(
        nodeTest: 'node()',
        axis: AxesAxis.child,
        predicate: [],
      ),
    );
  }

  // text() string() .. xxx(), and (Night Reader patch) JsoupXpath's
  // functions with arguments as the last step:
  // `substring-after(text(),'：')`, `num()`.
  final function = RegExp(r'^[\w-]+\(.*\)$').firstMatch(source);
  if (function != null) {
    return Selector(
      selectorType: selectorType,
      function: function.group(0),
      axes: SelectorAxes(
        nodeTest: '*',
        axis: AxesAxis.self,
        predicate: [],
      ),
    );
  }
  return null;
}

/// if last selector is @attr or function, add to result
List<String?> parseAttr({
  required List<Selector> selectorList,
  required List<XPathNode> elements,
}) {
  final result = <String?>[];

  if (selectorList.isNotEmpty) {
    final lastSelector = selectorList.last;
    for (final element in elements) {
      if (lastSelector.attr != null) {
        // @attr
        if (lastSelector.attr == '*') {
          result.addAll(element.attributes.values);
        } else {
          result.add(element.attributes[lastSelector.attr]);
        }
      } else if (lastSelector.function != null) {
        // function
        result.add(
            elementFunction(node: element, function: lastSelector.function!));
      } else if (lastSelector.axes.axis == AxesAxis.attribute) {
        // attr
        if (lastSelector.axes.nodeTest == '*') {
          result.addAll(element.attributes.values);
        } else {
          result.add(element.attributes[lastSelector.axes.nodeTest]);
        }
      }
    }
  }
  return result;
}

/// if node-test is text() or other functions
String? elementFunction({required XPathNode node, required String function}) {
  if (function.startsWith('@')) {
    return node.attributes[function.substring(1)];
  } else {
    switch (function) {
      case 'text()':
      case 'string()':
      // Night Reader patch: JsoupXpath `allText()`, all the text inside.
      case 'allText()':
        return node.text ?? '';
      // Night Reader patch: JsoupXpath `num()`, the first number in the
      // text.
      case 'num()':
        return numberIn(node.text ?? '');
      case 'name()':
      case 'qualified()':
        return node.name?.qualified;
      case 'local-name()':
        return node.name?.localName;
      case 'namespace()':
      case 'prefix()':
        return node.name?.namespace;
      default:
        // Night Reader patch: a JsoupXpath function call
        // (`substring-after(text(),'：')`) with this node as the context.
        if (isExpressionFunction(function)) {
          return evaluateExpression(function, XContext(node)).asString;
        }
        throw UnsupportedError('Unsupported function: $function');
    }
  }
}
