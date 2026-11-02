# Night Reader patches for `xpath_selector`

## Source

- Package: [`xpath_selector` 3.0.2](https://pub.dev/packages/xpath_selector/versions/3.0.2)
- Archive: `https://pub.dev/api/archives/xpath_selector-3.0.2.tar.gz`
- Archive SHA-256: `6d8295565a34a6e2821a0721592e584c70421e52a0f54955e0c8e41963db7c90`
- Upstream repository: <https://github.com/simonkimi/xpath_selector>
- Vendored version: `3.0.2+nightreader.1`
- License: BSD 3-Clause; the upstream [`LICENSE`](LICENSE) is retained unchanged.
- Vendored files: `lib/`, `LICENSE`, `CHANGELOG.md`, `README.md`; `example/`, the
  IDE module file and the upstream `analysis_options.yaml` are left out.

## Local patch

- `lib/src/execute.dart` `_singleCompare`: a predicate that is only a child
  element or attribute name (`[a]`, `[@href]`, `*` for any), optionally wrapped
  in `not(...)`, holds when that child element or attribute exists (XPath 1.0:
  a non-empty node-set is true). Added as the last case before the
  `Unsupported predicate` error, so every predicate the upstream already
  understood is evaluated as before. `_multipleCompare` (`and` / `or`) is
  unchanged.
- `lib/src/reg.dart`: the `predicateExists` pattern for the case above.
- `pubspec.yaml`: version `3.0.2+nightreader.1`, `publish_to: none`, no
  `dev_dependencies`.
- `analysis_options.yaml` includes the app's rules and turns off
  `no_leading_underscores_for_local_identifiers`, which the upstream
  `parser.dart` trips; the upstream source is not edited for lint.

## Reason and tracking

Legado evaluates XPath rules with JsoupXpath, which supports existence
predicates. Book sources in the yckceo.com repository use them (思兔阅读
`//*[@id='allchapter']//dd[a]`, 第一版主 banzhu `//li/div//a[@class]/text()`);
upstream 3.0.2 throws `Unsupported predicate`. The app depends on this copy
through `dependency_overrides` so `xpath_selector_html_parser` uses it too.
Tests: `test/core/engine/parsers/analyze_by_xpath_test.dart`.
