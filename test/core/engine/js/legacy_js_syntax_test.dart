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

  group('a slash is told apart by what comes before it', () {
    test('after a postfix ++ or -- it divides', () {
      for (final op in ['++', '--']) {
        expect(
          LegacyJsSyntax.normalize('n$op / [[2]].map([v] => v)[0]'),
          'n$op / [[2]].map(([v]) => v)[0]',
        );
      }
    });

    test('after return it starts a regular expression', () {
      const quoted = 'function g() { return /"/.test(\'x\'); }\n';
      expect(
        LegacyJsSyntax.normalize('${quoted}var f = [a,b] => a;'),
        '${quoted}var f = ([a,b]) => a;',
      );
      const regex = 'function g() { return /=[a,b] =>/.source; }';
      expect(LegacyJsSyntax.normalize(regex), regex);
    });

    test('after a value it divides', () {
      expect(
        LegacyJsSyntax.normalize('var x = a / 2, f = [k, v] => v;'),
        'var x = a / 2, f = ([k, v]) => v;',
      );
      expect(
        LegacyJsSyntax.normalize('var x = (1) / 2 / 1.5; var f = [k] => k;'),
        'var x = (1) / 2 / 1.5; var f = ([k]) => k;',
      );
    });
  });

  group('every JavaScript line break ends a line', () {
    for (final (name, lineBreak) in [
      ('CR', String.fromCharCode(0x0D)),
      ('U+2028', String.fromCharCode(0x2028)),
      ('U+2029', String.fromCharCode(0x2029)),
    ]) {
      test('a line comment ends at $name', () {
        expect(
          LegacyJsSyntax.normalize(
            '// x=[a,b] => y${lineBreak}var f = [a,b] => a;',
          ),
          '// x=[a,b] => y${lineBreak}var f = ([a,b]) => a;',
        );
      });
    }

    test('a string continued with a backslash and CRLF stays one string', () {
      const code = 'var s = "a\\\r\n=[a,b] =>"; var f = [a,b] => a;';
      expect(
        LegacyJsSyntax.normalize(code),
        'var s = "a\\\r\n=[a,b] =>"; var f = ([a,b]) => a;',
      );
    });
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
