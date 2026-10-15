import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 朗讀定時的選項。偏好裡存 [storedValue]：分鐘數，0 是關閉，-1 是念完本章。
enum ReaderV2TtsSleepOption {
  off(0, '關閉'),
  minutes15(15, '15'),
  minutes30(30, '30'),
  minutes45(45, '45'),
  minutes60(60, '60'),
  minutes90(90, '90'),
  chapterEnd(-1, '章末');

  const ReaderV2TtsSleepOption(this.storedValue, this.label);

  final int storedValue;
  final String label;

  Duration? get duration =>
      storedValue > 0 ? Duration(minutes: storedValue) : null;

  static ReaderV2TtsSleepOption fromStored(int? value) => values.firstWhere(
    (option) => option.storedValue == value,
    orElse: () => off,
  );
}

/// 朗讀定時：選項記在偏好裡，每次開始朗讀（包括定時暫停後按繼續）都照
/// 選項重新倒數；只算實際在念的時間，暫停時倒數跟著停。時間到由
/// [onExpired] 暫停朗讀；「念完本章」由朗讀控制器在章節交界詢問
/// [takeChapterEnd]。
///
/// 播放狀態由朗讀控制器透過 [sync] 告知；剩餘時間不逐秒通知，顯示的
/// 元件自己定時重讀 [remaining]，閱讀器才不會每秒重建。
class ReaderV2TtsSleepTimer extends ChangeNotifier {
  ReaderV2TtsSleepTimer({required this._onExpired, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final VoidCallback _onExpired;
  final DateTime Function() _now;

  ReaderV2TtsSleepOption _option = ReaderV2TtsSleepOption.off;
  bool _active = false;
  bool _running = false;
  bool _armed = false;
  Duration _left = Duration.zero;
  DateTime? _runningSince;
  Timer? _timer;

  ReaderV2TtsSleepOption get option => _option;

  /// 這次朗讀會在念完本章時暫停。
  bool get pausesAtChapterEnd =>
      _armed && _option == ReaderV2TtsSleepOption.chapterEnd;

  /// 倒數中的剩餘時間；沒有在倒數時為 null。
  Duration? get remaining {
    if (!_armed || _option.duration == null) return null;
    final since = _runningSince;
    final left = since == null ? _left : _left - _now().difference(since);
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _option = ReaderV2TtsSleepOption.fromStored(
      prefs.getInt(PreferKey.ttsTimer),
    );
    notifyListeners();
  }

  /// 選擇並記住定時。朗讀中或暫停中選擇時立即從頭倒數。
  Future<void> choose(ReaderV2TtsSleepOption option) async {
    _option = option;
    _disarm();
    if (_active) _arm();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PreferKey.ttsTimer, option.storedValue);
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

  /// 章節交界：要在本章結束時暫停就回傳 true 並結束這次定時。
  bool takeChapterEnd() {
    if (!pausesAtChapterEnd) return false;
    _disarm();
    notifyListeners();
    return true;
  }

  void _arm() {
    if (_option == ReaderV2TtsSleepOption.off) return;
    _armed = true;
    _left = _option.duration ?? Duration.zero;
    if (_running) _startCountdown();
  }

  void _startCountdown() {
    if (_option.duration == null) return;
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
