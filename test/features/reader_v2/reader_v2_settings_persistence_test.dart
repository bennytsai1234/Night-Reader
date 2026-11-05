import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/fonts/app_font.dart';
import 'package:night_reader/core/fonts/font_library.dart';
import 'package:night_reader/features/reader_v2/features/brightness/reader_v2_brightness.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_highlight_style.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_info_item.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_prefs_repository.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 設定保存失敗時的還原契約，以及持久化資料損毀時的回退。
///
/// 可切換寫入失敗的 repository；讀取仍走 SharedPreferences mock。
class _BrokenLoadRepository extends ReaderV2PrefsRepository {
  const _BrokenLoadRepository();

  @override
  Future<ReaderV2PrefsSnapshot> load() async => throw StateError('no prefs');
}

class _FlakyPrefsRepository extends ReaderV2PrefsRepository {
  _FlakyPrefsRepository();

  bool failWrites = false;

  @override
  Future<void> save<T>(ReaderV2Setting<T> setting, T value) async {
    final failing =
        setting.key == PreferKey.readerFontSize ||
        setting.key == PreferKey.readerPaddingHorizontal;
    if (failWrites && failing) throw StateError('disk full');
    return super.save(setting, value);
  }
}

void main() {
  Future<void> usePrefs(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final getIt = GetIt.instance;
    if (getIt.isRegistered<SharedPreferences>()) {
      getIt.unregister<SharedPreferences>();
    }
    getIt.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
  }

  setUp(() => usePrefs(<String, Object>{}));
  tearDown(GetIt.instance.reset);

  test('saving stores the value as it was when saved', () async {
    final actions = List<int>.filled(9, 0);
    final pending = ReaderV2PrefsRepository().save(
      ReaderV2Settings.clickActions,
      actions,
    );
    // 等寫入的期間清單又被改：存的照舊是呼叫當下的。
    actions[0] = 1;
    await pending;
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PreferKey.readerClickActions), '0,0,0,0,0,0,0,0,0');
  });

  test('a snapshot does not share the tap grid with the one it came from', () {
    final first = ReaderV2PrefsSnapshot.defaults();
    final second = first.withValue(ReaderV2Settings.fontSize, 24.0);
    first.clickActions[0] = 1;
    expect(second.clickActions[0], 0);
  });

  group('loading', () {
    test('a new controller already has the saved settings', () async {
      await usePrefs(<String, Object>{
        PreferKey.readerFontSize: 24.0,
        PreferKey.readerHeaderInfo: '3,6',
      });

      final settings = ReaderV2SettingsController();

      expect(settings.fontSize, 24.0);
      expect(
        settings.headerInfo,
        const ReaderV2InfoSlots(
          left: ReaderV2InfoItem.chapterTitle,
          right: ReaderV2InfoItem.bookProgress,
        ),
      );
      settings.dispose();
    });

    test('the title gap of an older version carries over in lines', () async {
      // 舊版標題下方留段距 × 8（px）：段距 0.1 → 0.8px。字號 18、行高 1.4
      // 的一行是 25.2px，換算出來不是 0.1 行的倍數，留白仍要剛好 0.8px。
      await usePrefs(<String, Object>{
        PreferKey.readerFontSize: 18.0,
        PreferKey.readerLineHeight: 1.4,
        PreferKey.readerParagraphSpacing: 0.1,
      });
      double gapPx(ReaderV2SettingsController s) => s.titleSpacing * 18 * 1.4;

      final settings = ReaderV2SettingsController();
      expect(gapPx(settings), closeTo(0.8, 1e-9));

      // 換算的值當場存下來，之後改段距不會再帶著標題間距變。
      settings.setTypography(paragraphSpacing: 0);
      await pumpEventQueue();
      final reopened = ReaderV2SettingsController();
      expect(gapPx(reopened), closeTo(0.8, 1e-9));
      settings.dispose();
      reopened.dispose();
    });

    test('settings added later open as the reader looked before', () async {
      final settings = ReaderV2SettingsController();
      final readStyle = settings.readStyleFor(
        EdgeInsets.zero,
        viewportWidth: 393,
      );

      expect(readStyle.titleSpacing, 0);
      expect(settings.keepScreenOn, isTrue);
      expect(settings.pageTurnOverlap, 1);
      expect(settings.pageTurnSpeed.duration.inMilliseconds, 260);
      expect(settings.use24HourClock, isTrue);
      expect(settings.progressFractionDigits, 1);
      expect(settings.maxDim, 0.6);
      expect(settings.edgeFade, 14);
      expect(settings.ttsFollow, isTrue);
      expect(settings.volumeKeyReversed, isFalse);
      expect(settings.hideNavigationBar, isFalse);
      expect(readStyle.bold, isFalse);
      expect(readStyle.titleBold, isTrue);
      expect(readStyle.titleCenter, isFalse);
      expect(settings.infoFontSize, 11);
      settings.dispose();
    });

    test('an unreadable saved value opens with the defaults', () async {
      await usePrefs(<String, Object>{PreferKey.readerFontSize: '24'});

      final settings = ReaderV2SettingsController();

      expect(settings.fontSize, ReaderV2PrefsSnapshot.defaults().fontSize);
      settings.dispose();
    });

    test('a failed reload keeps the current settings', () async {
      await usePrefs(<String, Object>{PreferKey.readerFontSize: 24.0});
      final settings = ReaderV2SettingsController(
        prefsRepository: const _BrokenLoadRepository(),
      );

      await settings.loadSettings();

      expect(settings.fontSize, 24.0);
      settings.dispose();
    });
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
    await usePrefs(<String, Object>{PreferKey.readerFontSize: 24.0});
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

  test('footer offset persists and reset returns to the default', () async {
    final settings = ReaderV2SettingsController();
    await settings.loadSettings();
    final defaults = ReaderV2PrefsSnapshot.defaults();
    expect(settings.footerOffset, defaults.footerOffset);

    settings.setFooterOffset(0);
    await pumpEventQueue();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble(PreferKey.readerFooterOffset), 0);
    expect((await const ReaderV2PrefsRepository().load()).footerOffset, 0);

    settings.resetPageLayout();
    await pumpEventQueue();
    expect(settings.footerOffset, defaults.footerOffset);
    expect(settings.isPageLayoutDefault, isTrue);
    settings.dispose();
  });

  test(
    'weights and title alignment persist and reset with typography',
    () async {
      final settings = ReaderV2SettingsController();
      expect(settings.isTypographyChoicesDefault, isTrue);
      settings
        ..setBodyBold(true)
        ..setTitleBold(false)
        ..setTitleCenter(true);
      await pumpEventQueue();
      final saved = await const ReaderV2PrefsRepository().load();
      expect(saved.bodyBold, isTrue);
      expect(saved.titleBold, isFalse);
      expect(saved.titleCenter, isTrue);

      final reopened = ReaderV2SettingsController();
      final style = reopened.readStyleFor(EdgeInsets.zero, viewportWidth: 393);
      expect(style.bold, isTrue);
      expect(style.titleBold, isFalse);
      expect(style.titleCenter, isTrue);
      reopened.dispose();

      settings.resetTypography();
      await pumpEventQueue();
      expect(settings.isTypographyChoicesDefault, isTrue);
      settings.dispose();
    },
  );

  test('the reader font persists, switches the text once it is downloaded '
      'and resets with typography', () async {
    // 換上假的字型庫：不連網，下載的是一小段假資料，註冊只記下字族。
    final dir = await Directory.systemTemp.createTemp('fonts');
    final served = List<int>.generate(2048, (i) => i % 241);
    final fake = FontLibrary(
      dio: Dio()..httpClientAdapter = _BytesAdapter(served),
      directoryLoader: () async => dir,
      register: (family, bytes) async {},
      fileOf: (font) => font == AppFont.system
          ? null
          : AppFontFile(
              family: 'Test${font.id}',
              fileName: '${font.id}.ttf',
              url: 'https://example.com/${font.id}.ttf',
              bytes: served.length,
              sha256: sha256.convert(served).toString(),
            ),
    );
    final previous = FontLibrary.instance;
    FontLibrary.instance = fake;
    addTearDown(() async {
      FontLibrary.instance = previous;
      await dir.delete(recursive: true);
    });

    final settings = ReaderV2SettingsController();
    var notified = 0;
    settings.addListener(() => notified++);
    expect(settings.readerFont, AppFont.system);
    expect(settings.readerFontFamily, isNull);

    settings.setReaderFont(AppFont.wenkaiTc);
    // 還沒下載好時正文照舊用系統字型。
    expect(
      settings.readStyleFor(EdgeInsets.zero, viewportWidth: 393).fontFamily,
      isNull,
    );
    expect(await fake.ensure(AppFont.wenkaiTc), isTrue);
    await pumpEventQueue();
    expect(
      (await const ReaderV2PrefsRepository().load()).readerFont,
      AppFont.wenkaiTc,
    );
    expect(settings.readerFontFamily, 'TestwenkaiTc');
    expect(
      settings.readStyleFor(EdgeInsets.zero, viewportWidth: 393).fontFamily,
      'TestwenkaiTc',
    );
    expect(notified, greaterThanOrEqualTo(2), reason: '下載好時通知重排');
    expect(settings.isTypographyChoicesDefault, isFalse);

    settings.resetTypography();
    await pumpEventQueue();
    expect(settings.readerFont, AppFont.system);
    expect(settings.readerFontFamily, isNull);
    expect(settings.isTypographyChoicesDefault, isTrue);
    settings.dispose();
  });

  test(
    'info font size persists, is clamped and resets with the page layout',
    () async {
      final settings = ReaderV2SettingsController();
      settings.setInfoFontSize(14);
      await pumpEventQueue();
      expect((await const ReaderV2PrefsRepository().load()).infoFontSize, 14);
      expect(settings.isPageLayoutDefault, isFalse);

      settings.setInfoFontSize(40);
      expect(settings.infoFontSize, ReaderV2PrefsRepository.maxInfoFontSize);
      settings.setInfoFontSize(2);
      expect(settings.infoFontSize, ReaderV2PrefsRepository.minInfoFontSize);

      settings.resetPageLayout();
      await pumpEventQueue();
      expect(settings.infoFontSize, 11);
      expect(settings.isPageLayoutDefault, isTrue);
      settings.dispose();
    },
  );

  test('reset writes the defaults even when another phone changed them '
      'while the page was open', () async {
    final settings = ReaderV2SettingsController();
    expect(settings.isTypographyChoicesDefault, isTrue);
    expect(settings.isPageLayoutDefault, isTrue);
    // 頁面開著時同步寫進另一台的值，記憶體裡還是預設。
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PreferKey.readerBodyBold, true);
    await prefs.setBool(PreferKey.readerTitleCenter, true);
    await prefs.setBool(PreferKey.readerJustifyText, false);
    await prefs.setDouble(PreferKey.readerInfoFontSize, 15);
    await prefs.setDouble(PreferKey.readerPaddingTop, 30);
    await prefs.setString(PreferKey.readerHeaderInfo, '2,1');

    settings
      ..resetTypography()
      ..resetPageLayout();
    await pumpEventQueue();

    final saved = await const ReaderV2PrefsRepository().load();
    final defaults = ReaderV2PrefsSnapshot.defaults();
    expect(saved.bodyBold, defaults.bodyBold);
    expect(saved.titleCenter, defaults.titleCenter);
    expect(saved.justifyText, defaults.justifyText);
    expect(saved.infoFontSize, defaults.infoFontSize);
    expect(saved.paddingTop, defaults.paddingTop);
    expect(saved.headerInfo, defaults.headerInfo);
    settings.dispose();
  });

  test('line chars persists and reset returns to 32', () async {
    final settings = ReaderV2SettingsController();
    await settings.loadSettings();
    expect(settings.lineChars, 32);

    settings.setLineChars(20);
    await pumpEventQueue();
    expect((await const ReaderV2PrefsRepository().load()).lineChars, 20);
    expect(settings.isPageLayoutDefault, isFalse);

    settings.resetPageLayout();
    await pumpEventQueue();
    expect(settings.lineChars, 32);
    expect(settings.isPageLayoutDefault, isTrue);
    settings.dispose();
  });

  test('an earlier left/right margin stays as the minimum margin', () async {
    await usePrefs(<String, Object>{PreferKey.readerPaddingHorizontal: 6.0});
    final settings = ReaderV2SettingsController();
    await settings.loadSettings();

    // 手機放不下 32 字：撐滿，兩側照舊是原本設的邊距。
    expect(settings.paddingHorizontalFor(393), 6);
    settings.dispose();
  });

  test(
    'justify text is on by default, persists and reaches the style',
    () async {
      final settings = ReaderV2SettingsController();
      await settings.loadSettings();
      expect(settings.justifyText, isTrue);
      expect(
        settings.readStyleFor(EdgeInsets.zero, viewportWidth: 393).justify,
        isTrue,
      );

      settings.setJustifyText(false);
      await pumpEventQueue();
      expect(
        (await const ReaderV2PrefsRepository().load()).justifyText,
        isFalse,
      );
      expect(
        settings.readStyleFor(EdgeInsets.zero, viewportWidth: 393).justify,
        isFalse,
      );
      expect(settings.isPageLayoutDefault, isFalse);

      settings.resetPageLayout();
      await pumpEventQueue();
      expect(settings.justifyText, isTrue);
      settings.dispose();
    },
  );

  test('battery info items round-trip through stored slots', () {
    const slots = ReaderV2InfoSlots(
      left: ReaderV2InfoItem.battery,
      right: ReaderV2InfoItem.batteryWithIcon,
    );
    expect(ReaderV2InfoSlots.decode(slots.encode()), slots);
    const inside = ReaderV2InfoSlots(
      left: ReaderV2InfoItem.none,
      right: ReaderV2InfoItem.batteryInside,
    );
    expect(ReaderV2InfoSlots.decode(inside.encode()), inside);
    const iconOnly = ReaderV2InfoSlots(
      left: ReaderV2InfoItem.batteryIcon,
      right: ReaderV2InfoItem.none,
    );
    expect(iconOnly.encode(), '10,0');
    expect(ReaderV2InfoSlots.decode(iconOnly.encode()), iconOnly);
    expect(
      ReaderV2InfoItem.values.where((item) => item.isBattery),
      hasLength(4),
    );
    // 碼是存下的值，選單順序換了也不能重複。
    expect(
      ReaderV2InfoItem.values.map((item) => item.code).toSet(),
      hasLength(ReaderV2InfoItem.values.length),
    );
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

  test(
    'dragging the brightness bar leaves auto and saves once on release',
    () async {
      final defaults = await const ReaderV2PrefsRepository().load();
      expect(defaults.brightnessAuto, isTrue);
      expect(defaults.volumeKeyPage, isFalse);

      final settings = ReaderV2SettingsController();
      await settings.loadSettings();
      settings.setBrightness(0.1, persist: false);
      expect(settings.brightnessAuto, isFalse);
      await pumpEventQueue();
      final mid = await const ReaderV2PrefsRepository().load();
      expect(mid.brightness, ReaderV2Brightness.defaultLevel);

      settings.setBrightness(0.2);
      settings.setVolumeKeyPage(true);
      await pumpEventQueue();
      settings.dispose();

      final reloaded = await const ReaderV2PrefsRepository().load();
      expect(reloaded.brightnessAuto, isFalse);
      expect(reloaded.brightness, closeTo(0.2, 1e-9));
      expect(reloaded.volumeKeyPage, isTrue);
    },
  );

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

/// 回一段固定位元組的假下載。
class _BytesAdapter implements HttpClientAdapter {
  _BytesAdapter(this.bytes);

  final List<int> bytes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody(
    Stream.value(Uint8List.fromList(bytes)),
    200,
    headers: {
      Headers.contentLengthHeader: ['${bytes.length}'],
    },
  );

  @override
  void close({bool force = false}) {}
}
