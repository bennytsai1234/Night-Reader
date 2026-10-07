import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page_shell.dart';

/// 閱讀頁框架幾何的契約：隱藏狀態列時，正文位置只依鏡頭挖孔決定。
///
/// 從後台回到前台時，系統會先把狀態列叫回來、再由 App 收起；這段期間
/// 回報的上緣內距會在挖孔高度與狀態列高度之間跳動，正文不得跟著移動。
void main() {
  const cutout = DisplayFeature(
    bounds: Rect.fromLTRB(180, 0, 220, 30),
    type: DisplayFeatureType.cutout,
    state: DisplayFeatureState.unknown,
  );

  ReaderV2PageChromeLayout resolve({
    required double statusInset,
    required bool hideStatusBar,
    bool showHeaderInfo = false,
    List<DisplayFeature> features = const [cutout],
  }) {
    return ReaderV2PageChromeLayout.resolve(
      mediaPadding: EdgeInsets.only(top: statusInset, bottom: 20),
      displayFeatures: features,
      hideStatusBar: hideStatusBar,
      showHeaderInfo: showHeaderInfo,
      showFooterInfo: true,
      paddingTop: 8,
      paddingBottom: 8,
    );
  }

  test('hidden status bar: a transient status inset does not move text', () {
    for (final showHeaderInfo in [false, true]) {
      final hidden = resolve(
        statusInset: 30,
        hideStatusBar: true,
        showHeaderInfo: showHeaderInfo,
      );
      final transient = resolve(
        statusInset: 48,
        hideStatusBar: true,
        showHeaderInfo: showHeaderInfo,
      );
      final insetDropped = resolve(
        statusInset: 0,
        hideStatusBar: true,
        showHeaderInfo: showHeaderInfo,
      );
      expect(transient.contentTop, hidden.contentTop);
      expect(insetDropped.contentTop, hidden.contentTop);
      expect(transient.headerExtent, hidden.headerExtent);
    }
  });

  test('hidden status bar: the header clears the camera cutout', () {
    final layout = resolve(statusInset: 48, hideStatusBar: true);
    expect(layout.headerExtent, 30);
    expect(layout.contentTop, 30 + 8);
  });

  test('hidden status bar without a cutout starts at the screen edge', () {
    final layout = resolve(
      statusInset: 48,
      hideStatusBar: true,
      features: const [],
    );
    expect(layout.headerExtent, 0);
  });

  test('visible status bar still follows the system inset', () {
    final layout = resolve(statusInset: 48, hideStatusBar: false);
    expect(layout.headerExtent, 48);
    expect(layout.contentTop, 48 + 8);
  });
}
