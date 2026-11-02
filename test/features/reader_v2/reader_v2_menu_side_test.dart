import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 閱讀選單與面板跟著每行字數對齊正文的左右邊。
void main() {
  Future<ReaderV2SettingsController> settingsWith(int lineChars) async {
    SharedPreferences.setMockInitialValues({
      PreferKey.readerLineChars: lineChars,
    });
    final getIt = GetIt.instance;
    if (getIt.isRegistered<SharedPreferences>()) {
      getIt.unregister<SharedPreferences>();
    }
    getIt.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    return ReaderV2SettingsController();
  }

  tearDown(GetIt.instance.reset);

  test(
    'a phone that cannot fit the line keeps the menus where they were',
    () async {
      final settings = await settingsWith(32);
      addTearDown(settings.dispose);

      expect(settings.menuSideFor(412), isNull);
    },
  );

  test('a narrowed text column puts the menus on its edges', () async {
    final settings = await settingsWith(32);
    addTearDown(settings.dispose);

    final side = settings.menuSideFor(1280);
    expect(side, isNotNull);
    expect(side, settings.paddingHorizontalFor(1280));
    expect(side, greaterThan(settings.paddingHorizontal));
  });

  test('fewer characters per line pull the menus further in', () async {
    final narrow = await settingsWith(20);
    addTearDown(narrow.dispose);
    final narrowSide = narrow.menuSideFor(1280)!;
    GetIt.instance.reset();

    final wide = await settingsWith(40);
    addTearDown(wide.dispose);
    final wideSide = wide.menuSideFor(1280)!;

    expect(narrowSide, greaterThan(wideSide));
  });
}
