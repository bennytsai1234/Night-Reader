import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/platform/app_permission_service.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/chinese/ui_language.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 按了暫停、還沒停好時的通知內文與頁面上那一列。
const String backgroundWorkPausing = '正在暫停…';

/// 按了結束、還沒停好時的通知內文與頁面上那一列。
const String backgroundWorkEnding = '正在結束…';

/// 通知欄上一件背景工作的樣子：標題是工作，內文是做到哪裡；[progress]
/// 是整件的進度（0 到 1），null 是不畫進度條（ADR 0058）。
@immutable
class BackgroundWorkStatus {
  const BackgroundWorkStatus({
    required this.title,
    required this.text,
    this.progress,
    this.pausable = false,
    this.settling = false,
  });

  /// 做到一半按了暫停或結束時的樣子：內文寫正在暫停或結束，不放按鈕。
  const BackgroundWorkStatus.settling(
    this.title, {
    required bool pausing,
    this.progress,
  }) : text = pausing ? backgroundWorkPausing : backgroundWorkEnding,
       pausable = false,
       settling = true;

  final String title;
  final String text;
  final double? progress;

  /// 通知放「暫停」：這件工作暫停後能接著做。
  final bool pausable;

  /// 正在暫停或結束：通知不放按鈕。
  final bool settling;

  /// 通知上的按鈕，照順序（`BackgroundWorkService.kt` 認這幾個名字）。
  List<String> get actions => settling
      ? const []
      : pausable
      ? const ['pause', 'end']
      : const ['end'];

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
      other.permille == permille &&
      other.pausable == pausable &&
      other.settling == settling;

  @override
  int get hashCode => Object.hash(title, text, permille, pausable, settling);
}

/// 一件使用者按了才開始的長工作：修復異常書源、單一書源的 AI 修復、
/// 校驗書源、AI 找書（ADR 0058）、放到背景的搜尋（ADR 0070）。
abstract interface class BackgroundJob {
  /// 通知上按了「暫停」、從最近使用滑掉夜讀，或系統的時間到了：停下、做到
  /// 的留著，之後按繼續接著做。
  void pauseFromSystem();

  /// 通知上按了「結束」：工作就此結束，結果留著。
  void endFromSystem();

  /// 點了通知：回到這件工作的頁面。
  void openFromNotification();
}

/// 交給 Android 的那一半：前景服務與通知（`BackgroundWorkService.kt`）。
abstract interface class BackgroundWorkPlatform {
  /// 顯示或更新通知；第一次會啟動前景服務。傳回系統肯不肯開。
  Future<bool> show(BackgroundWorkStatus status);

  /// 收掉通知、停掉前景服務。
  Future<void> hide();

  /// 系統那邊按了暫停（`pause`）、結束（`end`）或點了通知（`open`）。
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

  /// [_job] 只是佔著位置、還沒開始（[reserve]）：不送通知、通知上的按鈕不轉給
  /// 它，等它 [begin]。
  bool _reserved = false;

  /// 現在要顯示的樣子，與最後真的送給系統的樣子。
  BackgroundWorkStatus? _shown;
  BackgroundWorkStatus? _sent;

  /// 送給系統的順序：前一個送完才送下一個，收掉之後不會被晚到的更新叫回來。
  Future<void> _sending = Future<void>.value();

  /// 系統拒絕或送不過去的錯誤：連續相同的只記一次。
  String? _lastError;

  /// 有一件在跑：其他幾件的開始與繼續是灰的。
  bool get isBusy => _job != null;

  /// 開 App 時收掉上次留下的通知與前景服務：程序還在、Flutter 引擎卻重開過
  /// 時（Activity 被收掉後播放套件拆了引擎），舊的通知沒有人會收（ADR 0058）。
  /// 這時還沒有工作在跑才收。
  void clearLeftover() {
    if (_job != null) return;
    _send(() async {
      if (_job == null && _sent == null) await _platform!.hide();
    });
  }

  BackgroundJob? get current => _job;

