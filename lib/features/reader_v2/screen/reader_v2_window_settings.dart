import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_orientation.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_device_channel.dart';

/// 閱讀器露在畫面上時，套用閱讀器自己的螢幕常亮、背光與螢幕方向；被整頁
/// 蓋住（全域設定、書籍詳情）或關掉時恢復系統設定，回到閱讀器再套用。
///
/// 「蓋住」看 [TickerMode]：Overlay 會關掉被不透明頁面完全遮住的頁面的
/// TickerMode；選單、底部面板與對話框不遮滿，不算離開閱讀器。
class ReaderV2WindowSettings extends StatefulWidget {
  const ReaderV2WindowSettings({
    super.key,
    required this.keepScreenOn,
    required this.backlight,
    required this.orientation,
    required this.child,
  });

  final bool keepScreenOn;

  /// 視窗背光（0–1）；null 是跟隨系統。
  final double? backlight;
  final ReaderV2Orientation orientation;
  final Widget child;

  @override
  State<ReaderV2WindowSettings> createState() => _ReaderV2WindowSettingsState();
}

class _ReaderV2WindowSettingsState extends State<ReaderV2WindowSettings> {
  /// 最後一次送出的值；沒送過時等於系統設定（不常亮、跟隨系統）。
  bool _sentKeepScreenOn = false;
  double? _sentBacklight;
  ReaderV2Orientation _sentOrientation = ReaderV2Orientation.system;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ReaderV2WindowSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _apply(
      keepScreenOn: false,
      backlight: null,
      orientation: ReaderV2Orientation.system,
    );
    super.dispose();
  }

  void _sync() {
    if (!TickerMode.valuesOf(context).enabled) {
      _apply(
        keepScreenOn: false,
        backlight: null,
        orientation: ReaderV2Orientation.system,
      );
      return;
    }
    _apply(
      keepScreenOn: widget.keepScreenOn,
      backlight: ReaderV2DeviceChannel.supportsWindowBrightness
          ? widget.backlight
          : null,
      orientation: widget.orientation,
    );
  }

  void _apply({
    required bool keepScreenOn,
    required double? backlight,
    required ReaderV2Orientation orientation,
  }) {
    if (keepScreenOn != _sentKeepScreenOn) {
      _sentKeepScreenOn = keepScreenOn;
      unawaited(ReaderV2DeviceChannel.setKeepScreenOn(keepScreenOn));
    }
    if (backlight != _sentBacklight) {
      _sentBacklight = backlight;
      unawaited(ReaderV2DeviceChannel.setWindowBrightness(backlight));
    }
    if (orientation != _sentOrientation) {
      _sentOrientation = orientation;
      unawaited(SystemChrome.setPreferredOrientations(orientation.preferred));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
