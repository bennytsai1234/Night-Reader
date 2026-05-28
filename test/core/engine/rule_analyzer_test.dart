import 'package:flutter_test/flutter_test.dart';
import 'package:reader/core/engine/rule_analyzer.dart';

void main() {
  group('RuleAnalyzer Tests', () {
    test('splitRule with &&', () {
      final analyzer = RuleAnalyzer('rule1 && rule2 && rule3');
      final result = analyzer.splitRule(['&&']);
      expect(result, ['rule1 ', ' rule2 ', ' rule3']);
      expect(analyzer.elementsType, '&&');
    });

    test('splitRule with ||', () {
      final analyzer = RuleAnalyzer('rule1 || rule2');
      final result = analyzer.splitRule(['||']);
      expect(result, ['rule1 ', ' rule2']);
      expect(analyzer.elementsType, '||');
    });

    test('splitRule with balanced brackets', () {
      final analyzer = RuleAnalyzer('rule1[a && b] && rule2');
      final result = analyzer.splitRule(['&&']);
      // && inside brackets should not be split
      expect(result, ['rule1[a && b] ', ' rule2']);
    });

    test('innerRuleRange for {{js}}', () {
      final analyzer = RuleAnalyzer('Prefix {{js_code}} Suffix');
      final result = analyzer.innerRuleRange(
        '{{',
        '}}',
        fr: (code) {
          expect(code, 'js_code');
          return 'REPLACED';
        },
      );
      expect(result, 'Prefix REPLACED Suffix');
    });

    test('innerRule for @get', () {
      // Assuming @get:{key} format
      final analyzer = RuleAnalyzer('Data: @get:{myKey}');
      final result = analyzer.innerRuleRange(
        '@get:{',
        '}',
        fr: (key) {
          expect(key, 'myKey');
          return 'VALUE';
        },
      );
      expect(result, 'Data: VALUE');
    });

    test('trim leading @ and whitespace', () {
      final analyzer = RuleAnalyzer('  @  rule');
      analyzer.trim();
      final result = analyzer.splitRule(['&&']);
      expect(result, ['rule']);
    });
  });
}
