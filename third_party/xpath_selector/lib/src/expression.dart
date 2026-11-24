// Night Reader patch: an expression evaluator for predicates and function
// steps, following JsoupXpath 2.5.3 (the XPath engine Legado uses):
// `or`/`and`, `=`/`!=` (compared as strings when the types differ), `<` `>`
// `<=` `>=`, JsoupXpath's `^=` `$=` `*=` `~=` (whole match) `!~`, `+` `-` `*`
// `div` `mod`, `|`, unary `-`, string and number literals, location paths
// relative to the context node, and JsoupXpath's functions.
import 'package:xpath_selector/src/builder.dart';
import 'package:xpath_selector/src/model/base.dart';

/// A value an expression evaluates to (JsoupXpath `XValue`).
sealed class XValue {
  const XValue();

  /// JsoupXpath `asString`: nodes are their own text joined, strings from a
  /// path are joined with `,`.
  String get asString;

  bool get asBool;

  double get asNumber {
    final text = asString.trim();
    return double.tryParse(text) ?? double.nan;
  }
}

class XNumber extends XValue {
  const XNumber(this.value);
  final double value;

  @override
  String get asString => value == value.truncateToDouble() && value.isFinite
      ? value.toInt().toString()
      : value.toString();

  @override
  bool get asBool => value != 0 && !value.isNaN;

  @override
  double get asNumber => value;
}

class XString extends XValue {
  const XString(this.value);
  final String value;

  @override
  String get asString => value.trim();

  @override
  bool get asBool => value.trim().isNotEmpty;
}

class XBool extends XValue {
  const XBool(this.value);
  final bool value;

  @override
  String get asString => value.toString();

  @override
  bool get asBool => value;

  @override
  double get asNumber => value ? 1 : 0;
}

/// Element nodes from a location path.
class XNodes extends XValue {
  const XNodes(this.nodes);
  final List<XPathNode> nodes;

  @override
  String get asString => nodes.map(ownText).join();

  @override
  bool get asBool => nodes.isNotEmpty;
}

/// Strings from a location path ending in `@attr` or `text()`.
class XList extends XValue {
  const XList(this.values);
  final List<String> values;

  @override
  String get asString => values.join(',');

  @override
  bool get asBool => values.isNotEmpty;
}

/// The element's own text nodes, whitespace collapsed (JsoupXpath `text()`:
/// one text element for each of Jsoup `textNodes()`, read with `ownText`).
/// A text node itself is its own text.
List<String> ownTextNodes(XPathNode node) {
  if (!node.isElement) return [_collapse(node.text ?? '')];
  final texts = XPathNode.textNodesOf?.call(node.node, false) ??
      [
        for (final child in node.children)
          if (!child.isElement) child.text ?? '',
      ];
  return [for (final text in texts) _collapse(text)];
}

/// The element's own text, without its child elements (Jsoup `ownText`).
String ownText(XPathNode node) => _collapse(ownTextNodes(node).join(' '));

