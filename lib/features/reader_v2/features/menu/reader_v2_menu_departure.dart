import 'dart:async';

import 'reader_v2_menu_controller.dart';

/// 從閱讀選單推一整頁（書籍詳情、全域系統設定）前，等上下選單與亮度條
/// 完全滑出畫面：推進、覆蓋、縮放這幾種換頁會淡掉底下的閱讀器，選單還在
/// 的話玻璃包在淡出裡，模糊要到最後一幀才糊上（ADR 0022）。
///
/// 每一次推頁是一張 [ReaderV2MenuDepartureTicket]。選了別的目的地（開了
/// 新的一張）、選單在滑出途中又被打開，或閱讀器拆掉時，舊的那張作廢：
/// 它不會等到之後另一次不相關的收起才推頁。
class ReaderV2MenuDeparture {
  ReaderV2MenuDeparture(this._menu)
    : _offScreen = !_menu.controlsVisible.value {
    _menu.controlsVisible.addListener(_onMenuChanged);
  }

  final ReaderV2MenuController _menu;

  /// 選單完全不在畫面上：沒有打開過，或收起動畫播完（[menusHidden]）。
  bool _offScreen;
  ReaderV2MenuDepartureTicket? _current;

  /// 收起選單、開一張新的推頁請求；前一張作廢。
  ReaderV2MenuDepartureTicket depart() {
    _current?._settle(false);
    final ticket = _current = ReaderV2MenuDepartureTicket._(this);
    if (_offScreen) ticket._settle(true);
    _menu.dismissControls();
    return ticket;
  }

  /// 選單的收起動畫播完、完全移出畫面（系統關閉動畫時在收起的那一幀）。
  void menusHidden() {
    _offScreen = true;
    _current?._settle(true);
  }

  void _onMenuChanged() {
    if (!_menu.controlsVisible.value) return;
    // 選單又打開（含滑出途中被叫回來）：還沒推出去的請求作廢。
    _offScreen = false;
    _current?._settle(false);
    _current = null;
  }

  void dispose() {
    _menu.controlsVisible.removeListener(_onMenuChanged);
    _current?._settle(false);
    _current = null;
  }
}

/// 一次從選單推頁的請求，見 [ReaderV2MenuDeparture]。
class ReaderV2MenuDepartureTicket {
  ReaderV2MenuDepartureTicket._(this._owner);

  final ReaderV2MenuDeparture _owner;
  final Completer<bool> _gone = Completer<bool>();
  bool _cancelled = false;

  /// 選單完全滑出時以 true 完成；這張請求作廢時以 false 完成。
  Future<bool> get menusGone => _gone.future;

  /// 現在可以推頁：這張沒有作廢、仍是最新的一張，選單也完全不在畫面上。
  /// 等完 [menusGone] 之後又做了別的非同步工作（例如寫入閱讀進度），
  /// 推頁前再看一次。
  bool get canDepart =>
      !_cancelled && identical(_owner._current, this) && _owner._offScreen;

  void _settle(bool gone) {
    if (!gone) _cancelled = true;
    if (!_gone.isCompleted) _gone.complete(gone);
  }
}
