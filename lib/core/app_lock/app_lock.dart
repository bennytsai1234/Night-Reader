import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「解鎖才能打開」的三種（ADR 0083）。
enum AppLockMode {
  off('不鎖'),
  onLeave('離開就鎖'),
  afterFiveMinutes('離開 5 分鐘後');

  const AppLockMode(this.label);
  final String label;

  static AppLockMode fromStorage(String? value) => AppLockMode.values
      .firstWhere((mode) => mode.name == value, orElse: () => AppLockMode.off);
}

/// 鎖走到哪。
enum AppLockPhase {
  /// 沒鎖，看得到內容。
  open,

  /// 解鎖開著時離開了：先蓋上鎖的畫面，回來時照離開多久決定。
  away,

  /// 鎖住，等使用者解鎖。
  locked,

  /// 系統的辨識框開著。
  authenticating,
}

/// 鎖的畫面要畫什麼。
@immutable
class AppLockState {
  const AppLockState(this.phase, {this.promptFailed = false});

  static const AppLockState open = AppLockState(AppLockPhase.open);

  final AppLockPhase phase;

  /// 這次鎖住叫過辨識、沒有過（取消、失敗、被系統擋住）：畫面留一顆「解鎖」。
  final bool promptFailed;

  bool get covering => phase != AppLockPhase.open;

  @override
  bool operator ==(Object other) =>
      other is AppLockState &&
      other.phase == phase &&
      other.promptFailed == promptFailed;

  @override
  int get hashCode => Object.hash(phase, promptFailed);
}

/// 叫系統辨識的結果。
enum AppLockAuthResult {
  passed,

  /// 使用者取消、辨識失敗、被系統暫時擋住，或出錯：維持鎖住。
  failed,

  /// 辨識中離開了夜讀，系統把辨識框收掉：回來時再叫一次。
  interrupted,

  /// 手機沒設鎖屏密碼：夜讀不鎖，不然會打不開。
  unavailable,
}

/// 平台做的事：系統辨識、視窗這一層的蓋住與離開的原因。
abstract interface class AppLockPlatform {
  /// 手機鎖得住：系統版本夠新、設了鎖屏密碼。
  Future<bool> supported();

  Future<AppLockAuthResult> authenticate();

  /// 這次離開的原因（Android）：`own` 夜讀自己打開了別的畫面、`screenOff`
  /// 關螢幕、`away` 真的離開；iPhone 分不出來，回 null。
  Future<String?> leaveReason();

  /// 夜讀自己要打開別的 App 或系統畫面。
  Future<void> markOwnExcursion();

  Future<void> configure({required bool cover, required bool locked});

  /// 回來那一幀畫好了，拿掉系統畫的模糊（iPhone）。
  Future<void> uncover();
}

/// 離開時蓋住畫面、解鎖才能打開（ADR 0083）。設定是這台手機自己的：不同步、
/// 不進備份。
///
/// 在 `runApp` 之前 [start]：返回鍵要比 App 自己的導覽先問到這裡，鎖住時才
/// 攔得下來。
class AppLock with WidgetsBindingObserver {
  AppLock({AppLockPlatform? platform, DateTime Function()? clock})
    : _platform = platform ?? MethodChannelAppLockPlatform(),
      _clock = clock ?? DateTime.now;

  static final AppLock instance = AppLock();

  /// 「離開 5 分鐘後」的 5 分鐘。
  static const Duration grace = Duration(minutes: 5);

  /// 夜讀自己打開別的畫面後，多久內離開算是它造成的（iPhone 由這裡記）。
  static const Duration ownExcursionWindow = Duration(seconds: 3);

  final AppLockPlatform _platform;
  final DateTime Function() _clock;
  SharedPreferences? _prefs;

  final ValueNotifier<AppLockState> lockState = ValueNotifier(
    AppLockState.open,
  );

  /// 設定改了時通知（「關於夜讀」的兩列聽它）。
  final ValueNotifier<int> settingsVersion = ValueNotifier(0);

  bool _cover = false;
  AppLockMode _mode = AppLockMode.off;

  /// 這台手機鎖不鎖得住；讀到之前當作可以。
  bool _supported = true;

  DateTime? _leftAt;

  /// 離開時 Activity 被收掉、或夜讀被系統收掉：回來一定要解鎖。
  bool _mustUnlock = false;

  /// 下次回到前景時自動叫辨識（每次鎖住叫一次，不在取消後一直跳）。
  bool _promptOnResume = false;

  DateTime? _ownExcursionAt;
  Completer<void>? _opened;

  /// 現在在夜讀外面（收過 hidden、paused 或 detached，還沒回來）。
  bool _outside = false;

  /// 第幾趟出去：問離開原因的途中回來了，那一趟的結果就不用。
  int _trip = 0;

  bool get cover => _cover;
  AppLockMode get mode => _mode;

  /// 「離開時蓋住畫面」實際上開著沒（解鎖開著時一定蓋）。
  bool get coverEffective => _cover || _locking;

  bool get supported => _supported;

