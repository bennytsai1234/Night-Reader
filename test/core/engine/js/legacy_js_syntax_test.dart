import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/js/legacy_js_syntax.dart';

void main() {
  group('array destructuring arrow parameters get parentheses', () {
    test('after an operator, a comma or an opening parenthesis', () {
      expect(
        LegacyJsSyntax.normalize('var f = [a, b] => a + b;'),
        'var f = ([a, b]) => a + b;',
      );
      expect(
        LegacyJsSyntax.normalize('list.map([k, v] => k + v)'),
        'list.map(([k, v]) => k + v)',
      );
      expect(
        LegacyJsSyntax.normalize('f(x, [k, v] => v)'),
        'f(x, ([k, v]) => v)',
      );
    });

    test('at the start of the rule', () {
      expect(LegacyJsSyntax.normalize('  [a, b] => a'), '  ([a, b]) => a');
    });

    test('with a string default inside the parameters', () {
      expect(
        LegacyJsSyntax.normalize('var f = [a = "x", b] => a;'),
        'var f = ([a = "x", b]) => a;',
      );
    });

    test('inside a template interpolation', () {
      expect(
        LegacyJsSyntax.normalize(r'`${list.map([k, v] => k)}`'),
        r'`${list.map(([k, v]) => k)}`',
      );
    });
  });

  group('literals are left as they are', () {
    for (final (name, code) in [
      ('double-quoted string', 'var t = "key=[a,b] => secret"; t'),
      ('single-quoted string', "var t = 'key=[a,b] => secret'; t"),
      ('line comment', 'var t = 1; // x=[a,b] => y\nt'),
      ('block comment', 'var t = 1; /* x=[a,b] => y */ t'),
      ('regular expression', r'var r = /=[a,b] =>/; r'),
      ('template text', r'var t = `key=[a,b] => ${1}`; t'),
    ]) {
      test(name, () => expect(LegacyJsSyntax.normalize(code), code));
    }
  });

  group('unknown template escapes lose the extra backslash', () {
    test('in template text', () {
      expect(
        LegacyJsSyntax.normalize(r'var p = `${cb}\((.*)\)`;'),
        r'var p = `${cb}((.*))`;',
      );
    });

    test('known escapes and other literals keep theirs', () {
      const code = r'var p = `a\n\`b\${c}`; var s = "\("; var r = /\(/;';
      expect(LegacyJsSyntax.normalize(code), code);
    });
  });
}
