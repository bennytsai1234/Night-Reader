import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 朗讀定時的選項。偏好裡存 [storedValue]：固定選項是分鐘數，0 是關閉，
/// -1 是自訂（分鐘數另存）。
enum ReaderV2TtsSleepOption {
  off(0, '關閉'),
  minutes15(15, '15'),
  minutes30(30, '30'),
  minutes45(45, '45'),
  minutes60(60, '60'),
  minutes90(90, '90'),
  custom(-1, '自訂');

  const ReaderV2TtsSleepOption(this.storedValue, this.label);

  final int storedValue;
  final String label;

  static ReaderV2TtsSleepOption fromStored(int? value) => values.firstWhere(
    (option) => option.storedValue == value,
    orElse: () => off,
  );
}

/// 朗讀定時：選項與自訂分鐘數記在偏好裡，每次開始朗讀（包括定時暫停後
/// 按繼續）都照選項重新倒數；只算實際在念的時間，暫停時倒數跟著停。
/// 時間到由 [onExpired] 暫停朗讀。
///
/// 播放狀態由朗讀控制器透過 [sync] 告知；剩餘時間不逐秒通知，顯示的
/// 元件自己定時重讀 [remaining]，閱讀器才不會每秒重建。
class ReaderV2TtsSleepTimer extends ChangeNotifier {
  ReaderV2TtsSleepTimer({required this._onExpired, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// 自訂分鐘數的範圍；上限是最長固定選項（90 分）的兩倍。
  static const int minCustomMinutes = 1;
  static const int maxCustomMinutes = 180;

  /// 沒設定過自訂時的分鐘數，與選單定時鍵在定時關閉時用的時間相同。
  static const int defaultCustomMinutes = 30;

  final VoidCallback _onExpired;
  final DateTime Function() _now;

  ReaderV2TtsSleepOption _option = ReaderV2TtsSleepOption.off;
  int _customMinutes = defaultCustomMinutes;
  bool _active = false;
  bool _running = false;
  bool _armed = false;
  Duration _left = Duration.zero;
  DateTime? _runningSince;
  Timer? _timer;

  ReaderV2TtsSleepOption get option => _option;
  int get customMinutes => _customMinutes;

  /// 目前選項的定時長度；關閉時為 null。
  Duration? get duration => switch (_option) {
    ReaderV2TtsSleepOption.off => null,
    ReaderV2TtsSleepOption.custom => Duration(minutes: _customMinutes),
    final option => Duration(minutes: option.storedValue),
  };

  /// 倒數中的剩餘時間；沒有在倒數時為 null。
  Duration? get remaining {
    if (!_armed) return null;
    final since = _runningSince;
    final left = since == null ? _left : _left - _now().difference(since);
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _option = ReaderV2TtsSleepOption.fromStored(
      prefs.getInt(PreferKey.ttsTimer),
    );
    _customMinutes =
        (prefs.getInt(PreferKey.ttsTimerCustomMinutes) ?? defaultCustomMinutes)
            .clamp(minCustomMinutes, maxCustomMinutes);
    notifyListeners();
  }

  /// 選擇並記住定時。朗讀中或暫停中選擇時立即從頭倒數。
  Future<void> choose(ReaderV2TtsSleepOption option) async {
    _option = option;
    _restart();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PreferKey.ttsTimer, option.storedValue);
  }

  /// 設定並記住自訂分鐘數；正在用自訂時立即從頭倒數。
  Future<void> setCustomMinutes(int minutes) async {
    _customMinutes = minutes.clamp(minCustomMinutes, maxCustomMinutes);
    if (_option == ReaderV2TtsSleepOption.custom) {
      _restart();
    } else {
      notifyListeners();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PreferKey.ttsTimerCustomMinutes, _customMinutes);
  }

  /// [active]：有一段朗讀正在進行或暫停中；[running]：正在念。
  /// 停止朗讀時清掉倒數；從沒在念變成在念、且還沒有倒數時開始倒數。
  void sync({required bool active, required bool running}) {
    if (!active) {
      final changed = _active || _armed;
      _active = false;
      _running = false;
      _disarm();
      if (changed) notifyListeners();
      return;
    }
    _active = true;
    if (running == _running) return;
    _running = running;
    if (!_armed) {
      if (running) _arm();
    } else if (running) {
      _startCountdown();
    } else {
      _freeze();
    }
    notifyListeners();
  }

  void _restart() {
    _disarm();
    if (_active) _arm();
    notifyListeners();
  }

  void _arm() {
    final duration = this.duration;
    if (duration == null) return;
    _armed = true;
    _left = duration;
    if (_running) _startCountdown();
  }

  void _startCountdown() {
    _runningSince = _now();
    _timer?.cancel();
    _timer = Timer(_left, _expire);
  }

  void _freeze() {
    _left = remaining ?? Duration.zero;
    _runningSince = null;
    _timer?.cancel();
    _timer = null;
  }

  void _disarm() {
    _timer?.cancel();
    _timer = null;
    _armed = false;
    _runningSince = null;
    _left = Duration.zero;
  }

  void _expire() {
    _disarm();
    notifyListeners();
    _onExpired();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
