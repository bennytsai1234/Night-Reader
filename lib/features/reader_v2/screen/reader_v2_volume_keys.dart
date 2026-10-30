import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'reader_v2_device_channel.dart';

/// 音量鍵翻頁：音量下是下一頁、音量上是上一頁。
///
/// 按鍵由 `MainActivity.dispatchKeyEvent` 攔下：那是 App 最早拿到按鍵的
/// 地方，不看畫面上哪個元件有焦點，也不經過 Flutter 的按鍵轉送。原生端
/// 拿到按鍵當下就要決定攔不攔，所以狀態一變就把「現在攔不攔」告訴它：
/// [enabled]（設定開著、沒在朗讀）、閱讀器是最上面那一頁（沒有面板、
/// 對話框或整頁蓋著）、[blockers] 都是 false（選單、目錄收著）時攔下；
/// 其餘時候音量鍵照常調音量。
class ReaderV2VolumeKeys extends StatefulWidget {
  const ReaderV2VolumeKeys({
    super.key,
    required this.enabled,
    this.blockers = const [],
    required this.onKey,
    required this.child,
  });

  final bool enabled;
  final List<ValueListenable<bool>> blockers;

  /// 參數 true 是音量下；按住不放時每個重複事件呼叫一次。
  final ValueChanged<bool> onKey;
  final Widget child;

  @override
  State<ReaderV2VolumeKeys> createState() => _ReaderV2VolumeKeysState();
}

class _ReaderV2VolumeKeysState extends State<ReaderV2VolumeKeys>
    implements ReaderV2VolumeKeyListener {
  bool _routeCurrent = false;

  /// 最後告訴原生端的值；null 是還沒告訴過，下一次不管攔不攔都要送：
  /// 接手時原生端可能還是上一個閱讀器設的值。
  bool? _sent;

  @override
  void initState() {
    super.initState();
    for (final blocker in widget.blockers) {
      blocker.addListener(_sync);
    }
    ReaderV2DeviceChannel.volumeKeyListener = this;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeCurrent = ModalRoute.isCurrentOf(context) ?? true;
    _sync();
  }

  @override
  void didUpdateWidget(covariant ReaderV2VolumeKeys oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.blockers, widget.blockers)) {
      for (final blocker in oldWidget.blockers) {
        blocker.removeListener(_sync);
      }
      for (final blocker in widget.blockers) {
        blocker.addListener(_sync);
      }
    }
    _sync();
  }

  @override
  void dispose() {
    for (final blocker in widget.blockers) {
      blocker.removeListener(_sync);
    }
    // 換成另一個閱讀器時，新的那個先接手；舊的關掉時不能把它的設定收掉。
    if (_owner) {
      _send(false);
      ReaderV2DeviceChannel.volumeKeyListener = null;
    }
    super.dispose();
  }

  bool get _owner => identical(ReaderV2DeviceChannel.volumeKeyListener, this);

  bool get _active =>
      widget.enabled &&
      _routeCurrent &&
      !widget.blockers.any((blocker) => blocker.value);

  void _sync() {
    if (_owner) _send(_active);
  }

  void _send(bool on) {
    if (on == _sent) return;
    _sent = on;
    unawaited(ReaderV2DeviceChannel.setVolumeKeyPaging(on));
  }

  @override
  void onVolumeKey(bool forward) {
    // 狀態剛變、原生端還沒收到就攔下的那一下：吃掉但不翻頁。
    if (mounted && _active) widget.onKey(forward);
  }

  @override
  void onVolumeKeyReset() {
    _sent = false;
    _sync();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
