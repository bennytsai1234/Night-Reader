import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/app_permission_service.dart';

/// 通知欄上一件背景工作的樣子：標題是工作，內文是做到哪裡；[progress]
/// 是整件的進度（0 到 1），null 是不畫進度條（ADR 0058）。
@immutable
class BackgroundWorkStatus {
  const BackgroundWorkStatus({
    required this.title,
    required this.text,
    this.progress,
  });

  final String title;
  final String text;
  final double? progress;

  /// 交給系統的進度：千分之幾。進度條畫不出比這更細的差別，同一個千分位
  /// 不重送。
  int? get permille => progress == null
      ? null
      : (progress!.clamp(0.0, 1.0) * BackgroundWork.progressMax).round();

  @override
  bool operator ==(Object other) =>
      other is BackgroundWorkStatus &&
      other.title == title &&
      other.text == text &&
      other.permille == permille;

  @override
  int get hashCode => Object.hash(title, text, permille);
}

/// 一件使用者按了才開始的長工作：修復異常書源、單一書源的 AI 修復、
/// 校驗書源（ADR 0058）。
abstract interface class BackgroundJob {
  /// 通知上按了「停止」、從最近使用滑掉夜讀，或系統的時間到了。
  void stopFromSystem();

  /// 點了通知：回到這件工作的頁面。
  void openFromNotification();
}

/// 交給 Android 的那一半：前景服務與通知（`BackgroundWorkService.kt`）。
abstract interface class BackgroundWorkPlatform {
  /// 顯示或更新通知；第一次會啟動前景服務。傳回系統肯不肯開。
  Future<bool> show(BackgroundWorkStatus status);

  /// 收掉通知、停掉前景服務。
  Future<void> hide();

  /// 系統那邊按了停止（`stop`）或點了通知（`open`）。
  set onAction(void Function(String action)? handler);
}

/// 背景工作：一次只跑一件；跑的時候前景服務讓系統別凍結夜讀、關螢幕時
/// 照跑，通知欄顯示進度，不跳出、不出聲（ADR 0058）。
///
/// 工作本身照舊在主 isolate 跑；這裡只管位置與通知。
class BackgroundWork extends ChangeNotifier {
  BackgroundWork({BackgroundWorkPlatform? platform, this._requestPermission})
    : _platform = platform ?? _defaultPlatform() {
    _platform?.onAction = _handleAction;
  }

  static final BackgroundWork instance = BackgroundWork(
    requestPermission: () => AppPermissionService().requestNotification(),
  );

  /// 進度條的總格數，和 `BackgroundWorkService.kt` 一致。
  static const int progressMax = 1000;

  /// 只有 Android 有前景服務；iOS 不讓 App 在背景跑這種工作，測試在電腦上跑。
  static BackgroundWorkPlatform? _defaultPlatform() =>
      !kIsWeb && Platform.isAndroid ? _MethodChannelPlatform() : null;

  final BackgroundWorkPlatform? _platform;

  /// 第一次開始工作時要通知權限（原本只在第一次朗讀時要）。
  Future<void> Function()? _requestPermission;

  BackgroundJob? _job;

  /// 現在要顯示的樣子，與最後真的送給系統的樣子。
  BackgroundWorkStatus? _shown;
  BackgroundWorkStatus? _sent;

  /// 送給系統的順序：前一個送完才送下一個，收掉之後不會被晚到的更新叫回來。
  Future<void> _sending = Future<void>.value();

  /// 系統拒絕或送不過去的錯誤：連續相同的只記一次。
  String? _lastError;

  /// 有一件在跑：另外兩件的入口是灰的。
  bool get isBusy => _job != null;

  BackgroundJob? get current => _job;

  /// 開始 [job]：已經有一件在跑時不開始，傳回 false。要在 App 看得到時
  /// 呼叫（使用者剛按下去）：Android 不讓背景的 App 啟動前景服務。
  bool begin(BackgroundJob job, BackgroundWorkStatus status) {
    if (_job != null) return identical(_job, job);
    _job = job;
    _shown = status;
    final request = _requestPermission;
    _requestPermission = null;
    _send(() async {
      if (request != null) {
        try {
          await request();
        } catch (error) {
          _log('notification permission', error);
        }
      }
      await _flush(job);
    });
    notifyListeners();
    return true;
  }

  /// [job] 做到哪裡了：內容和上一次一樣（同一個千分位）時不送；前一次還沒
  /// 送完時連續幾次變動只送最後一次。
  void update(BackgroundJob job, BackgroundWorkStatus status) {
    if (!identical(_job, job) || status == _shown) return;
    _shown = status;
    _send(() => _flush(job));
  }

  /// [job] 結束了（做完、停下或出錯）：收掉通知，位置空出來。
  void end(BackgroundJob job) {
    if (!identical(_job, job)) return;
    _job = null;
    _shown = null;
    _send(() async {
      _sent = null;
      await _platform!.hide();
    });
    notifyListeners();
  }

  /// 送出 [job] 現在的樣子；它已經結束、或和上次送的一樣就不送。
  Future<void> _flush(BackgroundJob job) async {
    final shown = _shown;
    if (!identical(_job, job) || shown == null || shown == _sent) return;
    final first = _sent == null;
    _sent = shown;
    final started = await _platform!.show(shown);
    if (first && !started) _log('show', 'the system did not start the service');
  }

  void _send(Future<void> Function() action) {
    if (_platform == null) return;
    _sending = _sending.then((_) async {
      try {
        await action();
      } catch (error) {
        _log('channel', error);
      }
    });
  }

  void _handleAction(String action) {
    final job = _job;
    if (job == null) return;
    switch (action) {
      case 'stop':
        job.stopFromSystem();
      case 'open':
        job.openFromNotification();
    }
  }

  void _log(String what, Object error) {
    final text = '$what: $error';
    if (text == _lastError) return;
    _lastError = text;
    AppLog.e('BackgroundWork: $text', error: error);
  }
}

class _MethodChannelPlatform implements BackgroundWorkPlatform {
  static const MethodChannel _channel = MethodChannel(
    'night_reader/background_work',
  );

  @override
  Future<bool> show(BackgroundWorkStatus status) async =>
      await _channel.invokeMethod<bool>('show', {
        'title': status.title,
        'text': status.text,
        'progress': status.permille ?? -1,
      }) ??
      false;

  @override
  Future<void> hide() => _channel.invokeMethod<void>('hide');

  @override
  set onAction(void Function(String action)? handler) {
    _channel.setMethodCallHandler(
      handler == null
          ? null
          : (call) async {
              handler(call.method);
              return null;
            },
    );
  }
}
