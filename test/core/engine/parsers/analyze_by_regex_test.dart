import 'package:flutter_test/flutter_test.dart';
import 'package:reader/core/engine/parsers/analyze_by_regex.dart';

void main() {
  group('AnalyzeByRegex Tests', () {
    const text = 'Name: John Doe, Age: 30; Name: Jane Smith, Age: 25';

    test('getElements - chain extraction', () {
      // First extract segments, then extract names
      final matches = AnalyzeByRegex.getElements(text, [
        r'Name: [^;]+',
        r'Name: ([^,]+)',
      ]);
      expect(matches.length, 2);
      expect(matches[0][1], 'John Doe');
      expect(matches[1][1], 'Jane Smith');
    });

    test('getString - simple extraction', () {
      final result = AnalyzeByRegex.getString(text, r'Name: ([^,]+)');
      expect(result, 'Name: John Doe\nName: Jane Smith');
    });

    test('replace - simple replacement', () {
      final result = AnalyzeByRegex.replace('Hello World', '##World##Dart');
      expect(result, 'Hello Dart');
    });

    test(r'replace - with groups $1, $2', () {
      final result = AnalyzeByRegex.replace(
        'John Doe',
        r'##(\w+) (\w+)##$2, $1',
      );
      expect(result, 'Doe, John');
    });

    test('getString - automatically routes to replace when ## present', () {
      final result = AnalyzeByRegex.getString('abc 123 def', r'##\d+##XYZ');
      expect(result, 'abc XYZ def');
    });

    test('getElements supports legado inline regex flags', () {
      const multilineText = 'id=123\nclass="name">第一章';
      final matches = AnalyzeByRegex.getElements(multilineText, [
        r'(?s)(\d+)\s*class="([^"]+)">([^<]+)',
      ]);

      expect(matches, hasLength(1));
      expect(matches.first[1], '123');
      expect(matches.first[2], 'name');
      expect(matches.first[3], '第一章');
    });
  });
}
