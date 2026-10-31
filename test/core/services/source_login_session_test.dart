import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/source/source_login_ui.dart';
import 'package:night_reader/core/services/source_interaction.dart';
import 'package:night_reader/core/services/source_login_session.dart';

import '../../test_helper.dart';

class _RecordingHandler implements SourceInteractionHandler {
  final List<String> messages = [];

  @override
  Future<String?> browse(SourceBrowseRequest request) async => null;

  @override
  Future<String?> verificationCode(SourceCodeRequest request) async => null;

  @override
  void message(SourceMessage message) => messages.add(message.text);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();
  final skip = quickJsUnavailableReason();

  var serial = 0;
  BookSource sourceWith(String loginUrl) {
    final source = BookSource(
      bookSourceUrl: 'https://login-${serial++}.site.test',
      bookSourceName: '測試書源',
      loginUrl: loginUrl,
      loginUi: '[{name: "帳號", type: "text"}]',
    );
    addTearDown(source.clearLoginData);
    return source;
  }

  test('submit saves the form over stored fields and runs login()', () async {
    final source = sourceWith('''@js:
      function login() {
        var info = source.getLoginInfoMap();
        source.putLoginHeader(JSON.stringify({token: info['帳號'] + '-ok'}));
      }''');
    // 按鈕之前自己存的 token 留著，表單的欄位蓋過去。
    await source.putLoginInfo('{"帳號":"old","token":"keep"}');
    final session = await SourceLoginSession.open(source);
    addTearDown(session.close);

    expect(await session.submit({'帳號': 'reader'}), isTrue);

    expect(jsonDecode((await source.getLoginInfo())!), {
      '帳號': 'reader',
      'token': 'keep',
    });
    expect(await source.getLoginHeader(), '{"token":"reader-ok"}');
  }, skip: skip);

  // 只是設定面板的表單沒有 login 函式：打勾只存，不像 Legado 跳錯誤。
  test('submit without a login function only saves', () async {
    final source = sourceWith('@js: function other() {}');
    final session = await SourceLoginSession.open(source);
    addTearDown(session.close);

    expect(await session.submit({'帳號': 'reader'}), isFalse);
    expect(jsonDecode((await source.getLoginInfo())!), {'帳號': 'reader'});
  }, skip: skip);

  test('a button runs with the form as result and talks to the page', () async {
    final source = sourceWith(
      '@js: function hello(name) { return "你好" + name; }',
    );
    final handler = _RecordingHandler();
    SourceInteraction.handler = handler;
    addTearDown(() => SourceInteraction.handler = null);
    final session = await SourceLoginSession.open(source);
    addTearDown(session.close);

    await session.pressButton(
      'java.toast(hello(result["帳號"]));'
      'source.putLoginHeader(JSON.stringify({name: result["帳號"]}))',
      {'帳號': 'reader'},
    );

    expect(handler.messages, ['你好reader']);
    expect(await source.getLoginHeader(), '{"name":"reader"}');
    await expectLater(
      session.pressButton('throw "壞了"', const {}),
      throwsA(anything),
    );
  }, skip: skip);

  test('a generated form is read from the program', () async {
    final source = sourceWith('@js: function login() {}');
    final session = await SourceLoginSession.open(source);
    addTearDown(session.close);

    final rows = await session.loadScriptForm(
      'JSON.stringify([{name: "帳號", type: "text"},'
      '{name: "登入", type: "button", action: "login()"}])',
    );

    expect(rows.map((row) => (row.name, row.type)), [
      ('帳號', SourceLoginRowType.text),
      ('登入', SourceLoginRowType.button),
    ]);
  }, skip: skip);
}
