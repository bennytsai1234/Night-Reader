import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_repair_secrets.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/network/network_service.dart';

void main() {
  test('cookies the site set in the network cookie jar are secrets too: a '
      'page that prints them back does not hand them to the AI', () async {
    await NetworkService().init(ephemeral: true);
    await NetworkService().cookieJar.saveFromResponse(
      Uri.parse('https://www.site.example/'),
      [Cookie('sid', 'jar-cookie-value-123')],
    );

    final secrets = await aiRepairSecretsOf(
      BookSource(
        bookSourceUrl: 'https://www.site.example',
        bookSourceName: '範例書站',
      ),
    );

    expect(secrets, contains('jar-cookie-value-123'));
    expect(
      redactAiRepairSecrets('你的工作階段：jar-cookie-value-123', secrets),
      '你的工作階段：$aiRepairRedacted',
    );
  });

  // 書源標頭的代理可能帶帳號密碼：書源 JSON、試抓的紀錄都會出現它。
  test(
    'the proxy in the source header is a secret, credentials and all',
    () async {
      await NetworkService().init(ephemeral: true);
      const proxy = 'http://10.0.0.1:8080@reader@pass-word-99';
      final secrets = await aiRepairSecretsOf(
        BookSource(
          bookSourceUrl: 'https://proxy.example',
          bookSourceName: '代理書站',
          header: '{"proxy":"$proxy","Referer":"https://proxy.example/"}',
        ),
      );

      expect(
        secrets,
        containsAll([proxy, 'pass-word-99', '@reader@pass-word-99']),
      );
      final redacted = redactAiRepairSecrets(
        '"header":"{\\"proxy\\":\\"$proxy\\"}"',
        secrets,
      );
      expect(redacted, isNot(contains('pass-word-99')));
      expect(redacted, isNot(contains('reader')));
    },
  );
}
