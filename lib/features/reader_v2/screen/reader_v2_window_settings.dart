import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_device_channel.dart';

/// 閱讀器露在畫面上時，螢幕保持常亮、套用閱讀器自己的背光；被整頁蓋住
/// （全域設定、書籍詳情）或關掉時恢復系統設定，回到閱讀器再套用。
///
/// 「蓋住」看 [TickerMode]：Overlay 會關掉被不透明頁面完全遮住的頁面的
/// TickerMode；選單、底部面板與對話框不遮滿，不算離開閱讀器。
class ReaderV2WindowSettings extends StatefulWidget {
  const ReaderV2WindowSettings({
    super.key,
    required this.backlight,
    required this.child,
  });

  /// 視窗背光（0–1）；null 是跟隨系統。
  final double? backlight;
  final Widget child;

  @override
  State<ReaderV2WindowSettings> createState() => _ReaderV2WindowSettingsState();
}

class _ReaderV2WindowSettingsState extends State<ReaderV2WindowSettings> {
  bool _holding = false;

  /// 最後一次送出的背光；null 是跟隨系統（也是沒送過時的狀態）。
  double? _sentBacklight;

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
    _release();
    super.dispose();
  }

  void _sync() {
    if (!TickerMode.valuesOf(context).enabled) {
      _release();
      return;
    }
    if (!_holding) {
      _holding = true;
      unawaited(ReaderV2DeviceChannel.setKeepScreenOn(true));
    }
    final backlight = ReaderV2DeviceChannel.supportsWindowBrightness
        ? widget.backlight
        : null;
    if (backlight != _sentBacklight) {
      _sentBacklight = backlight;
      unawaited(ReaderV2DeviceChannel.setWindowBrightness(backlight));
    }
  }

  void _release() {
    if (!_holding) return;
    _holding = false;
    unawaited(ReaderV2DeviceChannel.setKeepScreenOn(false));
    if (_sentBacklight != null) {
      _sentBacklight = null;
      unawaited(ReaderV2DeviceChannel.setWindowBrightness(null));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