  /// 使用者按下去、頁面推入動畫還沒播完（ADR 0018）：先佔住位置，別件開不了、
  /// 自動換源排在後面，但不送通知、不要權限，等 [begin] 才開始。已經有一件
  /// 佔著時傳回 false。佔了之後一定要 [begin] 或 [end]。
  bool reserve(BackgroundJob job) {
    if (_job != null) return false;
    _job = job;
    _reserved = true;
    _shown = null;
    notifyListeners();
    return true;
  }

  /// 開始 [job]（[reserve] 佔住的那件也從這裡開始）：已經有別件佔著時不開始，
  /// 傳回 false。要在 App 看得到時呼叫（使用者剛按下去、或推入動畫剛播完）：
  /// Android 不讓背景的 App 啟動前景服務。
  bool begin(BackgroundJob job, BackgroundWorkStatus status) {
    if (_job != null && !identical(_job, job)) return false;
    if (identical(_job, job) && !_reserved) return true;
    _job = job;
    _reserved = false;
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

  /// 排在現在那一件後面的工作：只有自動換源排隊（ADR 0069 是 0058「不做
  /// 排隊」的例外）。
  ({BackgroundJob job, BackgroundWorkStatus status, Completer<void> started})?
  _queued;

  /// 開始 [job]；有別件在跑時排在它後面，它結束時接著開始。傳回 [job] 開始
  /// 的時候。不要通知權限：自動換源是靜默的，不在刪書源時跳出權限詢問。
  ///
  /// 接著開始時通知不收、直接換成 [job] 的樣子：前景服務一直開著，夜讀那時
  /// 不在前景也接得上（Android 不讓背景的 App 啟動前景服務）。
  Future<void> beginAfterCurrent(
    BackgroundJob job,
    BackgroundWorkStatus status,
  ) {
    if (identical(_job, job)) return Future<void>.value();
    final queued = _queued;
    if (queued != null) {
      assert(identical(queued.job, job), 'only one job waits');
      return queued.started.future;
    }
    if (_job == null) {
      _job = job;
      _shown = status;
      _send(() => _flush(job));
      notifyListeners();
      return Future<void>.value();
    }
    final started = Completer<void>();
    _queued = (job: job, status: status, started: started);
    return started.future;
  }

  /// [job] 做到哪裡了：內容和上一次一樣（同一個千分位）時不送；前一次還沒
  /// 送完時連續幾次變動只送最後一次。
  void update(BackgroundJob job, BackgroundWorkStatus status) {
    if (!identical(_job, job) || _reserved || status == _shown) return;
    _shown = status;
    _send(() => _flush(job));
  }

  /// [job] 結束了（做完、停下、出錯，或佔著還沒開始就不做了）：收掉通知，
  /// 位置空出來；有排隊的（[beginAfterCurrent]）就換成它，通知不收。
  void end(BackgroundJob job) {
    if (!identical(_job, job)) return;
    final reserved = _reserved;
    _reserved = false;
    final queued = _queued;
    if (queued != null) {
      _queued = null;
      _job = queued.job;
      _shown = queued.status;
      _send(() => _flush(queued.job));
      queued.started.complete();
      notifyListeners();
      return;
    }
    _job = null;
    _shown = null;
    // 只佔著的那件沒送過通知，沒有要收的。
    if (!reserved) {
      _send(() async {
        _sent = null;
        await _platform!.hide();
      });
    }
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
    // 只佔著的那件還沒有自己的通知：晚到的按鈕是上一件的。
    if (job == null || _reserved) return;
    switch (action) {
      case 'pause':
        job.pauseFromSystem();
      case 'end':
        job.endFromSystem();
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
  Future<bool> show(BackgroundWorkStatus status) async {
    // 通知照介面語言整段轉換，內文裡的書源名稱也一起轉；按鈕的字也由這裡
    // 給（ADR 0066）。
    final simplified = languagePrefIsSimplified(
      getIt<SharedPreferences>().getString(PreferKey.language),
    );
    String ui(String text) =>
        simplified ? UiLanguageText.toSimplified(text) : text;
    return await _channel.invokeMethod<bool>('show', {
          'title': ui(status.title),
          'text': ui(status.text),
          'progress': status.permille ?? -1,
          'actions': status.actions,
          'actionLabels': {'pause': ui('暫停'), 'end': ui('結束')},
        }) ??
        false;
  }

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
