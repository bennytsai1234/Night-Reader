import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:night_reader/features/reader/features/brightness/reader_brightness_bar.dart';
import 'package:night_reader/features/reader/features/menu/reader_menu_entrance.dart';
import 'package:night_reader/features/reader/features/menu/reader_menu_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/popups/popup_routes.dart';

/// 閱讀選單的擺放（`docs/design/reader.md`「閱讀器選單」）：上下選單貼齊
/// 畫面上下緣，亮度條夾在兩者之間、從左滑入。文字閱讀器與漫畫閱讀器共用。
///
/// [top]、[bottom] 自己帶進出場；亮度條的進出場與選單配色在這裡包上，
/// 比上下選單晚一點出發，三塊錯開。
class ReaderMenuLayout extends StatelessWidget {
  const ReaderMenuLayout({
    super.key,
    required this.controlsVisible,
    required this.top,
    required this.bottom,
    this.brightness,
    required this.brightnessSide,
  });

  final ValueListenable<bool> controlsVisible;
  final Widget top;
  final Widget bottom;

  /// 亮度條；null 時不畫（手機不能調閱讀器亮度）。
  final Widget? brightness;

  /// 亮度條離畫面左邊多遠。
  final double brightnessSide;

  @override
  Widget build(BuildContext context) => CustomMultiChildLayout(
    delegate: _MenuLayoutDelegate(brightnessSide: brightnessSide),
    children: [
      LayoutId(id: _MenuSlot.top, child: top),
      LayoutId(id: _MenuSlot.bottom, child: bottom),
      if (brightness case final control?)
        LayoutId(
          id: _MenuSlot.brightness,
          child: ReaderMenuEntrance(
            visible: controlsVisible,
            edge: AxisDirection.left,
            // 滑出畫面的距離照它離左邊多遠。
            gap: brightnessSide,
            delay: AppMotion.readerMenuStagger,
            child: DerivedTheme(
              derive: ReaderMenuStyle.menuThemeOf,
              child: control,
            ),
          ),
        ),
    ],
  );
}

enum _MenuSlot { top, bottom, brightness }

/// 上下選單貼齊畫面上下緣；亮度條離左邊 [brightnessSide]，撐滿兩者之間的
/// 空間、上下各留 [AppSpacing.xl]，在上下選單之間置中。空間不夠時亮度條
/// 自己不畫（[ReaderBrightnessBar.minHeight]）。
class _MenuLayoutDelegate extends MultiChildLayoutDelegate {
  _MenuLayoutDelegate({required this.brightnessSide});

  final double brightnessSide;

  @override
  void performLayout(Size size) {
    final loose = BoxConstraints.loose(size).copyWith(minWidth: size.width);
    final top = layoutChild(_MenuSlot.top, loose);
    positionChild(_MenuSlot.top, Offset.zero);
    final bottom = layoutChild(_MenuSlot.bottom, loose);
    positionChild(_MenuSlot.bottom, Offset(0, size.height - bottom.height));
    if (!hasChild(_MenuSlot.brightness)) return;
    final available =
        size.height - top.height - bottom.height - AppSpacing.xl * 2;
    layoutChild(
      _MenuSlot.brightness,
      BoxConstraints.tightFor(
        width: AppGlass.buttonSize,
        height: available < 0 ? 0 : available,
      ),
    );
    positionChild(
      _MenuSlot.brightness,
      Offset(brightnessSide, top.height + AppSpacing.xl),
    );
  }

  @override
  bool shouldRelayout(_MenuLayoutDelegate oldDelegate) =>
      oldDelegate.brightnessSide != brightnessSide;
}
