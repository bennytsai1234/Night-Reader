import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_repair_secrets.dart';
import 'package:night_reader/core/services/cookie_store.dart';

void main() {
  test('a secret is hidden in its JSON-escaped forms too', () {
    // 審查：含引號的密碼放進書源 JSON（標頭本身是 JSON 字串，再跳脫一層）。
    const secret = 'password-"123456';
    final once = jsonEncode({'header': secret});
    final twice = jsonEncode({
      'source': jsonEncode({'header': secret}),
    });

    for (final text in [
      secret,
      once,
      twice,
      Uri.encodeQueryComponent(secret),
    ]) {
      final hidden = redactAiRepairSecrets(text, {secret});
      expect(hidden, contains(aiRepairRedacted), reason: text);
      expect(hidden, isNot(contains('123456')), reason: text);
    }
  });

  test('cookies written during the repair are read live', () async {
    // 審查：開始時沒有 Cookie，修到一半規則或網站驗證才寫進來。
    const url = 'https://live-cookie.example';
    expect(aiRepairLiveCookieSecrets({url}), isEmpty);
    await CookieStore().setCookie(url, 'sid=session-value-9876; a=1');
    expect(aiRepairLiveCookieSecrets({url}), {'session-value-9876'});
  });
}
