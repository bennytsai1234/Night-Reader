import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/base_source.dart';
import 'package:night_reader/core/models/book_source.dart';

void main() {
  group('BaseSource login helpers', () {
    test('extractLoginJs strips @js prefix', () {
      expect(
        BaseSourceLoginHelper.extractLoginJs(
          '@js:function login(){return true;}',
        ),
        'function login(){return true;}',
      );
    });

    test('extractLoginJs strips js tags', () {
      expect(
        BaseSourceLoginHelper.extractLoginJs('<js>function login(){}</js>'),
        'function login(){}',
      );
    });

    test('extractLoginJs returns null for plain url', () {
      expect(
        BaseSourceLoginHelper.extractLoginJs('https://example.com/login'),
        isNull,
      );
    });

    test('loginUiConfig parses list config', () {
      final source = BookSource(
        bookSourceUrl: 'https://example.com',
        bookSourceName: 'Example',
        loginUi: '[{"name":"帳號","type":"text"},{"name":"登入","type":"button"}]',
      );

      expect(source.loginUiConfig(), isNotNull);
      expect(source.loginUiConfig()!.length, 2);
      expect(source.loginUiConfig()!.first['name'], '帳號');
    });

    test('getLoginJs delegates to helper', () {
      final source = BookSource(
        bookSourceUrl: 'https://example.com',
        bookSourceName: 'Example',
        loginUrl: '@js:function login(){return "ok";}',
      );

      expect(source.getLoginJs(), 'function login(){return "ok";}');
    });
  });
}
