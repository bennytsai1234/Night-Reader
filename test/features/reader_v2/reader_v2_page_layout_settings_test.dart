import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_info_item.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_prefs_repository.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_constants.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  group('page layout prefs', () {
    test('persist and reload padding, status bar and info slots', () async {
      final settings = ReaderV2SettingsController();
      settings.setPagePadding(horizontal: 8, top: 12, bottom: 6);
      settings.setHideStatusBar(true);
      const header = ReaderV2InfoSlots(
        left: ReaderV2InfoItem.bookName,
        right: ReaderV2InfoItem.time,
      );
      settings.setHeaderInfo(header);
      await pumpEventQueue();

      final snapshot = await const ReaderV2PrefsRepository().load();
      expect(snapshot.paddingHorizontal, 8);
      expect(snapshot.paddingTop, 12);
      expect(snapshot.paddingBottom, 6);
      expect(snapshot.hideStatusBar, isTrue);
      expect(snapshot.headerInfo, header);

      settings.resetPageLayout();
      await pumpEventQueue();
      expect(settings.isPageLayoutDefault, isTrue);
      settings.dispose();
    });

    test('horizontal padding feeds the reader style', () {
      final settings = ReaderV2SettingsController()
        ..setPagePadding(horizontal: 6);
      final style = settings.readStyleFor(EdgeInsets.zero);
      expect(style.paddingLeft, 6);
      expect(style.paddingRight, 6);
      settings.dispose();
    });

    test('unknown or malformed stored slots fall back safely', () {
      expect(ReaderV2InfoSlots.decode('garbage'), isNull);
      expect(
        ReaderV2InfoSlots.decode('99,6'),
        const ReaderV2InfoSlots(
          left: ReaderV2InfoItem.none,
          right: ReaderV2InfoItem.bookProgress,
        ),
      );
    });
  });

  group('page chrome layout', () {
    const media = EdgeInsets.only(top: 32, bottom: 16);

    ReaderV2PageChromeLayout resolve({
      required bool hideStatusBar,
      required bool header,
      required bool footer,
      double top = 0,
      double bottom = 0,
    }) {
      return ReaderV2PageChromeLayout.resolve(
        mediaPadding: media,
        hideStatusBar: hideStatusBar,
        showHeaderInfo: header,
        showFooterInfo: footer,
        paddingTop: top,
        paddingBottom: bottom,
      );
    }

    test('visible status bar stacks the header row below it', () {
      final layout = resolve(hideStatusBar: false, header: true, footer: true);
      expect(layout.headerRowTop, media.top);
      expect(layout.headerExtent, media.top + kReaderInfoRowHeight);
      expect(
        layout.footerExtent,
        media.bottom + kReaderPermanentInfoReservedHeight,
      );
    });

    test('hidden status bar puts the header into the cutout row', () {
      final layout = resolve(hideStatusBar: true, header: true, footer: false);
      expect(layout.headerRowTop, 0);
      expect(layout.headerExtent, media.top);
      expect(layout.footerExtent, media.bottom);
    });

    test('user paddings only move the content box', () {
      final layout = resolve(
        hideStatusBar: false,
        header: false,
        footer: true,
        top: 10,
        bottom: 4,
      );
      expect(layout.headerExtent, media.top);
      expect(layout.contentTop, media.top + 10);
      expect(layout.contentBottom, layout.footerExtent + 4);
    });
  });
}