  bool get _locking => _mode != AppLockMode.off && _supported;

  void start(SharedPreferences prefs) {
    _prefs = prefs;
    _cover = prefs.getBool(PreferKey.appCoverOnLeave) ?? false;
    _mode = AppLockMode.fromStorage(prefs.getString(PreferKey.appLockMode));
    WidgetsBinding.instance.addObserver(this);
    if (_mode != AppLockMode.off) {
      // 開 App 一定要解鎖；第一幀就是鎖的畫面。
      _setState(const AppLockState(AppLockPhase.locked));
      _promptOnResume = true;
      WidgetsBinding.instance
        ..addPostFrameCallback((_) => _maybePrompt())
        ..ensureVisualUpdate();
    }
    unawaited(_refreshSupported());
    _configure();
  }

  /// 測試用：拿掉 [start] 註冊的監聽。
  @visibleForTesting
  void dispose() => WidgetsBinding.instance.removeObserver(this);

  /// 鎖的畫面收掉了（沒開解鎖時馬上完成）：開 App 的進場等它。
  Future<void> whenOpen() => _opened?.future ?? Future.value();

  /// 鎖的畫面淡出播完：開 App 的進場這時才開始。
  void markOpened() {
    if (lockState.value.covering) return;
    final opened = _opened;
    _opened = null;
    opened?.complete();
  }

  Future<void> setCover(bool value) async {
    _cover = value;
    await _prefs?.setBool(PreferKey.appCoverOnLeave, value);
    _settingsChanged();
  }

  /// 改「解鎖才能打開」。從不鎖改成鎖之前先辨識一次，確定解得開；沒過就不改。
  Future<bool> setMode(AppLockMode value) async {
    if (value == _mode) return true;
    if (_mode == AppLockMode.off) {
      await _refreshSupported();
      if (!_supported) return false;
      final result = await _authenticate();
      if (result != AppLockAuthResult.passed) return false;
    }
    _mode = value;
    await _prefs?.setString(PreferKey.appLockMode, value.name);
    _settingsChanged();
    return true;
  }

  /// 夜讀自己要打開別的 App 或系統畫面（外部瀏覽器、Google 登入）：回來不算
  /// 離開。Android 的系統畫面大多由 Activity 自己記，這裡補記不經過它的。
  Future<void> markOwnExcursion() async {
    _ownExcursionAt = _clock();
    try {
      await _platform.markOwnExcursion();
    } catch (error) {
      AppLog.w('解鎖：記下夜讀自己打開的畫面失敗：$error');
    }
  }

