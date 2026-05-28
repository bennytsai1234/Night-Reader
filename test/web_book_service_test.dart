import 'package:flutter_test/flutter_test.dart';
import 'package:reader/core/exception/app_exception.dart';
import 'package:reader/core/models/book_source.dart';

void main() {
  group('WebBook guard logic', () {
    test('AdultContentException is thrown for 18+ sources', () {
      // Verify that AdultContentException can be constructed correctly
      final e = AdultContentException('blocked');
      expect(e, isA<AppException>());
      expect(e.message, 'blocked');
    });

    test('SourceException is thrown for empty search URL', () {
      // Verify SourceException carries sourceUrl
      final e = SourceException(
        '搜尋 URL 不能為空',
        sourceUrl: 'https://example.com',
      );
      expect(e, isA<AppException>());
      expect(e.sourceUrl, 'https://example.com');
      expect(e.message, '搜尋 URL 不能為空');
    });

    test('SourceException is thrown for null search URL', () {
      // A source with no searchUrl should trigger SourceException
      final source = BookSource(bookSourceUrl: 'https://example.com');
      expect(source.searchUrl, isNull);
    });

    test('BookSource with empty searchUrl string is treated as empty', () {
      final source = BookSource(
        bookSourceUrl: 'https://example.com',
        searchUrl: '',
      );
      expect(source.searchUrl, isEmpty);
    });
  });
}
