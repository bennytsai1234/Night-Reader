import 'package:flutter_test/flutter_test.dart';
import 'package:reader/core/models/book_source_part.dart';
import 'package:reader/core/models/rule_sub.dart';

void main() {
  group('Miscellaneous Models Tests', () {
    test('BookSourcePart serialization', () {
      final part = BookSourcePart(
        bookSourceUrl: 'http://source.com',
        bookSourceName: 'Source Name',
        enabled: true,
      );
      final json = part.toJson();
      final fromJson = BookSourcePart.fromJson(json);
      expect(fromJson.bookSourceUrl, 'http://source.com');
      expect(fromJson.bookSourceName, 'Source Name');
    });

    test('RuleSub serialization', () {
      final sub = RuleSub(
        id: 789,
        name: 'Regex Sub',
        url: 'http://rules.com/regex',
      );
      final json = sub.toJson();
      final fromJson = RuleSub.fromJson(json);
      expect(fromJson.id, 789);
      expect(fromJson.url, contains('regex'));
    });
  });
}