String _collapse(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The context of one evaluation: the node a predicate is tested on, its
/// 1-based position among the nodes being filtered and how many there are.
class XContext {
  const XContext(this.node, {this.position = 1, this.size = 1});
  final XPathNode node;
  final int position;
  final int size;
}

/// Evaluates [expression] for [context].
XValue evaluateExpression(String expression, XContext context) =>
    _parse(expression).eval(context);

/// Parsed expressions: a predicate is evaluated once for every node it
/// filters (each chapter of a table of contents).
final Map<String, _Node> _parsed = {};

_Node _parse(String expression) {
  final cached = _parsed[expression];
  if (cached != null) return cached;
  final parser = _Parser(_tokenize(expression), expression);
  final ast = parser.parseExpr();
  parser.expectEnd();
  if (_parsed.length >= 256) _parsed.remove(_parsed.keys.first);
  return _parsed[expression] = ast;
}

// ── tokens ──────────────────────────────────────────────────────────────

enum _T { number, string, path, name, op, lparen, rparen, comma, end }

class _Token {
  const _Token(this.type, this.text);
  final _T type;
  final String text;

  @override
  String toString() => '$type($text)';
}

const _wordOperators = {'and', 'or', 'div', 'mod'};

/// Functions JsoupXpath evaluates as a function call; other `name(...)`
/// (`text()`, `node()`, `allText()`, `html()`, `outerHtml()`, `num()`) are
/// node tests and read as a location path.
const _functions = {
  'concat',
  'contains',
  'count',
  'ends-with',
  'first',
  'last',
  'not',
  'position',
  'starts-with',
  'string-length',
  'substring',
  'substring-after',
  'substring-after-last',
  'substring-before',
  'substring-before-last',
  'substring-ex',
  'sum',
};

/// Whether [call] (`substring-after(text(),'：')`) is one of JsoupXpath's
/// functions this evaluator knows. Others (`format-date`) are rejected
/// instead of being read as a location path.
bool isExpressionFunction(String call) {
  final name = RegExp(r'^\s*([\w-]+)\s*\(').firstMatch(call)?.group(1);
  return name != null && _functions.contains(name);
}

/// Node tests read as a location path (`text()`, `num()`).
const _nodeTests = {
  'text',
  'node',
  'allText',
  'html',
  'outerHtml',
  'num',
  'string',
  'name',
  'local-name',
  'namespace',
  'prefix',
  'qualified',
};

List<_Token> _tokenize(String input) {
  final tokens = <_Token>[];
  var i = 0;
  bool operandExpected() {
    if (tokens.isEmpty) return true;
    final last = tokens.last;
    return last.type == _T.op ||
        last.type == _T.lparen ||
        last.type == _T.comma;
  }

  while (i < input.length) {
    final c = input[i];
    if (c.trim().isEmpty) {
      i++;
      continue;
    }
    if (c == '"' || c == "'") {
      final end = input.indexOf(c, i + 1);
      if (end < 0) throw FormatException('Unclosed string in: $input');
      tokens.add(_Token(_T.string, input.substring(i + 1, end)));
      i = end + 1;
      continue;
    }
    if (c == '(') {
      tokens.add(const _Token(_T.lparen, '('));
      i++;
      continue;
    }
    if (c == ')') {
      tokens.add(const _Token(_T.rparen, ')'));
      i++;
      continue;
    }
    if (c == ',') {
      tokens.add(const _Token(_T.comma, ','));
      i++;
      continue;
    }
    final two = i + 1 < input.length ? input.substring(i, i + 2) : '';
    if (const {'!=', '<=', '>=', '^=', r'$=', '*=', '~=', '!~'}.contains(two) &&
        !(two == '*=' && operandExpected())) {
      tokens.add(_Token(_T.op, two));
      i += 2;
      continue;
    }
    if ('=<>+|'.contains(c)) {
      tokens.add(_Token(_T.op, c));
      i++;
      continue;
    }
    if (c == '-' && !operandExpected()) {
      tokens.add(const _Token(_T.op, '-'));
      i++;
      continue;
    }
    if (c == '*' && !operandExpected()) {
      tokens.add(const _Token(_T.op, '*'));
      i++;
      continue;
    }
    if (RegExp(r'[0-9.]').hasMatch(c) &&
        (c != '.' ||
            (i + 1 < input.length &&
                RegExp(r'[0-9]').hasMatch(input[i + 1])))) {
      final match = RegExp(r'\d*\.?\d+').matchAsPrefix(input, i)!;
      tokens.add(_Token(_T.number, match.group(0)!));
      i = match.end;
      continue;
    }
    if (c == '-' && operandExpected()) {
      // Unary minus.
      tokens.add(const _Token(_T.op, 'neg'));
      i++;
      continue;
    }
    // A name: an operator word, a function name, or the start of a path.
    final nameMatch = RegExp(r'[A-Za-z_][\w.-]*').matchAsPrefix(input, i);
    if (nameMatch != null) {
      final name = nameMatch.group(0)!;
      var after = nameMatch.end;
      while (after < input.length && input[after].trim().isEmpty) {
        after++;
      }
      if (_wordOperators.contains(name) && !operandExpected()) {
        tokens.add(_Token(_T.op, name));
        i = nameMatch.end;
        continue;
      }
      if (_functions.contains(name) &&
          after < input.length &&
          input[after] == '(') {
        tokens.add(_Token(_T.name, name));
        i = after;
        continue;
      }
    }
    if (nameMatch != null) {
      var after = nameMatch.end;
      while (after < input.length && input[after].trim().isEmpty) {
        after++;
      }
      final name = nameMatch.group(0)!;
      if (after < input.length &&
          input[after] == '(' &&
          !_nodeTests.contains(name)) {
        throw UnsupportedError('Unsupported function: $name()');
      }
    }
    // A location path: up to the next operator, comma or closing bracket at
    // depth zero.
    final end = _pathEnd(input, i);
    if (end == i) {
      throw FormatException('Unexpected ${input[i]} in: $input');
    }
    tokens.add(_Token(_T.path, input.substring(i, end).trim()));
    i = end;
  }
  tokens.add(const _Token(_T.end, ''));
  return tokens;
}

int _pathEnd(String input, int start) {
  var depth = 0;
  String? quote;
  var i = start;
  while (i < input.length) {
    final c = input[i];
    if (quote != null) {
      if (c == quote) quote = null;
      i++;
      continue;
    }
    if (c == '"' || c == "'") {
      quote = c;
    } else if (c == '[' || c == '(') {
      depth++;
    } else if (c == ']') {
      depth--;
    } else if (c == ')') {
      if (depth == 0) return i;
      depth--;
    } else if (depth == 0) {
      if (c.trim().isEmpty || ',=<>!|+^~\$'.contains(c)) return i;
      if (c == '*' && i + 1 < input.length && input[i + 1] == '=') return i;
      if (c == '-' && i > start && input[i - 1] == ')') return i;
    }
    i++;
  }
  return i;
}

// ── parser ──────────────────────────────────────────────────────────────

abstract class _Node {
  XValue eval(XContext context);
}

class _Literal extends _Node {
  _Literal(this.value);
  final XValue value;
  @override
  XValue eval(XContext context) => value;
}

class _Path extends _Node {
  _Path(this.path);
  final String path;
  @override
  XValue eval(XContext context) => evaluatePath(path, context.node);
}

class _Negate extends _Node {
  _Negate(this.operand);
  final _Node operand;
  @override
  XValue eval(XContext context) => XNumber(-operand.eval(context).asNumber);
}

class _Binary extends _Node {
  _Binary(this.op, this.left, this.right);
  final String op;
  final _Node left;
  final _Node right;

  @override
  XValue eval(XContext context) {
    if (op == 'or') {
      return XBool(left.eval(context).asBool || right.eval(context).asBool);
    }
    if (op == 'and') {
      return XBool(left.eval(context).asBool && right.eval(context).asBool);
    }
    final a = left.eval(context);
    final b = right.eval(context);
    switch (op) {
      case '=':
        return XBool(_equals(a, b));
      case '!=':
        return XBool(!_equals(a, b));
      case '<':
        return XBool(_compare(a, b) < 0);
      case '>':
        return XBool(_compare(a, b) > 0);
      case '<=':
        return XBool(_compare(a, b) <= 0);
      case '>=':
        return XBool(_compare(a, b) >= 0);
      case '^=':
        return XBool(a.asString.startsWith(b.asString));
      case r'$=':
        return XBool(a.asString.endsWith(b.asString));
      case '*=':
        return XBool(a.asString.contains(b.asString));
      case '~=':
        return XBool(_wholeMatch(a.asString, b.asString));
      case '!~':
        return XBool(!_wholeMatch(a.asString, b.asString));
      case '+':
        return XNumber(a.asNumber + b.asNumber);
      case '-':
        return XNumber(a.asNumber - b.asNumber);
      case '*':
        return XNumber(a.asNumber * b.asNumber);
      case 'div':
        return XNumber(a.asNumber / b.asNumber);
      case 'mod':
        return XNumber(a.asNumber.remainder(b.asNumber));
      case '|':
        if (a is XNodes && b is XNodes) {
          return XNodes([
            ...a.nodes,
            ...b.nodes.where((n) => !a.nodes.contains(n)),
          ]);
        }
        return XList([..._strings(a), ..._strings(b)]);
    }
    throw UnsupportedError('Unsupported operator: $op');
  }
}

List<String> _strings(XValue v) => switch (v) {
      XList(:final values) => values,
      XNodes(:final nodes) => nodes.map(ownText).toList(),
      _ => [v.asString],
    };

/// JsoupXpath `=`: the same type compares values, different types compare
/// their strings.
bool _equals(XValue a, XValue b) {
  if (a is XNumber && b is XNumber) return a.value == b.value;
  if (a is XBool && b is XBool) return a.value == b.value;
  if (a is XNumber || b is XNumber) {
    final x = a.asNumber;
    final y = b.asNumber;
    if (!x.isNaN && !y.isNaN) return x == y;
  }
  return a.asString == b.asString;
}

/// JsoupXpath `compareTo`: numbers as numbers, otherwise as strings.
int _compare(XValue a, XValue b) {
  final x = a.asNumber;
  final y = b.asNumber;
  if (!x.isNaN && !y.isNaN) return x.compareTo(y);
  return a.asString.compareTo(b.asString);
}

/// Java `String.matches`: the whole string matches the pattern.
bool _wholeMatch(String value, String pattern) =>
    RegExp('^(?:$pattern)\$').hasMatch(value);

class _Call extends _Node {
  _Call(this.name, this.args);
  final String name;
  final List<_Node> args;

  XValue _arg(XContext c, int i) =>
      i < args.length ? args[i].eval(c) : const XString('');

  @override
  XValue eval(XContext c) {
    switch (name) {
      case 'position':
        return XNumber(c.position.toDouble());
      case 'last':
        return XNumber(c.size.toDouble());
      case 'first':
        return const XNumber(1);
      case 'not':
        return XBool(!_arg(c, 0).asBool);
      case 'count':
        final v = _arg(c, 0);
        return XNumber(switch (v) {
          XNodes(:final nodes) => nodes.length.toDouble(),
          XList(:final values) => values.length.toDouble(),
          _ => 0,
        });
      case 'contains':
        return XBool(_arg(c, 0).asString.contains(_arg(c, 1).asString));
      case 'starts-with':
        return XBool(_arg(c, 0).asString.startsWith(_arg(c, 1).asString));
      case 'ends-with':
        return XBool(_arg(c, 0).asString.endsWith(_arg(c, 1).asString));
      case 'string-length':
        return XNumber(
          args.isEmpty ? 0 : _arg(c, 0).asString.length.toDouble(),
        );
      case 'concat':
        return XString([for (final a in args) a.eval(c).asString].join());
      case 'substring':
        // JsoupXpath SubString: start is 1-based, the third argument is a
        // length.
        final target = _arg(c, 0).asString;
        final start = (_arg(c, 1).asNumber.toInt() - 1).clamp(
          0,
          target.length,
        );
        if (args.length > 2) {
          final end = (start + _arg(c, 2).asNumber.toInt()).clamp(
            start,
            target.length,
          );
          return XString(target.substring(start, end));
        }
        return XString(target.substring(start));
      case 'substring-ex':
        // JsoupXpath SubStringEx: Java's substring(start, end), 0-based,
        // negative counts from the end (commons-lang StringUtils).
        final target = _arg(c, 0).asString;
        int at(int i) => (i < 0 ? target.length + i : i).clamp(
              0,
              target.length,
            );
        final start = at(_arg(c, 1).asNumber.toInt());
        if (args.length > 2) {
          final end = at(_arg(c, 2).asNumber.toInt());
          return XString(end <= start ? '' : target.substring(start, end));
        }
        return XString(target.substring(start));
      case 'substring-after':
        final s = _arg(c, 0).asString;
        final sep = _arg(c, 1).asString;
        final i = s.indexOf(sep);
        return XString(i < 0 ? '' : s.substring(i + sep.length));
      case 'substring-after-last':
        final s = _arg(c, 0).asString;
        final sep = _arg(c, 1).asString;
        final i = s.lastIndexOf(sep);
        return XString(i < 0 || sep.isEmpty ? '' : s.substring(i + sep.length));
      case 'substring-before':
        final s = _arg(c, 0).asString;
        final sep = _arg(c, 1).asString;
        final i = s.indexOf(sep);
        return XString(i < 0 ? '' : s.substring(0, i));
      case 'substring-before-last':
        final s = _arg(c, 0).asString;
        final sep = _arg(c, 1).asString;
        final i = s.lastIndexOf(sep);
        return XString(i < 0 || sep.isEmpty ? s : s.substring(0, i));
      case 'sum':
        var total = 0.0;
        for (final a in args) {
          final v = a.eval(c);
          final parts = switch (v) {
            XNodes(:final nodes) => nodes.map(ownText),
            XList(:final values) => values,
            _ => [v.asString],
          };
          for (final p in parts) {
            final n = _firstNumber(p);
            if (n == null) return const XString('');
            total += n;
          }
        }
        return XNumber(total);
    }
    throw UnsupportedError('Unsupported function: $name()');
  }
}

/// The first number in [text] (JsoupXpath `num()`, `Constants.NUM_PATTERN`).
double? _firstNumber(String text) {
  final match = RegExp(r'[+-]?(\d+(\.\d+)?|\.\d+)').firstMatch(text);
  return match == null ? null : double.tryParse(match.group(0)!);
}

/// `num()` of [text] as a string, an integer when it is one.
String? numberIn(String text) {
  final n = _firstNumber(text);
  if (n == null) return null;
  return n == n.truncateToDouble() ? n.toInt().toString() : n.toString();
}

class _Parser {
  _Parser(this.tokens, this.source);
  final List<_Token> tokens;
  final String source;
  var _i = 0;

  _Token get _peek => tokens[_i];
  _Token _next() => tokens[_i++];

  bool _isOp(String op) => _peek.type == _T.op && _peek.text == op;

  void expectEnd() {
    if (_peek.type != _T.end) {
      throw FormatException('Unexpected ${_peek.text} in: $source');
    }
  }

  _Node parseExpr() => _or();

  _Node _or() {
    var left = _and();
    while (_isOp('or')) {
      _next();
      left = _Binary('or', left, _and());
    }
    return left;
  }

  _Node _and() {
    var left = _equality();
    while (_isOp('and')) {
      _next();
      left = _Binary('and', left, _equality());
    }
    return left;
  }

  _Node _equality() {
    var left = _relational();
    while (_isOp('=') || _isOp('!=')) {
      final op = _next().text;
      left = _Binary(op, left, _relational());
    }
    return left;
  }

  static const _relationalOps = {
    '<',
    '>',
    '<=',
    '>=',
    '^=',
    r'$=',
    '*=',
    '~=',
    '!~',
  };

  _Node _relational() {
    var left = _additive();
    while (_peek.type == _T.op && _relationalOps.contains(_peek.text)) {
      final op = _next().text;
      left = _Binary(op, left, _additive());
    }
    return left;
  }

  _Node _additive() {
    var left = _multiplicative();
    while (_isOp('+') || _isOp('-')) {
      final op = _next().text;
      left = _Binary(op, left, _multiplicative());
    }
    return left;
  }

  _Node _multiplicative() {
    var left = _unary();
    while (_isOp('*') || _isOp('div') || _isOp('mod')) {
      final op = _next().text;
      left = _Binary(op, left, _unary());
    }
    return left;
  }

  _Node _unary() {
    if (_isOp('neg')) {
      _next();
      return _Negate(_unary());
    }
    return _union();
  }

  _Node _union() {
    var left = _primary();
    while (_isOp('|')) {
      _next();
      left = _Binary('|', left, _primary());
    }
    return left;
  }

  _Node _primary() {
    final token = _next();
    switch (token.type) {
      case _T.number:
        return _Literal(XNumber(double.parse(token.text)));
      case _T.string:
        return _Literal(XString(token.text));
      case _T.path:
        return _Path(token.text);
      case _T.lparen:
        final inner = parseExpr();
        if (_next().type != _T.rparen) {
          throw FormatException('Missing ) in: $source');
        }
        return inner;
      case _T.name:
        if (_next().type != _T.lparen) {
          throw FormatException('Missing ( after ${token.text} in: $source');
        }
        final args = <_Node>[];
        if (_peek.type != _T.rparen) {
          args.add(parseExpr());
          while (_peek.type == _T.comma) {
            _next();
            args.add(parseExpr());
          }
        }
        if (_next().type != _T.rparen) {
          throw FormatException('Missing ) in: $source');
        }
        return _Call(token.text, args);
      default:
        throw FormatException('Unexpected ${token.text} in: $source');
    }
  }
}

/// A location path inside an expression, from [node]: `a`, `@href`,
/// `text()`, `.`, `..`, `following-sibling::li`, `./a/@href`. Strings when
/// it ends in an attribute or a text function, nodes otherwise.
XValue evaluatePath(String path, XPathNode node) {
  var relative = path;
  if (relative.startsWith('./')) relative = relative.substring(1);
  final query = relative.startsWith('/') ? relative : '/$relative';
  final result = XPath(node).query(query);
  final trimmed = relative.trim();
  // JsoupXpath: `text()` is text elements, read as their own text joined.
  if (RegExp(r'(?:^|/)text\(\)$').hasMatch(trimmed)) {
    return XString(result.attrs.whereType<String>().join());
  }
  final endsInValue = RegExp(r'(?:^|/)@[^/]*$|\)\s*$').hasMatch(trimmed);
  if (endsInValue) {
    return XList(result.attrs.whereType<String>().toList());
  }
  return XNodes(result.nodes);
}
