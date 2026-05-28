import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:xpath_selector/xpath_selector.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';
import 'package:night_reader/core/engine/rule_analyzer.dart';

/// AnalyzeByXPath - XPath 解析器
/// (原 Android model/analyzeRule/AnalyzeByXPath.kt) (5KB)
///
/// 使用 Dart `xpath_selector` + `xpath_selector_html_parser` 套件
class AnalyzeByXPath {
  late HtmlXPath _xpath;
  late Element _domRoot;
  Element? _bodyCompatRoot;
  static final RegExp _customFunctionPattern = RegExp(
    r'/(allText|textNodes|ownText|html|outerHtml)\(\)\s*$',
  );

  AnalyzeByXPath(dynamic doc) {
    final htmlLike = _extractHtmlLikeContent(doc);
    if (doc is XPathNode) {
      final node = doc.node;
      if (node is Element) {
        _initFromElement(node);
      } else {
        final prepared = _prepareHtml(doc.toString());
        _initFromHtml(prepared);
      }
    } else if (doc is Element) {
      _initFromElement(doc);
    } else if (htmlLike != null) {
      final prepared = _prepareHtml(htmlLike);
      _initFromHtml(prepared);
    } else if (doc is String) {
      final prepared = _prepareHtml(doc);
      _initFromHtml(prepared);
    } else {
      final prepared = _prepareHtml(doc.toString());
      _initFromHtml(prepared);
    }
  }

  void _initFromHtml(String html) {
    final document = html_parser.parse(html);
    _domRoot = document.documentElement ?? document.body!;
    _bodyCompatRoot = _buildBodyCompatRoot(html);
    _xpath = HtmlXPath.html(html);
  }

  void _initFromElement(Element element) {
    final wrapper = Element.tag('div');
    final fragment = html_parser.parseFragment(element.outerHtml);
    wrapper.nodes.addAll(fragment.nodes);
    _domRoot = wrapper;
    _bodyCompatRoot = wrapper;
    _xpath = HtmlXPath.html(wrapper.outerHtml);
  }

  Element? _buildBodyCompatRoot(String html) {
    final match = RegExp(
      r'<body\b[^>]*>([\s\S]*?)</body>',
      caseSensitive: false,
    ).firstMatch(html);
    final fragmentHtml = match?.group(1)?.trim();
    if (fragmentHtml == null || fragmentHtml.isEmpty) {
      return null;
    }
    final wrapper = Element.tag('div');
    final fragment = html_parser.parseFragment(fragmentHtml);
    wrapper.nodes.addAll(fragment.nodes);
    return wrapper;
  }

  /// (原 Android 的) strToJXDocument，處理表格標籤補全
  String _prepareHtml(String html) {
    var h = html.trim();
    h = h.replaceAllMapped(
      RegExp(r'""(?=\s+[a-zA-Z_:][-a-zA-Z0-9_:.]*=)'),
      (_) => '"',
    );
    if (h.endsWith('</td>')) {
      h = '<tr>$h</tr>';
    }
    if (h.endsWith('</tr>') || h.endsWith('</tbody>')) {
      h = '<table>$h</table>';
    }
    return h;
  }

