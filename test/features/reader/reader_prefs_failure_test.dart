import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/reader/features/settings/reader_settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// 手機的偏好設定檔：[failWrites] 時寫不進去（回報失敗，或丟錯）。
class _Store extends SharedPreferencesStorePlatform {
  _Store(Map<String, Object> initial) : saved = {...initial};

  final Map<String, Object> saved;
  bool failWrites = false;
  bool throwOnFail = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (failWrites) {
      if (throwOnFail) throw StateError('disk full');
      return false;
    }
    saved[key] = value;
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => {...saved};

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async => {
    for (final entry in saved.entries)
      if (entry.key.startsWith(parameters.filter.prefix))
        entry.key: entry.value,
  };

  @override
  Future<bool> remove(String key) async {
    if (failWrites) return false;
    return saved.remove(key) != null;
  }

  @override
  Future<bool> clear() async {
    saved.clear();
    return true;
  }
}

void main() {
  late _Store store;

  setUp(() async {
    store = _Store({'flutter.${PreferKey.readerFontSize}': 18.0});
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
  });
  tearDown(GetIt.instance.reset);

  for (final throws in [false, true]) {
    test('字級寫不進去（${throws ? '丟錯' : '回報失敗'}）：還原成 18，重新載入、'
        '重開閱讀器也是 18', () async {
      final settings = ReaderSettingsController();
      await settings.loadSettings();
      expect(settings.fontSize, 18);

      store
        ..failWrites = true
        ..throwOnFail = throws;
      settings.setFontSize(20);
      await pumpEventQueue();
      expect(settings.fontSize, 18, reason: '提示「已恢復原本的值」');

      await settings.loadSettings();
      expect(settings.fontSize, 18, reason: '從更多設定回來會重讀設定');
      final reopened = ReaderSettingsController();
      await reopened.loadSettings();
      expect(reopened.fontSize, 18);
      settings.dispose();
      reopened.dispose();
    });
  }

  test('較早的寫入失敗不把較新的、寫進去的值蓋回去', () async {
    final settings = ReaderSettingsController();
    await settings.loadSettings();

    store.failWrites = true;
    settings.setFontSize(20);
    store.failWrites = false;
    settings.setFontSize(22);
    await pumpEventQueue();

    expect(settings.fontSize, 22);
    await settings.loadSettings();
    expect(settings.fontSize, 22);
    expect(store.saved['flutter.${PreferKey.readerFontSize}'], 22);
    settings.dispose();
  });
}
