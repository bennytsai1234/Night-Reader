import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/about/about_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PackageInfo.setMockInitialValues(
      appName: '夜讀',
      packageName: 'com.inkpage.reader',
      version: '0.4.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('the Wi-Fi download row only shows while auto-check is on', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pumpAndSettle();

    expect(find.text('在 Wi-Fi 下自動下載更新'), findsOneWidget);

    await tester.ensureVisible(find.text('自動檢查更新'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自動檢查更新'));
    await tester.pumpAndSettle();

    expect(find.text('在 Wi-Fi 下自動下載更新'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('update.auto_check'), isFalse);
  });
}
