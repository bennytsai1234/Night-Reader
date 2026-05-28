import 'package:html/dom.dart';

final Map<String, List<_SelectorSegment>> _selectorSegmentsCache = {};
final Map<String, _ParsedCompoundSelector> _compoundSelectorCache = {};

List<Element> querySelectorAllCompat(Element root, String selector) {
  final normalizedSelector = normalizeCssSelectorCompat(selector);
  if (_needsCompatSelector(normalizedSelector)) {
    return _querySelectorAllUnsupportedCompat(root, normalizedSelector);
  }
  try {
    final matches = root.querySelectorAll(normalizedSelector);
    if (_shouldIncludeRootMatch(root, normalizedSelector) &&
        !matches.contains(root)) {
      return [root, ...matches];
    }
    return matches;
  } on UnimplementedError {
    return _querySelectorAllUnsupportedCompat(root, normalizedSelector);
  } catch (_) {
    return _querySelectorAllUnsupportedCompat(root, normalizedSelector);
  }
}

bool matchesSelectorWithinParentCompat(Element temp, String selector) {
  final trimmed = selector.trim();
  if (trimmed.isEmpty || trimmed == '*') {
    final parent = temp.parent;
    if (parent == null) return false;
    try {
      return querySelectorAllCompat(parent, trimmed).contains(temp);
    } catch (_) {
      return false;
    }
  }
  try {
    return _querySelectorAllFromContainer(
      temp.parentNode,
      trimmed,
    ).contains(temp);
  } catch (_) {
    return false;
  }
}

List<Element> _querySelectorAllUnsupportedCompat(
  Element root,
  String selector,
) {
  if (!_needsCompatSelector(selector)) {
    return [];
  }

  final matches = <Element>{};
  for (final group in _splitSelectorList(selector)) {
    final trimmed = group.trim();
    if (trimmed.isEmpty) continue;
    for (final element in _querySelectorGroupCompat(root, trimmed)) {
      matches.add(element);
    }
  }
  final ordered = <Element>[];
  if (_shouldIncludeRootMatch(root, selector) && matches.contains(root)) {
    ordered.add(root);
  }
  ordered.addAll(root.querySelectorAll('*').where(matches.contains));
  return ordered;
}

bool _shouldIncludeRootMatch(Element root, String selector) {
  return _matchesSelectorAgainstElement(root, selector);
}

bool _needsCompatSelector(String selector) {
  return selector.contains(':contains(') ||
      selector.contains(':containsOwn(') ||
      selector.contains(':has(') ||
      _hasRegexAttributeSelector(selector) ||
      _hasExactAttributeSelector(selector) ||
      selector.contains(':eq(') ||
      selector.contains(':nth-child(') ||
      selector.contains(':nth-last-child(') ||
      selector.contains(':nth-of-type(') ||
      selector.contains(':nth-last-of-type(') ||
      selector.contains(':first-child') ||
      selector.contains(':last-child') ||
      selector.contains(':first-of-type') ||
      selector.contains(':last-of-type');
}

List<Element> _querySelectorGroupCompat(Element root, String selector) {
  final segments = _selectorSegmentsFor(selector);
  if (segments.isEmpty) return [];

  final tail = _parsedCompoundSelectorFor(segments.last.compound);
  final baseSelector = normalizeCssSelectorCompat(tail.baseSelector);

  List<Element> candidates;
  if (baseSelector.isEmpty || baseSelector == '*') {
    candidates = root.querySelectorAll('*');
  } else {
    try {
      candidates = root.querySelectorAll(baseSelector);
      if (candidates.isEmpty && _hasExactAttributeSelector(baseSelector)) {
        candidates = _fallbackCandidatesForBaseSelector(root, baseSelector);
      }
    } catch (_) {
      candidates = _fallbackCandidatesForBaseSelector(root, baseSelector);
    }
  }

  return candidates
      .where((element) => _matchesSelectorAgainstElement(element, selector))
      .toList();
}

List<Element> _fallbackCandidatesForBaseSelector(
  Element root,
  String baseSelector,
) {
  final candidates = <Element>[];
  if (_matchesBaseSelector(root, baseSelector)) {
    candidates.add(root);
  }
  candidates.addAll(
    root
        .querySelectorAll('*')
        .where((element) => _matchesBaseSelector(element, baseSelector)),
  );
  return candidates;
}

bool _matchesSelectorAgainstElement(Element element, String selector) {
  final segments = _selectorSegmentsFor(selector);
  if (segments.isEmpty) return false;
  return _matchesSelectorPathFrom(element, segments, segments.length - 1);
}

