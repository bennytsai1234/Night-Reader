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
///
/// 整個 App 只有一個視窗：最後露出來的閱讀器擁有它，只有擁有者的設定送進
/// 視窗。換源、從書籍詳情回來時新的閱讀頁取代舊的，舊頁在新頁套用之後才
/// 被蓋住、拆掉，那時它已經不是擁有者，不會把新頁的設定蓋回系統設定。
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

typedef _Window = ({
  bool keepScreenOn,
  double? backlight,
  ReaderV2Orientation orientation,
});

const _Window _system = (
  keepScreenOn: false,
  backlight: null,
  orientation: ReaderV2Orientation.system,
);

class _ReaderV2WindowSettingsState extends State<ReaderV2WindowSettings> {
  /// 露在畫面上的閱讀器，依露出的先後排；最後一個是擁有者。重建不改順序：
  /// 換頁動畫中舊頁還露著、跟著重建，也不會把擁有權搶回去。
  static final List<_ReaderV2WindowSettingsState> _shown = [];

  /// 最後一次送給視窗的值；沒送過時等於系統設定。
  static _Window _sent = _system;

  _Window get _wanted => (
    keepScreenOn: widget.keepScreenOn,
    backlight: ReaderV2DeviceChannel.supportsWindowBrightness
        ? widget.backlight
        : null,
    orientation: widget.orientation,
  );

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
    if (!_shown.contains(this)) _shown.add(this);
    if (identical(_shown.last, this)) _apply(_wanted);
  }

  /// 不再露出：擁有者交給前一個還露著的閱讀器，沒有就恢復系統設定。
  void _release() {
    final wasOwner = _shown.isNotEmpty && identical(_shown.last, this);
    if (!_shown.remove(this) || !wasOwner) return;
    _apply(_shown.isEmpty ? _system : _shown.last._wanted);
  }

  static void _apply(_Window next) {
    final sent = _sent;
    _sent = next;
    if (next.keepScreenOn != sent.keepScreenOn) {
      unawaited(ReaderV2DeviceChannel.setKeepScreenOn(next.keepScreenOn));
    }
    if (next.backlight != sent.backlight) {
      unawaited(ReaderV2DeviceChannel.setWindowBrightness(next.backlight));
    }
    if (next.orientation != sent.orientation) {
      unawaited(
        SystemChrome.setPreferredOrientations(next.orientation.preferred),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
