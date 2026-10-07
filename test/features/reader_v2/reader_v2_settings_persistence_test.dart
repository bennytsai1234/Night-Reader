import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_highlight_style.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_info_item.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_prefs_repository.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 設定保存失敗時的還原契約，以及持久化資料損毀時的回退。
///
/// 可切換寫入失敗的 repository；讀取仍走 SharedPreferences mock。
class _FlakyPrefsRepository extends ReaderV2PrefsRepository {
  _FlakyPrefsRepository();

  bool failWrites = false;

  @override
  Future<void> saveFontSize(double value) async {
    if (failWrites) throw StateError('disk full');
    return super.saveFontSize(value);
  }

  @override
  Future<void> savePaddingHorizontal(double value) async {
    if (failWrites) throw StateError('disk full');
    return super.savePaddingHorizontal(value);
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferences.getInstance();
  });

  group('save failure rollback', () {
    test('failed write restores the last persisted value', () async {
      final repository = _FlakyPrefsRepository();
      final settings = ReaderV2SettingsController(prefsRepository: repository);
      await settings.loadSettings();
      final failures = <String>[];
      settings.saveFailures.listen(failures.add);

      settings.setFontSize(24);
      await pumpEventQueue();
      expect(settings.fontSize, 24);

      repository.failWrites = true;
      settings.setFontSize(30);
      expect(settings.fontSize, 30);
      await pumpEventQueue();

      expect(settings.fontSize, 24);
      expect(failures, hasLength(1));
      settings.dispose();
    });

    test('an older failure does not overwrite a newer value', () async {
      final repository = _FlakyPrefsRepository();
      final settings = ReaderV2SettingsController(prefsRepository: repository);
      await settings.loadSettings();

      repository.failWrites = true;
      settings.setPagePadding(horizontal: 20);
      repository.failWrites = false;
      settings.setPagePadding(horizontal: 30);
      await pumpEventQueue();

      expect(settings.paddingHorizontal, 30);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(PreferKey.readerPaddingHorizontal), 30);
      settings.dispose();
    });
  });

  test('reloading a changed Chinese conversion re-converts content', () async {
    final reader = ReaderV2SettingsController();
    await reader.loadSettings();
    final generation = reader.contentSettingsGeneration;

    // 另一個 controller（閱讀偏好頁）寫入新的繁簡轉換。
    final page = ReaderV2SettingsController()..setChineseConvert(1);
    await pumpEventQueue();

    await reader.loadSettings();
    expect(reader.chineseConvert, 1);
    expect(reader.contentSettingsGeneration, greaterThan(generation));
    reader.dispose();
    page.dispose();
  });

  test('unsaved title size keeps the old body + 4 appearance', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreferKey.readerFontSize: 24.0,
    });
    final snapshot = await const ReaderV2PrefsRepository().load();
    expect(snapshot.titleFontSize, 28.0);

    final settings = ReaderV2SettingsController();
    await settings.loadSettings();
    settings.setTypography(fontSize: 30);
    expect(settings.titleFontSize, 28.0, reason: '標題字號獨立於正文');
    settings.dispose();
  });

  test('stored chapter spacing is clamped to the readable range', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreferKey.readerChapterSpacing: 99.0,
    });
    final snapshot = await const ReaderV2PrefsRepository().load();
    expect(snapshot.chapterSpacing, ReaderV2PrefsRepository.maxChapterSpacing);
  });

  test('footer offset persists and reset returns to following the system', () async {
    final settings = ReaderV2SettingsController();
    await settings.loadSettings();
    expect(settings.footerOffset, isNull);

    settings.setFooterOffset(0);
    await pumpEventQueue();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble(PreferKey.readerFooterOffset), 0);
    expect((await const ReaderV2PrefsRepository().load()).footerOffset, 0);

    settings.resetPageLayout();
    await pumpEventQueue();
    expect(settings.footerOffset, isNull);
    expect(prefs.containsKey(PreferKey.readerFooterOffset), isFalse);
    expect(settings.isPageLayoutDefault, isTrue);
    settings.dispose();
  });

  test('battery info items round-trip through stored slots', () {
    const slots = ReaderV2InfoSlots(
      left: ReaderV2InfoItem.battery,
      right: ReaderV2InfoItem.batteryWithIcon,
    );
    expect(ReaderV2InfoSlots.decode(slots.encode()), slots);
  });

  test('朗讀高亮的顏色與深淺可保存並讀回；未設定時維持原外觀', () async {
    final defaults = await const ReaderV2PrefsRepository().load();
    expect(defaults.highlightColor, ReaderV2HighlightColor.theme);
    expect(defaults.highlightStrength, ReaderV2HighlightStrength.defaultValue);

    final settings = ReaderV2SettingsController();
    await settings.loadSettings();
    settings.setHighlightColor(ReaderV2HighlightColor.blue);
    settings.setHighlightStrength(0.4);
    await pumpEventQueue();
    settings.dispose();

    final reloaded = await const ReaderV2PrefsRepository().load();
    expect(reloaded.highlightColor, ReaderV2HighlightColor.blue);
    expect(reloaded.highlightStrength, closeTo(0.4, 1e-9));
  });

  test('損毀或超出範圍的高亮設定回退到安全值', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreferKey.readerHighlightColor: 'rainbow',
      PreferKey.readerHighlightStrength: 5.0,
    });
    final snapshot = await const ReaderV2PrefsRepository().load();
    expect(snapshot.highlightColor, ReaderV2HighlightColor.theme);
    expect(snapshot.highlightStrength, ReaderV2HighlightStrength.max);
  });

  test('malformed stored info slots fall back safely', () {
    expect(ReaderV2InfoSlots.decode('garbage'), isNull);
    expect(
      ReaderV2InfoSlots.decode('99,6'),
      const ReaderV2InfoSlots(
        left: ReaderV2InfoItem.none,
        right: ReaderV2InfoItem.bookProgress,
      ),
    );
  });
}
