import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/source_type.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/source_interaction.dart';
import 'package:night_reader/features/source_login/source_failure_remedy.dart';

const _sourceUrl = 'https://remedy.test';

const _verification = SourceBrowseRequest(
  url: 'https://remedy.test/verify',
  title: '驗證',
  headers: {},
);

BookSource _source({String? loginUrl}) => BookSource(
  bookSourceUrl: _sourceUrl,
  bookSourceName: '測試書源',
  bookSourceType: SourceType.image,
  loginUrl: loginUrl,
);

void main() {
  tearDown(() => SourceInteraction.forgetVerification(_sourceUrl));

  test('要在網頁上驗證、記著要開的那一頁時是「前往驗證」', () {
    SourceInteraction.rememberVerification(_sourceUrl, _verification);
    final remedy = SourceFailureRemedy.of('需要在網頁上驗證', _source());
    expect(remedy?.label, '前往驗證');
  });

  test('要在網頁上驗證但沒有記著要開的那一頁時沒有解法', () {
    final remedy = SourceFailureRemedy.of('需要在網頁上驗證', _source());
    expect(remedy, isNull);
  });

  test('要登入、書源有登入時是「登入」', () {
    final remedy = SourceFailureRemedy.of(
      '需要登入',
      _source(loginUrl: 'https://remedy.test/login'),
    );
    expect(remedy?.label, '登入');
  });

  test('要登入但書源沒有登入時沒有解法', () {
    final remedy = SourceFailureRemedy.of('需要登入', _source());
    expect(remedy, isNull);
  });

  test('其他原因沒有解法', () {
    final remedy = SourceFailureRemedy.of(
      '網路連線失敗',
      _source(loginUrl: 'https://remedy.test/login'),
    );
    expect(remedy, isNull);
  });

  test('本地書（沒有書源）沒有解法', () {
    final remedy = SourceFailureRemedy.of('需要登入', null);
    expect(remedy, isNull);
  });
}
