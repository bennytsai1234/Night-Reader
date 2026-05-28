import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reader/features/about/about_page.dart';
import 'package:reader/features/settings/data_privacy_settings_page.dart';
import 'package:reader/features/settings/other_settings_page.dart';
import 'package:reader/features/settings/settings_page.dart';
import 'package:reader/features/settings/tts_settings_page.dart';

void main() {
  test('Settings pages can be constructed', () {
    expect(() => const AboutPage(), returnsNormally);
    expect(() => const OtherSettingsPage(), returnsNormally);
    expect(() => const DataPrivacySettingsPage(), returnsNormally);
    expect(() => const SettingsPage(), returnsNormally);
    expect(() => const TtsSettingsPage(), returnsNormally);
  });

  testWidgets('Settings page hides Reading Settings entry', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));

    expect(find.text('閱讀設定'), findsNothing);
    expect(find.text('朗讀與語音'), findsOneWidget);
  });
}
