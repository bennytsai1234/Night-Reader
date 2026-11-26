import 'dart:async';

/// 讀書途中什麼時候把進度送上去（ADR 0039）：位置變了之後畫面停住至少
/// [still] 才送，另一台切過去時拿得到；同一本兩次至少隔 [spacing]，這段
/// 時間內又停住的，到時候補送一次。捲動、翻頁、換章與自動捲動途中位置一直
/// 在變，停住的時間一直重算，不送：送的時候要讀資料庫、連網，不和動畫搶
/// 同一幀（ADR 0018、0037）。
///
/// 只在前景、閱讀器開著時計（[start]）；退到背景、關掉閱讀器時 [stop]，
/// 那時由閱讀器自己存好進度再送。
class ReadingUploadPacer {
  ReadingUploadPacer({
    required this.upload,
    bool Function()? busy,
    this.still = const Duration(seconds: 8),
    this.spacing = const Duration(seconds: 30),
  }) : _busy = busy ?? _never;

  /// 存好進度再要求同步。
  final void Function() upload;

  /// 畫面還在動（跳章途中、自動捲動中）：到了停住的時間也先不送，重新數。
  final bool Function() _busy;

  final Duration still;
  final Duration spacing;

  static bool _never() => false;

  bool _running = false;

  /// 上次送了之後位置變過。
  bool _moved = false;

  /// 隔不到 [spacing] 就又停住了：到時候補送。
  bool _owed = false;

  /// 上次開始數之後畫面動過（[activity]）：到時候重新數。捲動中每一幀都
  /// 會呼叫，只記一下，不每幀重設計時器。
  bool _stirred = false;
  Timer? _stillTimer;
  Timer? _spacingTimer;

  /// 開始計：閱讀器開好、在前景。
  void start() => _running = true;

  /// 停止計：退到背景、關掉閱讀器、換目錄。上次送的時間留著，回來後照樣
  /// 隔 [spacing]。
  void stop() {
    _running = false;
    _moved = false;
    _owed = false;
    _stirred = false;
    _stillTimer?.cancel();
    _stillTimer = null;
  }

  /// 存進度時位置真的變了。
  void moved() {
    if (!_running) return;
    _moved = true;
    _restart();
  }

  /// 畫面在動（捲動中記下位置）：還有沒送的移動時，停住的時間重新數。
  void activity() {
    if (_running && _moved) _stirred = true;
  }

  void _restart() {
    _owed = false;
    _stirred = false;
    _stillTimer?.cancel();
    _stillTimer = Timer(still, _settled);
  }

  void _settled() {
    _stillTimer = null;
    if (!_running || !_moved) return;
    if (_stirred || _busy()) {
      _restart();
      return;
    }
    if (_spacingTimer != null) {
      _owed = true;
      return;
    }
    _send();
  }

  void _spaced() {
    _spacingTimer = null;
    // 補送前又動了的話，停住的時間正在重數，到時候再送。
    if (!_owed || !_running || _stillTimer != null) return;
    _owed = false;
    if (_stirred || _busy()) {
      _restart();
      return;
    }
    _send();
  }

  void _send() {
    _moved = false;
    _spacingTimer = Timer(spacing, _spaced);
    upload();
  }

  void dispose() {
    stop();
    _spacingTimer?.cancel();
    _spacingTimer = null;
  }
}
