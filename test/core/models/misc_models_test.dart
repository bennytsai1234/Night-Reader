import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/book_source_part.dart';
import 'package:night_reader/core/models/rule_sub.dart';
import 'package:night_reader/core/models/source/explore_kind.dart';

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

    test('missing enabled flags retain source and subscription defaults', () {
      final source = BookSource.fromJson(const <String, dynamic>{});
      final subscription = RuleSub.fromJson(const <String, dynamic>{});

      expect(source.enabled, isTrue);
      expect(source.enabledExplore, isTrue);
      expect(source.enabledCookieJar, isTrue);
      expect(subscription.enabled, isTrue);
    });

    test('FlexChildStyle falls back for non-finite imported numbers', () {
      final style = FlexChildStyle.fromJson({
        'layout_flexGrow': 'NaN',
        'layout_flexShrink': double.infinity,
        'layout_flexBasisPercent': '-Infinity',
      });

      expect(style.layoutFlexGrow, FlexChildStyle.defaultStyle.layoutFlexGrow);
      expect(
        style.layoutFlexShrink,
        FlexChildStyle.defaultStyle.layoutFlexShrink,
      );
      expect(
        style.layoutFlexBasisPercent,
        FlexChildStyle.defaultStyle.layoutFlexBasisPercent,
      );
    });
  });
}
