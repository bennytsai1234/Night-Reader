import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/replace_rule.dart';

void main() {
  group('ReplaceRule', () {
    test('applies regex replacement with capture groups consistently', () {
      final rule = ReplaceRule(pattern: r'junk(\d+)', replacement: r'ok$1');

      expect(rule.apply('a junk123 b'), 'a ok123 b');
    });

    test('keeps escaped dollar signs in regex replacement', () {
      final rule = ReplaceRule(pattern: r'price(\d+)', replacement: r'\$$1');

      expect(rule.apply('price99'), r'$99');
    });

    test('imports legado legacy replace rule json keys', () {
      final rule = ReplaceRule.fromJson({
        'id': '42',
        'regex': r'ad\d+',
        'replaceSummary': '清理廣告',
        'replacement': '',
        'useTo': '測試書',
        'enable': '1',
        'serialNumber': '7',
      });

      expect(rule.id, 42);
      expect(rule.name, '清理廣告');
      expect(rule.pattern, r'ad\d+');
      expect(rule.scope, '測試書');
      expect(rule.isEnabled, isTrue);
      expect(rule.isRegex, isTrue);
      expect(rule.scopeContent, isTrue);
      expect(rule.order, 7);
    });

    test(
      'matches include and exclude scope without empty wildcard matches',
      () {
        final rule = ReplaceRule(
          pattern: 'bad',
          replacement: '',
          scope: '測試書;https://source.example',
          excludeScope: '排除書',
        );

        expect(rule.matchesScope(bookName: '測試書', bookOrigin: ''), isTrue);
        expect(rule.matchesScope(bookName: '其他書', bookOrigin: ''), isFalse);
        expect(rule.matchesScope(bookName: '排除書', bookOrigin: ''), isFalse);
      },
    );
  });
}
