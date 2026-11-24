# Night Reader patches for `xpath_selector`

## Source

- Package: [`xpath_selector` 3.0.2](https://pub.dev/packages/xpath_selector/versions/3.0.2)
- Archive: `https://pub.dev/api/archives/xpath_selector-3.0.2.tar.gz`
- Archive SHA-256: `6d8295565a34a6e2821a0721592e584c70421e52a0f54955e0c8e41963db7c90`
- Upstream repository: <https://github.com/simonkimi/xpath_selector>
- Vendored version: `3.0.2+nightreader.2`
- License: BSD 3-Clause; the upstream [`LICENSE`](LICENSE) is retained unchanged.
- Vendored files: `lib/`, `LICENSE`, `CHANGELOG.md`, `README.md`; `example/`, the
  IDE module file and the upstream `analysis_options.yaml` are left out.

## Local patch

Predicates and functions follow JsoupXpath 2.5.3, the XPath engine Legado
uses (`cn.wanghaomiao:JsoupXpath`, its `Xpath.g4` grammar and the
`core/function`, `core/node` and `core/axis` classes).

- `lib/src/expression.dart` (new): an expression evaluator for predicates and
  function steps. Operators `or` `and` `=` `!=` `<` `>` `<=` `>=`, JsoupXpath's
  `^=` (starts with), `$=` (ends with), `*=` (contains), `~=` (the whole value
  matches a regular expression, Java `String.matches`) and `!~`, `+` `-` `*`
  `div` `mod`, `|` and unary `-`; string and number literals; location paths
  relative to the context node (`a`, `@href`, `text()`, `..`,
  `following-sibling::li`); functions `position` `last` `first` `not` `count`
  `contains` `starts-with` `ends-with` `string-length` `concat` `substring`
  (1-based start and a length) `substring-ex` (0-based, Java substring)
  `substring-after` `substring-after-last` `substring-before`
  `substring-before-last` `sum`. `=` compares as strings when the two sides
  are of different types, and nodes are their own text, as in JsoupXpath
  `XValue`. Parsed expressions are cached. `format-date` is not supported and
  is rejected instead of being read as a path.
- `lib/src/execute.dart` `_matchPredicates`: a predicate is evaluated with
  that evaluator. A number is a position among the nodes being filtered,
  counted from the end when negative (`[-1]`, JsoupXpath); any other value
  holds when it is true or not empty, so `[a]`, `[@href]` and `[not(a)]` test
  existence. Upstream matched predicates with regular expressions and
  evaluated what was left with the `expressions` package; that code and
  `lib/src/reg.dart`, `lib/src/utils/op.dart` are removed.
- `lib/src/execute.dart`, `lib/src/selector.dart`,
  `lib/src/utils/dom_selector.dart`: JsoupXpath's `preceding` (the preceding
  sibling elements of the node and of each ancestor, nearest first),
  `following-sibling-one` and `preceding-sibling-one` axes.
- `lib/src/parser.dart` `splitXPathSteps`, `_splitPredicates`: steps are split
  on the slashes, and predicates on the brackets, outside quotes, `[...]` and
  `(...)`. Upstream matched steps with a regular expression that dropped `..`
  and `.` and cut predicates holding `]` or a function with arguments. A node
  test that is not a name, `*`, `.`, `..` or `node()` (`div[2] div`, a missing
  `/`) is rejected.
- `lib/src/parser.dart` `parseAttr`, `elementFunction`,
  `lib/src/expression.dart` `ownTextNodes`, `lib/src/model/base.dart`
  `XPathNode.textNodesOf`: `text()` is JsoupXpath's: one string for each of
  the element's own text nodes, without its child elements' text
  (`<p>甲<b>乙</b>丙</p>` gives `甲` and `丙`); `//text()` every text node
  inside, in document order; in a predicate the own text joined. Upstream
  gave the text of the element and all its descendants. The HTML model of
  `xpath_selector_html_parser` exposes element children only, so the app
  sets `XPathNode.textNodesOf` to read text nodes from its DOM.
- `lib/src/parser.dart` `_parseSelector`: the predicates are split off
  before the axis, so a predicate may hold one (`li[following-sibling::li]`).
  A node test may hold any non-ASCII letter (XML tags such as `章`).
- `lib/src/execute.dart` `_matchPredicates`: a position that is not finite
  (`[1 div 0]`) does not hold. `lib/src/expression.dart` `_tokenize`: a
  character that starts no token (`[!a]`) is a `FormatException`.
- `lib/src/parser.dart` `_parseSimpleSelector`, `elementFunction`: the last
  step may be a function: `num()` (the first number in the text),
  `allText()` (all the text inside), or a call with arguments (`substring-after(text(),'：')`)
  evaluated with the node as the context.
- `lib/src/builder.dart` `XPath.query`: a whole expression that is a function
  call (`concat(//h2/text(),'!')`, `sum(//li/span/num())`) gives one string,
  from the root. Parsed paths are cached.
- `lib/src/parser.dart` `parseSelectGroup` / `_parseSelector`: when the first
  step of a path has no leading `/` and is an element name (a relative location
  path such as `div[2]/div/h3/a/@title`), it is read as a child step from the
  queried node, the same as `/div[2]` from that node. Upstream threw `is not a
  valid xpath query string`.
- `lib/src/parser.dart` `splitXPathUnion`, used by `parseSelectGroup` and
  exported from `xpath_selector.dart`: a union is split on its top-level `|`
  only. Upstream split on every `|`, so a value such as
  `a[@data-ref='v1|part']` was cut into two broken paths.
- `pubspec.yaml`: version `3.0.2+nightreader.2`, `publish_to: none`, Dart
  `>=3.0.0` (the evaluator uses Dart 3 syntax), no `expressions` dependency,
  no `dev_dependencies`. `lib/xpath_selector.dart` uses `library;`.
- `analysis_options.yaml` includes the app's rules and turns off
  `no_leading_underscores_for_local_identifiers`, which the upstream
  `parser.dart` trips; the upstream source is not edited for lint.

## Reason and tracking

Legado evaluates XPath rules with JsoupXpath, which supports existence
predicates. Book sources in the yckceo.com repository use them (思兔阅读
`//*[@id='allchapter']//dd[a]`, 第一版主 banzhu `//li/div//a[@class]/text()`);
upstream 3.0.2 throws `Unsupported predicate`. Relative paths are used from
a list item (novelnext and the other English novel sites
`@XPath:div[2]/div/h3/a/@title`); JsoupXpath evaluates them from that node.
JsoupXpath parses a union with its grammar, so a `|` inside a quoted value
is part of the value. The app depends on this copy
through `dependency_overrides` so `xpath_selector_html_parser` uses it too.
Tests: `test/core/engine/parsers/analyze_by_xpath_test.dart`,
`test/core/engine/parsers/xpath_jsoupxpath_test.dart`.