  String? _extractHtmlLikeContent(dynamic doc) {
    if (doc is! Map) return null;
    for (final key in const <String>['__html', 'outerHtml', 'html']) {
      final candidate = doc[key];
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate;
      }
    }
    return null;
  }

  /// 獲取列表
  List<dynamic> getElements(String xPathRule) {
    if (xPathRule.isEmpty) return [];

    final normalizedRule = _normalizeXPathCompat(xPathRule);
    final ruleAnalyzes = RuleAnalyzer(normalizedRule);
    final rules = ruleAnalyzes.splitRule(['&&', '||', '%%']);

    if (rules.length == 1) {
      return _queryNodesCompat(rules[0].trim());
    } else {
      final results = <List<dynamic>>[];
      for (final rl in rules) {
        final temp = getElements(rl.trim());
        if (temp.isNotEmpty) {
          results.add(temp);
          if (ruleAnalyzes.elementsType == '||') break;
        }
      }

      if (results.isEmpty) return [];

      final result = <dynamic>[];
      if (ruleAnalyzes.elementsType == '%%') {
        final firstListSize = results[0].length;
        for (var i = 0; i < firstListSize; i++) {
          for (final temp in results) {
            if (i < temp.length) {
              result.add(temp[i]);
            }
          }
        }
      } else {
        for (final temp in results) {
          result.addAll(temp);
        }
      }
      return result;
    }
  }

  /// 獲取所有內容列表 (對標 Android AnalyzeByXPath.getStringList)
  List<String> getStringList(String xPathRule) {
    if (xPathRule.isEmpty) return [];

    final normalizedRule = _normalizeXPathCompat(xPathRule);
    final ruleAnalyzes = RuleAnalyzer(normalizedRule);
    final rules = ruleAnalyzes.splitRule(['&&', '||', '%%']);

    if (rules.length == 1) {
      final String rule = rules[0].trim();
      final customMatch = _customFunctionPattern.firstMatch(rule);
      if (customMatch != null) {
        final baseXPath = rule.substring(0, customMatch.start);
        final functionName = customMatch.group(1)!;
        final nodes =
            baseXPath.isEmpty
                ? _queryNodesCompat('//*')
                : _queryNodesCompat(baseXPath);
        return _applyCustomFunction(nodes, functionName);
      }

      final queryResult = _xpath.query(rule);

      // 1. 處理屬性提取 /@attr 或 /attr()
      if (rule.contains('/@')) {
        final attrs = queryResult.attrs.whereType<String>().toList();
        if (attrs.isNotEmpty) {
          return attrs;
        }
        return _queryStringListCompat(rule);
      }

      // 2. 處理文本提取 /text()
      if (rule.endsWith('/text()')) {
        final texts =
            queryResult.nodes
                .map((n) => n.text?.trim() ?? '')
                .where((t) => t.isNotEmpty)
                .toList();
        if (texts.isNotEmpty) {
          return texts;
        }
        return _queryStringListCompat(rule);
      }

      // 3. 預設返回節點的 outerHtml 或 text (對標 Android asString)
      final strings =
          queryResult.nodes
              .map((n) {
                final domNode = n.node;
                if (domNode is Element) {
                  return domNode.outerHtml;
                }
                return n.text?.trim() ?? '';
              })
              .where((t) => t.isNotEmpty)
              .toList();
      if (strings.isNotEmpty) {
        return strings;
      }
      return _queryStringListCompat(rule);
    } else {
      final results = <List<String>>[];
      for (final rl in rules) {
        final temp = getStringList(rl.trim());
        if (temp.isNotEmpty) {
          results.add(temp);
          if (ruleAnalyzes.elementsType == '||') break;
        }
      }

      if (results.isEmpty) return [];

      final result = <String>[];
      if (ruleAnalyzes.elementsType == '%%') {
        final firstListSize = results[0].length;
        for (var i = 0; i < firstListSize; i++) {
          for (final temp in results) {
            if (i < temp.length) {
              result.add(temp[i]);
            }
          }
        }
      } else {
        for (final temp in results) {
          result.addAll(temp);
        }
      }
      return result;
    }
  }

  /// 獲取合併字串
  String? getString(String rule) {
    if (rule.isEmpty) return null;

    final ruleAnalyzes = RuleAnalyzer(rule);
    final rules = ruleAnalyzes.splitRule(['&&', '||']);

    if (rules.length == 1) {
      final list = getStringList(rules[0].trim());
      if (list.isEmpty) return null;
      return list.join('\n');
    } else {
      final textList = <String>[];
      for (final rl in rules) {
        final temp = getString(rl.trim());
        if (temp != null && temp.isNotEmpty) {
          textList.add(temp);
          if (ruleAnalyzes.elementsType == '||') break;
        }
      }
      return textList.isEmpty ? null : textList.join('\n');
    }
  }

  List<String> _applyCustomFunction(List<dynamic> nodes, String functionName) {
    final results = <String>[];
    for (final node in nodes) {
      final element = _extractElement(node);
      if (element == null) {
        continue;
      }
      switch (functionName) {
        case 'allText':
          final text = element.text.trim().replaceAll(RegExp(r'\s+'), ' ');
          if (text.isNotEmpty) {
            results.add(text);
          }
          break;
        case 'textNodes':
          final text = element.nodes
              .where((n) => n.nodeType == Node.TEXT_NODE)
              .map((n) => n.text?.trim() ?? '')
              .where((t) => t.isNotEmpty)
              .join('\n');
          if (text.isNotEmpty) {
            results.add(text);
          }
          break;
        case 'ownText':
          final text = element.nodes
              .where((n) => n.nodeType == Node.TEXT_NODE)
              .map((n) => n.text?.trim() ?? '')
              .where((t) => t.isNotEmpty)
              .join(' ');
          if (text.isNotEmpty) {
            results.add(text);
          }
          break;
        case 'html':
        case 'outerHtml':
          results.add(element.outerHtml);
          break;
      }
    }
    return results;
  }

  List<dynamic> _queryNodesCompat(String rule) {
    final nodes = _xpath.query(rule).nodes;
    if (nodes.isNotEmpty) {
      return nodes;
    }
    final compatQuery = _parseCssCompatQuery(rule);
    if (compatQuery == null ||
        compatQuery.extractor != _XPathCompatExtractor.node) {
      return const <dynamic>[];
    }
    final elements = _queryCompatElements(compatQuery.selector);
    return elements;
  }

  List<String> _queryStringListCompat(String rule) {
    final compatQuery = _parseCssCompatQuery(rule);
    if (compatQuery == null) return const <String>[];
    final elements = _queryCompatElements(compatQuery.selector);
    if (elements.isEmpty) return const <String>[];

    switch (compatQuery.extractor) {
      case _XPathCompatExtractor.node:
      case _XPathCompatExtractor.html:
        return elements.map((element) => element.outerHtml).toList();
      case _XPathCompatExtractor.text:
        return elements
            .map((element) => element.text.trim())
            .where((text) => text.isNotEmpty)
            .toList();
      case _XPathCompatExtractor.attr:
        final attr = compatQuery.attrName;
        if (attr == null || attr.isEmpty) return const <String>[];
        return elements
            .map((element) => element.attributes[attr]?.trim() ?? '')
            .where((value) => value.isNotEmpty)
            .toList();
    }
  }

  Element? _extractElement(dynamic node) {
    if (node is Element) {
      return node;
    }
    if (node is XPathNode) {
      final domNode = node.node;
      if (domNode is Element) {
        return domNode;
      }
    }
    return null;
  }

  List<Element> _queryCompatElements(String selector) {
    final elements = _domRoot.querySelectorAll(selector);
    if (elements.isNotEmpty) {
      return elements;
    }
    final bodyCompatRoot = _bodyCompatRoot;
    if (bodyCompatRoot == null) {
      return const <Element>[];
    }
    return bodyCompatRoot.querySelectorAll(selector);
  }

  _XPathCompatQuery? _parseCssCompatQuery(String rule) {
    final trimmed = rule.trim();
    if (!trimmed.startsWith('/')) {
      return null;
    }

    var path = trimmed;
    var extractor = _XPathCompatExtractor.node;
    String? attrName;
    if (path.endsWith('/text()')) {
      extractor = _XPathCompatExtractor.text;
      path = path.substring(0, path.length - '/text()'.length);
    } else if (path.endsWith('/html()')) {
      extractor = _XPathCompatExtractor.html;
      path = path.substring(0, path.length - '/html()'.length);
    } else if (path.endsWith('/outerHtml()')) {
      extractor = _XPathCompatExtractor.html;
      path = path.substring(0, path.length - '/outerHtml()'.length);
    } else {
      final attrMatch = RegExp(
        r'/@([a-zA-Z_:][-a-zA-Z0-9_:.]*)$',
      ).firstMatch(path);
      if (attrMatch != null) {
        extractor = _XPathCompatExtractor.attr;
        attrName = attrMatch.group(1);
        path = path.substring(0, attrMatch.start);
      }
    }

    final steps = _splitXPathSteps(path);
    if (steps.isEmpty) {
      return null;
    }

    final selector = StringBuffer();
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final css = _convertXPathStepToCss(step.segment);
      if (css == null) {
        return null;
      }
      if (i > 0) {
        selector.write(step.isDescendant ? ' ' : ' > ');
      }
      selector.write(css);
    }
    return _XPathCompatQuery(
      selector: selector.toString(),
      extractor: extractor,
      attrName: attrName,
    );
  }

  List<_XPathCompatStep> _splitXPathSteps(String path) {
    final steps = <_XPathCompatStep>[];
    var index = 0;
    while (index < path.length) {
      var isDescendant = false;
      if (path.startsWith('//', index)) {
        isDescendant = true;
        index += 2;
      } else if (path.startsWith('/', index)) {
        index += 1;
      } else {
        return const <_XPathCompatStep>[];
      }

      final start = index;
      var bracketDepth = 0;
      while (index < path.length) {
        final char = path[index];
        if (char == '[') {
          bracketDepth += 1;
          index += 1;
          continue;
        }
        if (char == ']') {
          bracketDepth -= 1;
          index += 1;
          continue;
        }
        if (bracketDepth == 0 &&
            (path.startsWith('//', index) || path[index] == '/')) {
          break;
        }
        index += 1;
      }

      final segment = path.substring(start, index).trim();
      if (segment.isEmpty) {
        return const <_XPathCompatStep>[];
      }
      steps.add(_XPathCompatStep(segment: segment, isDescendant: isDescendant));
    }
    return steps;
  }

  String? _convertXPathStepToCss(String segment) {
    final match = RegExp(r'^([a-zA-Z*][\w:-]*)(.*)$').firstMatch(segment);
    if (match == null) {
      return null;
    }

    final tag = match.group(1)!;
    final predicatesPart = match.group(2)!;
    final selector = StringBuffer(tag);
    final predicateMatches = RegExp(r'\[(.*?)\]').allMatches(predicatesPart);
    for (final predicateMatch in predicateMatches) {
      final predicate = predicateMatch.group(1)?.trim() ?? '';
      if (predicate.isEmpty) continue;
      final cssPredicate = _convertXPathPredicateToCss(predicate);
      if (cssPredicate == null) {
        return null;
      }
      selector.write(cssPredicate);
    }

    final residual =
        predicatesPart.replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();
    if (residual.isNotEmpty) {
      return null;
    }
    return selector.toString();
  }

  String? _convertXPathPredicateToCss(String predicate) {
    final conjunctionParts =
        predicate
            .split(RegExp(r'\s+and\s+'))
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .toList();
    if (conjunctionParts.length > 1) {
      final selectors = <String>[];
      for (final part in conjunctionParts) {
        final css = _convertXPathPredicateToCss(part);
        if (css == null) {
          return null;
        }
        selectors.add(css);
      }
      return selectors.join();
    }

    final classEqualsMatch = RegExp(
      r'''^@class\s*=\s*("([^"]*)"|'([^']*)')$''',
    ).firstMatch(predicate);
    if (classEqualsMatch != null) {
      final rawValue =
          classEqualsMatch.group(2) ?? classEqualsMatch.group(3) ?? '';
      final classTokens = rawValue
          .split(RegExp(r'\s+'))
          .map((token) => token.trim())
          .where((token) => token.isNotEmpty);
      return classTokens
          .map((token) => '[class~="${_escapeCssValue(token)}"]')
          .join();
    }

    final containsMatch = RegExp(
      r'''^contains\(\s*@([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*,\s*("([^"]*)"|'([^']*)')\s*\)$''',
    ).firstMatch(predicate);
    if (containsMatch != null) {
      final attr = containsMatch.group(1)!;
      final rawValue = containsMatch.group(3) ?? containsMatch.group(4) ?? '';
      if (attr == 'class' && !rawValue.contains(' ')) {
        return '[class~="${_escapeCssValue(rawValue)}"]';
      }
      return '[$attr*="${_escapeCssValue(rawValue)}"]';
    }

    final attrEqualsMatch = RegExp(
      r'''^@([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*("([^"]*)"|'([^']*)')$''',
    ).firstMatch(predicate);
    if (attrEqualsMatch != null) {
      final attr = attrEqualsMatch.group(1)!;
      final rawValue =
          attrEqualsMatch.group(3) ?? attrEqualsMatch.group(4) ?? '';
      return '[$attr="${_escapeCssValue(rawValue)}"]';
    }

    return null;
  }

  String _escapeCssValue(String value) {
    return value.replaceAll('\\', r'\\').replaceAll('"', r'\"');
  }

  String _normalizeXPathCompat(String rule) {
    return rule.replaceAllMapped(
      RegExp("@class\\s*=\\s*(\"([^\"]*)\"|'([^']*)')"),
      (match) {
        final rawValue = match.group(2) ?? match.group(3) ?? '';
        final classNames =
            rawValue
                .split(RegExp(r'\s+'))
                .map((token) => token.trim())
                .where((token) => token.isNotEmpty)
                .toList();
        return classNames
            .map((token) => 'contains(@class, "$token")')
            .join(' and ');
      },
    );
  }
}

class _XPathCompatQuery {
  final String selector;
  final _XPathCompatExtractor extractor;
  final String? attrName;

  const _XPathCompatQuery({
    required this.selector,
    required this.extractor,
    this.attrName,
  });
}

class _XPathCompatStep {
  final String segment;
  final bool isDescendant;

  const _XPathCompatStep({required this.segment, required this.isDescendant});
}

enum _XPathCompatExtractor { node, text, attr, html }