bool _matchesSelectorPathFrom(
  Element element,
  List<_SelectorSegment> segments,
  int index,
) {
  if (!_matchesCompoundSelector(element, segments[index].compound)) {
    return false;
  }
  if (index == 0) return true;

  final combinator = segments[index].combinator ?? ' ';
  for (final previous in _relatedElementsForCombinator(element, combinator)) {
    if (_matchesSelectorPathFrom(previous, segments, index - 1)) {
      return true;
    }
  }
  return false;
}

Iterable<Element> _relatedElementsForCombinator(
  Element element,
  String combinator,
) sync* {
  switch (combinator) {
    case '>':
      final parent = element.parent;
      if (parent != null) yield parent;
      return;
    case '+':
      final sibling = element.previousElementSibling;
      if (sibling != null) yield sibling;
      return;
    case '~':
      var sibling = element.previousElementSibling;
      while (sibling != null) {
        yield sibling;
        sibling = sibling.previousElementSibling;
      }
      return;
    case ' ':
    default:
      var parent = element.parent;
      while (parent != null) {
        yield parent;
        parent = parent.parent;
      }
      return;
  }
}

bool _matchesCompoundSelector(Element element, String compound) {
  final parsed = _parsedCompoundSelectorFor(compound);
  if (!_matchesBaseSelector(element, parsed.baseSelector)) {
    return false;
  }
  for (final attributeRegex in parsed.attributeRegexes) {
    final value = element.attributes[attributeRegex.name] ?? '';
    if (!attributeRegex.pattern.hasMatch(value)) {
      return false;
    }
  }

  final text = element.text;
  final ownText =
      element.nodes
          .where((node) => node.nodeType == Node.TEXT_NODE)
          .map((node) => node.text ?? '')
          .join();
  if (!parsed.containsValues.every(text.contains)) {
    return false;
  }
  if (!parsed.containsOwnValues.every(ownText.contains)) {
    return false;
  }
  for (final hasSelector in parsed.hasSelectors) {
    if (hasSelector.trim().isEmpty) return false;
    if (querySelectorAllCompat(element, hasSelector).isEmpty) {
      return false;
    }
  }
  for (final notSelector in parsed.notSelectors) {
    final groups = _splitSelectorList(notSelector);
    if (groups.any(
      (group) =>
          group.trim().isNotEmpty &&
          _matchesSelectorAgainstElement(element, group.trim()),
    )) {
      return false;
    }
  }
  for (final pseudo in parsed.structuralPseudos) {
    if (!_matchesStructuralPseudo(element, pseudo)) {
      return false;
    }
  }
  return true;
}

bool _matchesBaseSelector(Element element, String selector) {
  final trimmed = selector.trim();
  if (trimmed.isEmpty || trimmed == '*') {
    return true;
  }
  final directMatch = _matchesSimpleBaseSelectorDirectly(element, trimmed);
  if (directMatch != null) {
    return directMatch;
  }
  final parentNode = element.parentNode;
  if (parentNode == null) {
    return false;
  }
  try {
    return _querySelectorAllFromContainer(
      parentNode,
      trimmed,
    ).contains(element);
  } catch (_) {
    return false;
  }
}

bool? _matchesSimpleBaseSelectorDirectly(Element element, String selector) {
  final extracted = _extractExactAttributeSelectors(selector);
  final normalizedSelector = extracted.baseSelector;

  if (normalizedSelector.contains(' ') ||
      normalizedSelector.contains('>') ||
      normalizedSelector.contains('+') ||
      normalizedSelector.contains('~') ||
      normalizedSelector.contains(':')) {
    return null;
  }

  if (_hasUnsupportedAttributeSyntax(normalizedSelector)) {
    return null;
  }

  final match = RegExp(
    r'^([a-zA-Z][\w-]*)?(#[\w-]+)?((?:\.[\w-]+)*)$',
  ).firstMatch(normalizedSelector);
  if (match == null) {
    return null;
  }

  final tag = match.group(1);
  final idToken = match.group(2);
  final classToken = match.group(3) ?? '';

  if (tag != null && element.localName != tag.toLowerCase()) {
    return false;
  }
  if (idToken != null && element.id != idToken.substring(1)) {
    return false;
  }
  if (classToken.isNotEmpty) {
    final classes = classToken
        .split('.')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    for (final className in classes) {
      if (!element.classes.contains(className)) {
        return false;
      }
    }
  }
  for (final attribute in extracted.attributeSelectors) {
    if ((element.attributes[attribute.name] ?? '') != attribute.value) {
      return false;
    }
  }
  return true;
}