  /// 按鎖的畫面上的「解鎖」。
  Future<void> unlock() async {
    if (lockState.value.phase != AppLockPhase.locked) return;
    await _prompt();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      // 離開時依序經過 hidden、paused，回來時也從 paused 經過 hidden：
      // 只有這一趟第一次的才算離開。
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_outside) return;
        _outside = true;
        unawaited(_leave(_trip, detached: false));
      case AppLifecycleState.detached:
        _outside = true;
        unawaited(_leave(_trip, detached: true));
      case AppLifecycleState.inactive:
        _comeBack();
      case AppLifecycleState.resumed:
        _comeBack();
        _uncoverAfterFrame();
        _maybePrompt();
    }
  }

  void _comeBack() {
    if (_outside) {
      _outside = false;
      _trip++;
    }
    _returnIfAway();
  }

  /// 鎖住時返回鍵不動底下的頁面。
  @override
  Future<bool> didPopRoute() async => lockState.value.covering;

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) =>
      lockState.value.covering;

  Future<void> _leave(int trip, {required bool detached}) async {
    final phase = lockState.value.phase;
    // 辨識框（含 Android 的手機密碼畫面）開著時的離開是辨識自己造成的。
    if (phase == AppLockPhase.authenticating && !detached) return;
    if (phase == AppLockPhase.away && !detached) return;
    if (!_locking) return;
    if (!detached) {
      final reason = await _leaveReason();
      // 問原因的時候已經回來了：這一趟不算。
      if (trip != _trip) return;
      if (reason == 'own' || reason == 'screenOff') {
        AppLog.d('解鎖：離開（$reason），回來不鎖');
        return;
      }
    }
    _ownExcursionAt = null;
    if (phase == AppLockPhase.open) _leftAt = _clock();
    _mustUnlock = _mustUnlock || detached || phase != AppLockPhase.open;
    _promptOnResume = true;
    FocusManager.instance.primaryFocus?.unfocus();
    _setState(const AppLockState(AppLockPhase.away));
    AppLog.d('解鎖：離開${detached ? '（視窗收掉）' : ''}，蓋上鎖的畫面');
  }

  Future<String?> _leaveReason() async {
    final own = _ownExcursionAt;
    _ownExcursionAt = null;
    if (own != null) {
      final since = _clock().difference(own);
      if (!since.isNegative && since <= ownExcursionWindow) return 'own';
    }
    try {
      return await _platform.leaveReason();
    } catch (error) {
      AppLog.w('解鎖：讀不到離開的原因：$error');
      return null;
    }
  }

  /// 回來了：照離開多久決定要不要解鎖。
  void _returnIfAway() {
    if (lockState.value.phase != AppLockPhase.away) return;
    final left = _leftAt;
    final elapsed = left == null ? null : _clock().difference(left);
    final lock =
        _mustUnlock ||
        _mode == AppLockMode.onLeave ||
        elapsed == null ||
        elapsed.isNegative ||
        elapsed >= grace;
    _leftAt = null;
    _mustUnlock = false;
    if (lock && _locking) {
      _setState(const AppLockState(AppLockPhase.locked));
    } else {
      _promptOnResume = false;
      _setState(AppLockState.open);
      markOpened();
    }
  }

  void _maybePrompt() {
    if (!_promptOnResume) return;
    if (lockState.value.phase != AppLockPhase.locked) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _promptOnResume = false;
    unawaited(_prompt());
  }

  Future<void> _prompt() async {
    _setState(const AppLockState(AppLockPhase.authenticating));
    final result = await _authenticate();
    if (lockState.value.phase != AppLockPhase.authenticating) return;
    switch (result) {
      case AppLockAuthResult.passed:
      case AppLockAuthResult.unavailable:
        _setState(AppLockState.open);
      case AppLockAuthResult.interrupted:
        _promptOnResume = true;
        _setState(const AppLockState(AppLockPhase.locked, promptFailed: true));
        _maybePrompt();
      case AppLockAuthResult.failed:
        _setState(const AppLockState(AppLockPhase.locked, promptFailed: true));
    }
  }

  Future<AppLockAuthResult> _authenticate() async {
    try {
      return await _platform.authenticate();
    } catch (error, stack) {
      AppLog.e('解鎖：叫系統辨識失敗：$error', error: error, stackTrace: stack);
      return AppLockAuthResult.failed;
    }
  }

  Future<void> _refreshSupported() async {
    bool supported;
    try {
      supported = await _platform.supported();
    } catch (error) {
      AppLog.w('解鎖：查不到手機能不能解鎖：$error');
      supported = false;
    }
    if (supported == _supported) return;
    _supported = supported;
    // 手機的鎖屏密碼拿掉了：不鎖，免得打不開。
    if (!supported && lockState.value.covering) {
      _setState(AppLockState.open);
      markOpened();
    }
    _settingsChanged();
  }

  void _settingsChanged() {
    settingsVersion.value++;
    _configure();
  }

  void _setState(AppLockState next) {
    if (lockState.value == next) return;
    // 蓋上時就備好：解鎖之後要等鎖的畫面淡出播完（[markOpened]）才算打開。
    if (next.covering) _opened ??= Completer<void>();
    lockState.value = next;
    _configure();
  }

  void _configure() {
    unawaited(
      _platform
          .configure(cover: coverEffective, locked: lockState.value.covering)
          .catchError((Object error) {
            AppLog.w('解鎖：設定視窗失敗：$error');
          }),
    );
  }

  void _uncoverAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _platform.uncover().catchError((Object error) {
          AppLog.w('解鎖：拿掉模糊失敗：$error');
        }),
      );
    });
    WidgetsBinding.instance.scheduleFrame();
  }
}

/// 系統辨識用 local_auth，視窗這一層走 `night_reader/app_lock`
/// （Android 的 `AppPrivacyWindow`、iPhone 的 `SceneDelegate`）。
class MethodChannelAppLockPlatform implements AppLockPlatform {
  MethodChannelAppLockPlatform({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  static const MethodChannel _channel = MethodChannel('night_reader/app_lock');

  final LocalAuthentication _auth;

  bool get _mobile => Platform.isAndroid || Platform.isIOS;

  @override
  Future<bool> supported() async {
    if (!_mobile) return false;
    if (await _channel.invokeMethod<bool>('supported') != true) return false;
    return _auth.isDeviceSupported();
  }

  @override
  Future<AppLockAuthResult> authenticate() async {
    try {
      final passed = await _auth.authenticate(localizedReason: '解鎖夜讀');
      return passed ? AppLockAuthResult.passed : AppLockAuthResult.failed;
    } on LocalAuthException catch (error) {
      AppLog.d('解鎖：辨識沒過：${error.code.name}');
      return switch (error.code) {
        LocalAuthExceptionCode.noCredentialsSet =>
          AppLockAuthResult.unavailable,
        LocalAuthExceptionCode.systemCanceled => AppLockAuthResult.interrupted,
        _ => AppLockAuthResult.failed,
      };
    }
  }

  @override
  Future<String?> leaveReason() async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('leaveReason');
  }

  @override
  Future<void> markOwnExcursion() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('markOwnExcursion');
  }

  @override
  Future<void> configure({required bool cover, required bool locked}) async {
    if (!_mobile) return;
    await _channel.invokeMethod<void>('configure', {
      'cover': cover,
      'locked': locked,
    });
  }

  @override
  Future<void> uncover() async {
    if (!Platform.isIOS) return;
    await _channel.invokeMethod<void>('uncover');
  }
}
