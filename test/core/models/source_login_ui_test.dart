import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/source/lenient_json.dart';
import 'package:night_reader/core/models/source/source_login_ui.dart';

void main() {
  group('decodeLenientJson', () {
    // 源倉庫一半的登入表單照 JS 的寫法填（欄位名不加引號），Legado 用 Gson
    // 的寬鬆模式照收，夜讀以前整份讀不出來。
    test('reads the loose JSON Gson accepts', () {
      final value = decodeLenientJson('''
        [
          // 輸入框
          {name: "邮箱", type: 'text'},
          /* 按鈕 */
          {name: "登录", type: "button", action: "login()", style: {
            layout_flexGrow: 1, layout_flexBasisPercent: 0.4,
          },},
          # 舊式註解
          {'name': 'x=y', type => button},
        ]
      ''');

      expect(value, [
        {'name': '邮箱', 'type': 'text'},
        {
          'name': '登录',
          'type': 'button',
          'action': 'login()',
          'style': {'layout_flexGrow': 1, 'layout_flexBasisPercent': 0.4},
        },
        {'name': 'x=y', 'type': 'button'},
      ]);
    });

    test('keeps escapes and rejects broken input', () {
      expect(decodeLenientJson(r'["a\nb", "中", true, null, -1]'), [
        'a\nb',
        '中',
        true,
        null,
        -1,
      ]);
      expect(() => decodeLenientJson('[{name: "x"'), throwsFormatException);
      expect(() => decodeLenientJson('[1] trailing'), throwsFormatException);
    });
  });

  group('SourceLoginUi.parse', () {
    test('reads rows, styles and drops the kinds Legado does not show', () {
      final ui = SourceLoginUi.parse('''
        [
          {name: "账号", type: "text"},
          {name: "密码", type: "password"},
          {name: "登录", type: "button", action: "login()",
            style: {layout_flexGrow: 1, layout_flexBasisPercent: 0.25,
              layout_wrapBefore: true}},
          {name: "查看划线评", type: "toggle"},
        ]
      ''');

      final rows = (ui! as SourceLoginUiRows).rows;
      expect(rows.map((row) => (row.name, row.type)), [
        ('账号', SourceLoginRowType.text),
        ('密码', SourceLoginRowType.password),
        ('登录', SourceLoginRowType.button),
      ]);
      final style = rows.last.style;
      expect(style.grow, 1);
      expect(style.basisPercent, 0.25);
      expect(style.wrapBefore, isTrue);
      expect(rows.first.style.basisPercent, -1);
    });

    test('tells apart no form, generated forms and broken forms', () {
      expect(SourceLoginUi.parse(null), isNull);
      expect(SourceLoginUi.parse('  '), isNull);
      expect(
        (SourceLoginUi.parse('@js: buildUi()')! as SourceLoginUiScript).script,
        ' buildUi()',
      );
      expect(
        (SourceLoginUi.parse('<js>JSON.stringify([])</js>')!
                as SourceLoginUiScript)
            .script,
        'JSON.stringify([])',
      );
      expect(SourceLoginUi.parse('[{name: '), isA<SourceLoginUiBroken>());
      expect(SourceLoginUi.parse('{"name": "x"}'), isA<SourceLoginUiBroken>());
    });
  });

  test('a source has login when it fills a login url or program', () {
    expect(BookSource(bookSourceUrl: 'https://a.test').hasLogin, isFalse);
    expect(
      BookSource(bookSourceUrl: 'https://a.test', loginUrl: '  ').hasLogin,
      isFalse,
    );
    expect(
      BookSource(bookSourceUrl: 'https://a.test', loginUrl: '/login').hasLogin,
      isTrue,
    );
    // 同 Legado：沒有 @js: 前綴的登入程式照原樣交出。
    expect(
      BookSource(
        bookSourceUrl: 'https://a.test',
        loginUrl: 'function login() {}',
      ).getLoginJs(),
      'function login() {}',
    );
  });
}