List<Element> _querySelectorAllFromContainer(Node? container, String selector) {
  if (container is Element) {
    return querySelectorAllCompat(container, selector);
  }
  if (container is Document) {
    final normalizedSelector = normalizeCssSelectorCompat(selector);
    try {
      return container.querySelectorAll(normalizedSelector);
    } on UnimplementedError {
      return _querySelectorAllUnsupportedCompat(
        container.documentElement!,
        normalizedSelector,
      );
    } catch (_) {
      if (_needsCompatSelector(normalizedSelector)) {
        return _querySelectorAllUnsupportedCompat(
          container.documentElement!,
          normalizedSelector,
        );
      }
      return [];
    }
  }
  return [];
}

List<String> _splitSelectorList(String selector) {
  return _splitSelectorAtTopLevel(selector, ',');
}

List<_SelectorSegment> _selectorSegmentsFor(String selector) {
  return _selectorSegmentsCache.putIfAbsent(
    selector,
    () => List.unmodifiable(_parseSelectorSegments(selector)),
  );
}

_ParsedCompoundSelector _parsedCompoundSelectorFor(String compound) {
  return _compoundSelectorCache.putIfAbsent(
    compound,
    () => _parseCompoundSelector(compound),
  );
}

List<_SelectorSegment> _parseSelectorSegments(String selector) {
  final segments = <_SelectorSegment>[];
  final current = StringBuffer();
  String? combinator;
  var parenDepth = 0;
  var bracketDepth = 0;
  String? quote;

  void flushCurrent() {
    final compound = current.toString().trim();
    if (compound.isEmpty) return;
    segments.add(_SelectorSegment(compound: compound, combinator: combinator));
    current.clear();
    combinator = null;
  }

  for (var i = 0; i < selector.length; i++) {
    final char = selector[i];
    if (quote != null) {
      current.write(char);
      if (char == quote && !_isEscaped(selector, i)) {
        quote = null;
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      current.write(char);
      continue;
    }
    if (char == '[') {
      bracketDepth++;
      current.write(char);
      continue;
    }
    if (char == ']') {
      if (bracketDepth > 0) bracketDepth--;
      current.write(char);
      continue;
    }
    if (char == '(') {
      parenDepth++;
      current.write(char);
      continue;
    }
    if (char == ')') {
      if (parenDepth > 0) parenDepth--;
      current.write(char);
      continue;
    }
    if (parenDepth == 0 && bracketDepth == 0) {
      if (char == '>' || char == '+' || char == '~') {
        flushCurrent();
        combinator = char;
        continue;
      }
      if (_isWhitespace(char)) {
        final nextNonWhitespace = _findNextNonWhitespace(selector, i + 1);
        if (current.isNotEmpty &&
            nextNonWhitespace != null &&
            !'>+~'.contains(nextNonWhitespace)) {
          flushCurrent();
          combinator = ' ';
        }
        continue;
      }
    }
    current.write(char);
  }

  flushCurrent();
  return segments;
}

_ParsedCompoundSelector _parseCompoundSelector(String compound) {
  final base = StringBuffer();
  final containsValues = <String>[];
  final containsOwnValues = <String>[];
  final hasSelectors = <String>[];
  final notSelectors = <String>[];
  final structuralPseudos = <_StructuralPseudo>[];

  for (var i = 0; i < compound.length; i++) {
    final pseudo =
        _matchPseudo(compound, i, ':containsOwn(') ??
        _matchPseudo(compound, i, ':contains(') ??
        _matchPseudo(compound, i, ':has(') ??
        _matchPseudo(compound, i, ':not(') ??
        _matchPseudo(compound, i, ':eq(') ??
        _matchPseudo(compound, i, ':nth-last-of-type(') ??
        _matchPseudo(compound, i, ':nth-of-type(') ??
        _matchPseudo(compound, i, ':nth-last-child(') ??
        _matchPseudo(compound, i, ':nth-child(');
    if (pseudo == null) {
      final simplePseudo =
          _matchSimplePseudo(compound, i, ':first-child') ??
          _matchSimplePseudo(compound, i, ':last-child') ??
          _matchSimplePseudo(compound, i, ':first-of-type') ??
          _matchSimplePseudo(compound, i, ':last-of-type');
      if (simplePseudo != null) {
        structuralPseudos.add(_StructuralPseudo(simplePseudo.name));
        i = simplePseudo.endIndex;
        continue;
      }
      base.write(compound[i]);
      continue;
    }

    if (pseudo.name == ':contains') {
      final value = _normalizeContainsNeedle(pseudo.argument);
      if (value.isNotEmpty) containsValues.add(value);
    } else if (pseudo.name == ':containsOwn') {
      final value = _normalizeContainsNeedle(pseudo.argument);
      if (value.isNotEmpty) containsOwnValues.add(value);
    } else if (pseudo.name == ':has') {
      if (pseudo.argument.trim().isNotEmpty) {
        hasSelectors.add(pseudo.argument.trim());
      }
    } else if (pseudo.name == ':not') {
      if (pseudo.argument.trim().isNotEmpty) {
        notSelectors.add(pseudo.argument.trim());
      }
    } else if (pseudo.name == ':eq') {
      structuralPseudos.add(_StructuralPseudo.eq(pseudo.argument.trim()));
    } else if (pseudo.name == ':nth-child') {
      structuralPseudos.add(_StructuralPseudo.nthChild(pseudo.argument.trim()));
    } else if (pseudo.name == ':nth-last-child') {
      structuralPseudos.add(
        _StructuralPseudo.nthLastChild(pseudo.argument.trim()),
      );
    } else if (pseudo.name == ':nth-of-type') {
      structuralPseudos.add(
        _StructuralPseudo.nthOfType(pseudo.argument.trim()),
      );
    } else if (pseudo.name == ':nth-last-of-type') {
      structuralPseudos.add(
        _StructuralPseudo.nthLastOfType(pseudo.argument.trim()),
      );
    }
    i = pseudo.endIndex;
  }

  final extracted = _extractRegexAttributeSelectors(base.toString().trim());

  return _ParsedCompoundSelector(
    baseSelector: extracted.baseSelector,
    attributeRegexes: extracted.attributeRegexes,
    containsValues: containsValues,
    containsOwnValues: containsOwnValues,
    hasSelectors: hasSelectors,
    notSelectors: notSelectors,
    structuralPseudos: structuralPseudos,
  );
}

_SimplePseudoMatch? _matchSimplePseudo(String input, int index, String name) {
  if (!input.startsWith(name, index)) return null;
  return _SimplePseudoMatch(name: name, endIndex: index + name.length - 1);
}

_PseudoMatch? _matchPseudo(String input, int index, String prefix) {
  if (!input.startsWith(prefix, index)) return null;
  final openParenIndex = index + prefix.length - 1;
  final closeParenIndex = _findMatchingParen(input, openParenIndex);
  if (closeParenIndex == -1) return null;
  return _PseudoMatch(
    name: prefix.substring(0, prefix.length - 1),
    argument: input.substring(openParenIndex + 1, closeParenIndex),
    endIndex: closeParenIndex,
  );
}

int _findMatchingParen(String input, int openParenIndex) {
  var depth = 1;
  String? quote;
  for (var i = openParenIndex + 1; i < input.length; i++) {
    final char = input[i];
    if (quote != null) {
      if (char == quote && !_isEscaped(input, i)) {
        quote = null;
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char == '(') {
      depth++;
    } else if (char == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

List<String> _splitSelectorAtTopLevel(String input, String delimiter) {
  final parts = <String>[];
  final current = StringBuffer();
  var parenDepth = 0;
  var bracketDepth = 0;
  String? quote;

  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    if (quote != null) {
      current.write(char);
      if (char == quote && !_isEscaped(input, i)) {
        quote = null;
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      current.write(char);
      continue;
    }
    if (char == '[') {
      bracketDepth++;
      current.write(char);
      continue;
    }
    if (char == ']') {
      if (bracketDepth > 0) bracketDepth--;
      current.write(char);
      continue;
    }
    if (char == '(') {
      parenDepth++;
      current.write(char);
      continue;
    }
    if (char == ')') {
      if (parenDepth > 0) parenDepth--;
      current.write(char);
      continue;
    }
    if (parenDepth == 0 &&
        bracketDepth == 0 &&
        input.startsWith(delimiter, i)) {
      parts.add(current.toString());
      current.clear();
      i += delimiter.length - 1;
      continue;
    }
    current.write(char);
  }

  parts.add(current.toString());
  return parts;
}

String? _findNextNonWhitespace(String input, int start) {
  for (var i = start; i < input.length; i++) {
    if (!_isWhitespace(input[i])) return input[i];
  }
  return null;
}

bool _isWhitespace(String char) => char.trim().isEmpty;

bool _isEscaped(String input, int index) {
  var backslashes = 0;
  for (var i = index - 1; i >= 0 && input[i] == r'\'; i--) {
    backslashes++;
  }
  return backslashes.isOdd;
}

String normalizeCssSelectorCompat(String selector) {
  return selector.replaceAllMapped(
    RegExp(r'\[([^\s~\^\$\*\|=\]]+)\s*=\s*([^\]]+)\]'),
    (match) {
      final attr = match.group(1)!.trim();
      final value = match.group(2)!.trim();
      if (value.startsWith('"') || value.startsWith("'")) {
        return match.group(0)!;
      }
      return '[$attr="$value"]';
    },
  );
}

bool _hasExactAttributeSelector(String selector) {
  return RegExp(
    r'\[\s*([^\s~\^\$\*\|=\]]+)\s*=\s*([^\]]+)\]',
  ).hasMatch(selector);
}

bool _hasRegexAttributeSelector(String selector) {
  return _extractRegexAttributeSelectors(selector).attributeRegexes.isNotEmpty;
}

({String baseSelector, List<_AttributeRegexSelector> attributeRegexes})
_extractRegexAttributeSelectors(String selector) {
  final attributeRegexes = <_AttributeRegexSelector>[];
  final normalized = selector.replaceAllMapped(
    RegExp(r'\[\s*([^\s~=\]]+)\s*~=\s*([^\]]+)\]'),
    (match) {
      final name = match.group(1)!.trim();
      final rawPattern = match.group(2)!.trim();
      if (!_looksLikeRegexAttributeValue(rawPattern)) {
        return match.group(0)!;
      }
      final pattern = _buildRegexAttributePattern(rawPattern);
      if (pattern == null) {
        return match.group(0)!;
      }
      attributeRegexes.add(
        _AttributeRegexSelector(name: name, pattern: pattern),
      );
      return '';
    },
  );
  return (
    baseSelector: normalized.replaceAll(RegExp(r'\s+'), ' ').trim(),
    attributeRegexes: attributeRegexes,
  );
}

({String baseSelector, List<_AttributeExactSelector> attributeSelectors})
_extractExactAttributeSelectors(String selector) {
  final attributeSelectors = <_AttributeExactSelector>[];
  final normalized = selector.replaceAllMapped(
    RegExp(r'\[\s*([^\s~\^\$\*\|=\]]+)\s*=\s*([^\]]+)\]'),
    (match) {
      final name = match.group(1)!.trim();
      final rawValue = match.group(2)!.trim();
      if (rawValue.isEmpty || _looksLikeRegexAttributeValue(rawValue)) {
        return match.group(0)!;
      }
      final value = _unwrapCssAttributeValue(rawValue);
      attributeSelectors.add(_AttributeExactSelector(name: name, value: value));
      return '';
    },
  );
  return (
    baseSelector: normalized.replaceAll(RegExp(r'\s+'), ' ').trim(),
    attributeSelectors: attributeSelectors,
  );
}

bool _hasUnsupportedAttributeSyntax(String selector) {
  return selector.contains('[') || selector.contains(']');
}

bool _looksLikeRegexAttributeValue(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
      (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
    return false;
  }
  return trimmed.startsWith('/') ||
      trimmed.contains(r'\') ||
      trimmed.contains('+') ||
      trimmed.contains('*') ||
      trimmed.contains('?') ||
      trimmed.contains('(') ||
      trimmed.contains('[') ||
      trimmed.contains('{') ||
      trimmed.contains('|') ||
      trimmed.contains('^') ||
      trimmed.contains(r'$');
}

RegExp? _buildRegexAttributePattern(String rawPattern) {
  try {
    return RegExp(rawPattern.trim());
  } catch (_) {
    return null;
  }
}

String _normalizeContainsNeedle(String value) {
  final trimmed = value.trim();
  if (trimmed.length >= 2 &&
      ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
          (trimmed.startsWith("'") && trimmed.endsWith("'")))) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

String _unwrapCssAttributeValue(String value) {
  final trimmed = value.trim();
  if (trimmed.length >= 2 &&
      ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
          (trimmed.startsWith("'") && trimmed.endsWith("'")))) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

class _SelectorSegment {
  final String compound;
  final String? combinator;

  const _SelectorSegment({required this.compound, required this.combinator});
}

class _ParsedCompoundSelector {
  final String baseSelector;
  final List<_AttributeRegexSelector> attributeRegexes;
  final List<String> containsValues;
  final List<String> containsOwnValues;
  final List<String> hasSelectors;
  final List<String> notSelectors;
  final List<_StructuralPseudo> structuralPseudos;

  const _ParsedCompoundSelector({
    required this.baseSelector,
    required this.attributeRegexes,
    required this.containsValues,
    required this.containsOwnValues,
    required this.hasSelectors,
    required this.notSelectors,
    required this.structuralPseudos,
  });
}

class _AttributeRegexSelector {
  final String name;
  final RegExp pattern;

  const _AttributeRegexSelector({required this.name, required this.pattern});
}

class _AttributeExactSelector {
  final String name;
  final String value;

  const _AttributeExactSelector({required this.name, required this.value});
}

class _PseudoMatch {
  final String name;
  final String argument;
  final int endIndex;

  const _PseudoMatch({
    required this.name,
    required this.argument,
    required this.endIndex,
  });
}

class _SimplePseudoMatch {
  final String name;
  final int endIndex;

  const _SimplePseudoMatch({required this.name, required this.endIndex});
}

class _StructuralPseudo {
  final String name;
  final String? argument;

  const _StructuralPseudo(this.name) : argument = null;

  const _StructuralPseudo.eq(this.argument) : name = ':eq';
  const _StructuralPseudo.nthChild(this.argument) : name = ':nth-child';
  const _StructuralPseudo.nthLastChild(this.argument)
    : name = ':nth-last-child';
  const _StructuralPseudo.nthOfType(this.argument) : name = ':nth-of-type';
  const _StructuralPseudo.nthLastOfType(this.argument)
    : name = ':nth-last-of-type';
}

bool _matchesStructuralPseudo(Element element, _StructuralPseudo pseudo) {
  switch (pseudo.name) {
    case ':first-child':
      return _elementIndex(element) == 0;
    case ':last-child':
      return _elementIndexFromEnd(element) == 0;
    case ':first-of-type':
      return _typeIndex(element) == 0;
    case ':last-of-type':
      return _typeIndexFromEnd(element) == 0;
    case ':eq':
      final index = int.tryParse(pseudo.argument ?? '');
      return index != null && _elementIndex(element) == index;
    case ':nth-child':
      return _matchesNthExpression(_elementIndex(element) + 1, pseudo.argument);
    case ':nth-last-child':
      return _matchesNthExpression(
        _elementIndexFromEnd(element) + 1,
        pseudo.argument,
      );
    case ':nth-of-type':
      return _matchesNthExpression(_typeIndex(element) + 1, pseudo.argument);
    case ':nth-last-of-type':
      return _matchesNthExpression(
        _typeIndexFromEnd(element) + 1,
        pseudo.argument,
      );
    default:
      return true;
  }
}

int _elementIndex(Element element) {
  final parent = element.parent;
  if (parent == null) return 0;
  return parent.children.indexOf(element);
}

int _elementIndexFromEnd(Element element) {
  final parent = element.parent;
  if (parent == null) return 0;
  final siblings = parent.children;
  final index = siblings.indexOf(element);
  return index == -1 ? 0 : siblings.length - index - 1;
}

int _typeIndex(Element element) {
  final siblings = _sameTypeSiblings(element);
  return siblings.indexOf(element);
}

int _typeIndexFromEnd(Element element) {
  final siblings = _sameTypeSiblings(element);
  final index = siblings.indexOf(element);
  return index == -1 ? 0 : siblings.length - index - 1;
}

List<Element> _sameTypeSiblings(Element element) {
  final parent = element.parent;
  if (parent == null) return [element];
  final localName = element.localName;
  return parent.children
      .where((child) => child.localName == localName)
      .toList();
}

bool _matchesNthExpression(int index1Based, String? expression) {
  if (expression == null) return false;
  final normalized = expression.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  if (normalized.isEmpty) return false;
  if (normalized == 'odd') return index1Based.isOdd;
  if (normalized == 'even') return index1Based.isEven;

  final direct = int.tryParse(normalized);
  if (direct != null) return index1Based == direct;

  final match = RegExp(r'^([+-]?\d*)n([+-]\d+)?$').firstMatch(normalized);
  if (match == null) return false;

  final aToken = match.group(1) ?? '';
  final bToken = match.group(2);
  final a =
      aToken.isEmpty || aToken == '+'
          ? 1
          : aToken == '-'
          ? -1
          : int.tryParse(aToken);
  final b = bToken == null ? 0 : int.tryParse(bToken);
  if (a == null || b == null) return false;
  if (a == 0) return index1Based == b;

  final delta = index1Based - b;
  if (delta.remainder(a) != 0) return false;
  return delta ~/ a >= 0;
}

class SourceRule {
  bool isCss = false;
  late String elementsRule;

  SourceRule(String ruleStr) {
    if (ruleStr.toUpperCase().startsWith('@CSS:')) {
      isCss = true;
      elementsRule = ruleStr.substring(5).trim();
    } else {
      elementsRule = ruleStr;
    }
  }
}

class ElementsSingle {
  String split = '.';
  String beforeRule = '';
  final List<int> indexDefault = [];
  final List<dynamic> indexes = [];

  List<Element> getElementsSingle(Element temp, String rule) {
    split = '.';
    beforeRule = '';
    indexDefault.clear();
    indexes.clear();
    findIndexSet(rule);

    List<Element> elements;
    if (beforeRule.isEmpty) {
      elements = temp.children;
    } else {
      final rules = beforeRule.split('.');
      if (rules[0] == ':root' || rules[0] == 'root') {
        elements = [temp];
      } else if (rules[0] == 'children') {
        elements = temp.children;
      } else if (rules[0] == 'class' && rules.length > 1) {
        final selector = '.${rules.sublist(1).join('.')}';
        elements = _withSelfIf(
          temp,
          descendants:
              selector.contains(':') || selector.contains('[')
                  ? querySelectorAllCompat(temp, selector)
                  : temp.getElementsByClassName(rules[1]),
          selfMatches:
              selector.contains(':') || selector.contains('[')
                  ? matchesSelectorWithinParentCompat(temp, selector)
                  : temp.classes.contains(rules[1]),
        );
      } else if (rules[0] == 'tag' && rules.length > 1) {
        final selector = rules.sublist(1).join('.');
        elements = _withSelfIf(
          temp,
          descendants:
              selector.contains(':') || selector.contains('[')
                  ? querySelectorAllCompat(temp, selector)
                  : temp.getElementsByTagName(rules[1]),
          selfMatches:
              selector.contains(':') || selector.contains('[')
                  ? matchesSelectorWithinParentCompat(temp, selector)
                  : temp.localName == rules[1],
        );
      } else if (rules[0] == 'id' && rules.length > 1) {
        final el = temp.querySelector('#${rules[1]}');
        elements = temp.id == rules[1] ? [temp] : (el != null ? [el] : []);
      } else if (rules[0] == 'text' && rules.length > 1) {
        final descendants =
            temp.querySelectorAll('*').where((el) {
              return el.nodes.any(
                (n) =>
                    n.nodeType == Node.TEXT_NODE && n.text!.contains(rules[1]),
              );
            }).toList();
        final selfMatches = temp.nodes.any(
          (n) =>
              n.nodeType == Node.TEXT_NODE && (n.text ?? '').contains(rules[1]),
        );
        elements = _withSelfIf(
          temp,
          descendants: descendants,
          selfMatches: selfMatches,
        );
      } else {
        try {
          elements = _withSelfIf(
            temp,
            descendants: querySelectorAllCompat(temp, beforeRule),
            selfMatches: matchesSelectorWithinParentCompat(temp, beforeRule),
          );
        } catch (e) {
          elements = [];
        }
      }
    }

    final len = elements.length;
    if (len == 0) return [];

    final lastIndexes =
        indexDefault.isNotEmpty ? indexDefault.length - 1 : indexes.length - 1;
    final indexSet = <int>{};

    if (indexes.isEmpty) {
      for (var i = lastIndexes; i >= 0; i--) {
        final it = indexDefault[i];
        if (it >= 0 && it < len) {
          indexSet.add(it);
        } else if (it < 0 && len >= -it) {
          indexSet.add(it + len);
        }
      }
    } else {
      for (var i = lastIndexes; i >= 0; i--) {
        final idx = indexes[i];
        if (idx is Triple) {
          var start = idx.first ?? 0;
          if (start < 0) start += len;
          var end = idx.second ?? (len - 1);
          if (end < 0) end += len;

          if ((start < 0 && end < 0) || (start >= len && end >= len)) continue;

          start = start.clamp(0, len - 1);
          end = end.clamp(0, len - 1);

          var step = idx.third;
          if (step == 0) step = 1;
          if (step < 0 && -step < len) step += len;
          if (step <= 0) step = 1;

          if (start <= end) {
            for (var j = start; j <= end; j += step) {
              indexSet.add(j);
            }
          } else {
            for (var j = start; j >= end; j -= step) {
              indexSet.add(j);
            }
          }
        } else if (idx is int) {
          final it = idx;
          if (it >= 0 && it < len) {
            indexSet.add(it);
          } else if (it < 0 && len >= -it) {
            indexSet.add(it + len);
          }
        }
      }
    }

    if (split == '!') {
      final result = <Element>[];
      for (var i = 0; i < len; i++) {
        if (!indexSet.contains(i)) {
          result.add(elements[i]);
        }
      }
      return result;
    } else if (split == '.') {
      final result = <Element>[];
      for (final idx in indexSet) {
        result.add(elements[idx]);
      }
      return result;
    } else {
      return elements;
    }
  }

  List<Element> _withSelfIf(
    Element temp, {
    required Iterable<Element> descendants,
    required bool selfMatches,
  }) {
    final results = <Element>[];
    if (selfMatches) {
      results.add(temp);
    }
    for (final element in descendants) {
      if (!results.contains(element)) {
        results.add(element);
      }
    }
    return results;
  }

  void findIndexSet(String rule) {
    final rus = rule.trim();
    final bracketMatch = RegExp(r'^(.*)\[(!?)([-\d:,\s]+)\]$').firstMatch(rus);
    if (bracketMatch != null) {
      beforeRule = bracketMatch.group(1)!.trim();
      split = bracketMatch.group(2) == '!' ? '!' : '.';
      final segments = bracketMatch.group(3)!.split(',');
      for (final rawSegment in segments) {
        final segment = rawSegment.trim();
        if (segment.isEmpty) {
          continue;
        }
        if (segment.contains(':')) {
          final parts = segment.split(':').map((e) => e.trim()).toList();
          int? parsePart(int index) =>
              index < parts.length && parts[index].isNotEmpty
                  ? int.tryParse(parts[index])
                  : null;
          indexes.add(
            Triple(
              parsePart(0),
              parsePart(1),
              parts.length > 2 ? (parsePart(2) ?? 1) : 1,
            ),
          );
        } else {
          final value = int.tryParse(segment);
          if (value != null) {
            indexes.add(value);
          }
        }
      }
      return;
    }

    var len = rus.length;
    var curMinus = false;
    final curList = <int?>[];
    var l = '';

    var head =
        rus.endsWith(']') && RegExp(r'\[(?:!?[-\d:,\s]+)\]\s*$').hasMatch(rus);

    if (head) {
      len--;
      while (len >= 0) {
        final rl = rus[len];
        if (rl == ' ' || rl == ']') {
          len--;
          continue;
        }

        if (_isDigit(rl)) {
          l = rl + l;
        } else if (rl == '-') {
          curMinus = true;
        } else {
          final curInt = l.isEmpty ? null : int.tryParse(curMinus ? '-$l' : l);
          if (rl == ':') {
            curList.add(curInt);
          } else {
            if (curList.isEmpty) {
              if (curInt == null && rl != '[') break;
              if (curInt != null) indexes.add(curInt);
            } else {
              indexes.add(
                Triple(
                  curInt,
                  curList.last,
                  curList.length == 2 ? (curList.first ?? 1) : 1,
                ),
              );
              curList.clear();
            }

            if (rl == '!') {
              split = '!';
              while (len > 0 && rus[len - 1] == ' ') {
                len--;
              }
            }

            if (rl == '[') {
              beforeRule = rus.substring(0, len);
              return;
            }

            if (rl != ',') break;
          }
          l = '';
          curMinus = false;
          head = false; // reset head if rule is complex
        }
        len--;
      }
    } else {
      while (len > 0) {
        len--;
        final rl = rus[len];
        if (rl == ' ') continue;

        if (_isDigit(rl)) {
          l = rl + l;
        } else if (rl == '-') {
          curMinus = true;
        } else {
          if (rl == '!' || rl == '.' || rl == ':') {
            final val = int.tryParse(curMinus ? '-$l' : l);
            if (val == null) {
              len++;
              break;
            }
            indexDefault.add(val);
            if (rl != ':') {
              split = rl;
              beforeRule = rus.substring(0, len);
              return;
            }
          } else {
            break;
          }
          l = '';
          curMinus = false;
        }
      }
    }
    split = ' ';
    beforeRule = rus;
  }

  bool _isDigit(String s) => RegExp(r'^\d$').hasMatch(s);
}

class Triple {
  final int? first;
  final int? second;
  final int third;
  Triple(this.first, this.second, this.third);
}
