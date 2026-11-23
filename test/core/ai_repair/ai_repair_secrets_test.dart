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
}
