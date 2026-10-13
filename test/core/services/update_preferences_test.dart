import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/update_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late DateTime now;
  late UpdatePreferences preferences;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    now = DateTime(2026, 10, 13, 9);
    preferences = UpdatePreferences(clock: () => now);
  });

  test('automatic check and Wi-Fi download default to on', () async {
    expect(await preferences.autoCheck(), isTrue);
    expect(
      await preferences.autoDownload(),
      UpdatePreferences.defaultAutoDownload,
    );

    await preferences.setAutoCheck(false);
    await preferences.setAutoDownload(false);
    expect(await preferences.autoCheck(), isFalse);
    expect(await preferences.autoDownload(), isFalse);
  });

  test('remind later holds off automatic prompts for a week', () async {
    expect(await preferences.inRemindLaterCooldown(), isFalse);

    await preferences.remindLater();
    now = now.add(const Duration(days: 6, hours: 23));
    expect(await preferences.inRemindLaterCooldown(), isTrue);

    now = now.add(const Duration(hours: 1));
    expect(await preferences.inRemindLaterCooldown(), isFalse);
  });

  test('a remind-later time in the future does not hold prompts', () async {
    await preferences.remindLater();
    // 使用者把系統時間往回調：記下的時間落在未來，不該無限期壓住提示。
    now = now.subtract(const Duration(days: 1));
    expect(await preferences.inRemindLaterCooldown(), isFalse);
  });
}
