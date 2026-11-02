import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_constants.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page_shell.dart';

/// 閱讀頁框架幾何的契約。
///
/// 隱藏狀態列時，正文位置只依挖孔高度決定：從後台回到前台時系統會先
/// 把狀態列叫回來、再由 App 收起，這段期間回報的上緣內距會跳動，正文
/// 不得跟著移動。頁尾的位置與正文到頁尾的距離都由使用者設定決定。
void main() {
  ReaderV2PageChromeLayout resolve({
    double statusInset = 30,
    double navInset = 20,
    double? cutout = 28,
    bool hideStatusBar = true,
    bool showHeaderInfo = false,
    bool showFooterInfo = true,
    double paddingTop = 0,
    double paddingBottom = 16,
    double footerOffset = 4,
    double infoFontSize = kReaderInfoFontSize,
  }) {
    return ReaderV2PageChromeLayout.resolve(
      mediaPadding: EdgeInsets.only(top: statusInset, bottom: navInset),
      topCutoutExtent: cutout,
      hideStatusBar: hideStatusBar,
      showHeaderInfo: showHeaderInfo,
      showFooterInfo: showFooterInfo,
      paddingTop: paddingTop,
      paddingBottom: paddingBottom,
      footerOffset: footerOffset,
      infoFontSize: infoFontSize,
    );
  }

  group('top', () {
    test('hidden status bar: a transient status inset does not move text', () {
      for (final showHeaderInfo in [false, true]) {
        final steady = resolve(statusInset: 30, showHeaderInfo: showHeaderInfo);
        for (final transient in [0.0, 48.0]) {
          final layout = resolve(
            statusInset: transient,
            showHeaderInfo: showHeaderInfo,
          );
          expect(layout.contentTop, steady.contentTop);
          expect(layout.headerExtent, steady.headerExtent);
        }
      }
    });

    test('hidden status bar: zero top padding sits right below the cutout', () {
      expect(resolve().contentTop, 28);
      expect(resolve(paddingTop: 6).contentTop, 28 + 6);
      expect(resolve(cutout: 0).contentTop, 0);
    });

    test('hidden status bar falls back to the system inset until known', () {
      expect(resolve(cutout: null, statusInset: 30).contentTop, 30);
    });

    test('visible status bar still follows the system inset', () {
      final layout = resolve(hideStatusBar: false, statusInset: 48);
      expect(layout.headerExtent, 48);
      expect(layout.contentTop, 48);
    });
  });

  group('bottom', () {
    test('footer offset is measured from the screen bottom', () {
      final layout = resolve(navInset: 20, footerOffset: 0);
      expect(layout.footerRowBottom, 0);
      expect(layout.footerExtent, kReaderFooterRowHeight);
    });

    test('bottom padding is the whole gap between text and footer', () {
      final tight = resolve(footerOffset: 4, paddingBottom: 0);
      expect(tight.contentBottom, 4 + kReaderFooterRowHeight);
      final loose = resolve(footerOffset: 4, paddingBottom: 12);
      expect(loose.contentBottom, tight.contentBottom + 12);
    });

    test('without a footer the gap is measured from the system inset', () {
      final layout = resolve(showFooterInfo: false, navInset: 20);
      expect(layout.contentBottom, 20 + 16);
    });
  });

  group('info font size', () {
    test('the default size keeps the rows as they were', () {
      expect(readerInfoRowHeightFor(kReaderInfoFontSize), kReaderInfoRowHeight);
      expect(
        readerFooterRowHeightFor(kReaderInfoFontSize),
        kReaderFooterRowHeight,
      );
    });

    test('a larger size makes both rows taller and pushes the text in', () {
      final small = resolve(
        hideStatusBar: false,
        showHeaderInfo: true,
        statusInset: 30,
      );
      final large = resolve(
        hideStatusBar: false,
        showHeaderInfo: true,
        statusInset: 30,
        infoFontSize: 15,
      );
      const growth = (15 - kReaderInfoFontSize) * 1.3;
      expect(large.headerExtent, closeTo(small.headerExtent + growth, 1e-9));
      expect(large.contentTop, closeTo(small.contentTop + growth, 1e-9));
      expect(large.footerExtent, closeTo(small.footerExtent + growth, 1e-9));
      expect(large.contentBottom, closeTo(small.contentBottom + growth, 1e-9));
      // 頁尾那一列的底還是在使用者設的位置。
      expect(large.footerRowBottom, small.footerRowBottom);
    });

    test('with the status bar hidden the header grows past a small cutout', () {
      final layout = resolve(
        showHeaderInfo: true,
        cutout: 20,
        infoFontSize: 16,
      );
      expect(layout.headerExtent, readerInfoRowHeightFor(16));
    });
  });
}
