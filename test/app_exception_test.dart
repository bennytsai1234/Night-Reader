import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/exception/app_exception.dart';

void main() {
  group('AppException hierarchy', () {
    test('ConcurrentException carries message and waitTime', () {
      final e = ConcurrentException('too many requests', 5000);
      expect(e.message, 'too many requests');
      expect(e.waitTime, 5000);
      expect(e.toString(), 'too many requests');
      expect(e, isA<AppException>());
    });

    test('ContentEmptyException toString returns message', () {
      final e = ContentEmptyException('content is empty');
      expect(e.message, 'content is empty');
      expect(e.toString(), 'content is empty');
    });

    test('TocEmptyException is an AppException', () {
      final e = TocEmptyException('no chapters found');
      expect(e, isA<AppException>());
      expect(e.message, 'no chapters found');
    });

    test('RegexTimeoutException is an AppException', () {
      final e = RegexTimeoutException('regex took too long');
      expect(e, isA<AppException>());
      expect(e.toString(), 'regex took too long');
    });

    test('EmptyFileException is an AppException', () {
      final e = EmptyFileException('file is empty');
      expect(e, isA<AppException>());
      expect(e.message, 'file is empty');
    });

    test('NoBooksDirException is an AppException', () {
      final e = NoBooksDirException('books dir not found');
      expect(e, isA<AppException>());
      expect(e.message, 'books dir not found');
    });

    test('InvalidBooksDirException is an AppException', () {
      final e = InvalidBooksDirException('invalid books dir');
      expect(e, isA<AppException>());
      expect(e.message, 'invalid books dir');
    });

    test('NoStackTraceException is an AppException', () {
      final e = NoStackTraceException('legacy error');
      expect(e, isA<AppException>());
      expect(e.toString(), 'legacy error');
    });

    test('NetworkException carries statusCode and url', () {
      final e = NetworkException(
        'connection failed',
        statusCode: 503,
        url: 'https://example.com',
      );
      expect(e, isA<AppException>());
      expect(e.message, 'connection failed');
      expect(e.statusCode, 503);
      expect(e.url, 'https://example.com');
      expect(e.toString(), 'connection failed');
    });

    test('NetworkException optional fields default to null', () {
      final e = NetworkException('timeout');
      expect(e.statusCode, isNull);
      expect(e.url, isNull);
    });

    test('ParsingException carries rule details', () {
      final e = ParsingException(
        'parse error',
        rule: 'ruleSearch',
        mode: 'xpath',
        url: 'https://example.com',
      );
      expect(e, isA<AppException>());
      expect(e.message, 'parse error');
      expect(e.rule, 'ruleSearch');
      expect(e.mode, 'xpath');
      expect(e.url, 'https://example.com');
      expect(e.toString(), contains('[xpath] parse error'));
      expect(e.toString(), contains('規則: ruleSearch'));
    });

    test('ParsingException fields default to null', () {
      final e = ParsingException('parse error');
      expect(e.rule, isNull);
      expect(e.mode, isNull);
      expect(e.url, isNull);
    });

    test('LoginCheckException carries sourceUrl', () {
      final e = LoginCheckException(
        'login required',
        sourceUrl: 'https://src.com',
      );
      expect(e, isA<AppException>());
      expect(e.message, 'login required');
      expect(e.sourceUrl, 'https://src.com');
    });

    test('SourceException carries sourceUrl', () {
      final e = SourceException('missing field', sourceUrl: 'https://src.com');
      expect(e, isA<AppException>());
      expect(e.message, 'missing field');
      expect(e.sourceUrl, 'https://src.com');
    });

    test('AdultContentException is an AppException', () {
      final e = AdultContentException('18+ content blocked');
      expect(e, isA<AppException>());
      expect(e.message, '18+ content blocked');
      expect(e.toString(), '18+ content blocked');
    });

    test('DownloadException carries bookUrl and chapterIndex', () {
      final e = DownloadException(
        'download failed',
        bookUrl: 'https://example.com/book/1',
        chapterIndex: 5,
      );
      expect(e, isA<AppException>());
      expect(e.message, 'download failed');
      expect(e.bookUrl, 'https://example.com/book/1');
      expect(e.chapterIndex, 5);
    });

    test('DownloadException optional fields default to null', () {
      final e = DownloadException('error');
      expect(e.bookUrl, isNull);
      expect(e.chapterIndex, isNull);
    });

    test('All exceptions implement Exception interface', () {
      final exceptions = <AppException>[
        ConcurrentException('a', 1),
        ContentEmptyException('b'),
        TocEmptyException('c'),
        RegexTimeoutException('d'),
        EmptyFileException('e'),
        NoBooksDirException('f'),
        InvalidBooksDirException('g'),
        NoStackTraceException('h'),
        NetworkException('i'),
        ParsingException('j'),
        LoginCheckException('k'),
        SourceException('l'),
        AdultContentException('m'),
        DownloadException('n'),
      ];

      for (final e in exceptions) {
        expect(e, isA<Exception>());
        expect(e.toString(), isNotEmpty);
      }
    });
  });
}
