import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content_transformer.dart';

void main() {
  group('Reader V2 typography source semantics', () {
    test('pure Western text, spacing, ellipsis, URL and emoji ZWJ sequence stay byte-for-byte equivalent as Dart text', () {
      const source = 'Wait...   Version…   https://example.com 👨‍👩‍👧‍👦';
      expect(normalizeTypography(source), source);
    });

    test('ZWNJ shaping in a non-CJK script is preserved', () {
      const source = 'می‌خواهم...';
      expect(normalizeTypography(source), source);
      expect(normalizeTypography(source).contains('\u200C'), isTrue);
    });

    test('CJK normalization does not delete ZWJ or ZWNJ content', () {
      const source = '中文👨‍👩‍👧‍👦和‌字...';
      final normalized = normalizeTypography(source);

      expect(normalized.contains('\u200D'), isTrue);
      expect(normalized.contains('\u200C'), isTrue);
      expect(normalized, endsWith('……'));
    });
  });
}
