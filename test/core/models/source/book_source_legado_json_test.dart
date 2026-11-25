import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/sync/source_sync.dart';
import 'package:night_reader/features/source_manager/source_share.dart';

BookSource _source() => BookSource(
  bookSourceUrl: 'https://b.example',
  bookSourceName: '乙',
  enabled: false,
  enabledExplore: true,
  enabledCookieJar: false,
);

void main() {
  test('書源轉成 Legado 讀得懂的樣子：只有三個開關換成 true／false，其餘照 toJson', () {
    final json = _source().toJson();
    final legado = _source().toLegadoJson();
    expect(legado['enabled'], isFalse);
    expect(legado['enabledExplore'], isTrue);
    expect(legado['enabledCookieJar'], isFalse);
    expect(
      jsonEncode(legado),
      jsonEncode({
        ...json,
        'enabled': false,
        'enabledExplore': true,
        'enabledCookieJar': false,
      }),
    );
  });

  test('匯出、分享選中的書源寫 Legado 讀得懂的開關', () {
    final list = jsonDecode(encodeBookSources([_source()])) as List<dynamic>;
    final source = list.single as Map<String, dynamic>;
    expect(source['enabled'], isFalse);
    expect(source['enabledExplore'], isTrue);
    expect(source['enabledCookieJar'], isFalse);
  });

  test('Legado 格式讀回來是同一個書源，同步紀錄不變', () {
    final original = SourceSync.recordOf(_source());
    // toJson 照舊寫 1／0：同步照它算指紋。
    expect(original.data['enabled'], 0);
    expect(original.data['enabledExplore'], 1);
    final roundTrip = BookSource.fromJson(
      jsonDecode(encodeBookSources([_source()])).single as Map<String, dynamic>,
    );
    expect(SourceSync.recordOf(roundTrip).fingerprint, original.fingerprint);
  });
}
