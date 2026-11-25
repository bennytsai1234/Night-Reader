import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';

/// 系統的聲音被別人拿走或拿回來時，朗讀要怎麼做。
enum AudioFocusChange {
  /// 被別的聲音打斷（來電、語音助理、別的 App 開始播）：先停，之後可能送
  /// [regained]。
  interrupted,

  /// 打斷結束、系統說可以接著播：被打斷前在播的接著播。
  regained,

  /// 停下、不自己接著播：拔掉耳機、藍牙斷線，或打斷結束時系統說不用接著播。
  lost,
}

/// 系統的音訊工作階段：要焦點、放焦點、收打斷與拔耳機的消息。真的是
/// `audio_session`（[SessionAudioFocusPlatform]），測試換成假的送平台事件。
abstract interface class AudioFocusPlatform {
  /// 要焦點：系統不給（例如通話中）回 false 或丟 [PlatformException]。
  Future<bool> activate();
  Future<void> deactivate();
  Stream<AudioInterruptionEvent> get interruptions;
  Stream<void> get becomingNoisy;
}

/// `audio_session` 的工作階段：整個 App 一份，有聲書播放器（`just_audio`）
/// 用的也是它，焦點、設定與兩種消息都是兩邊共用的。不另外設定，和有聲書
/// 一樣用 `audio_session` 預設的音樂設定（Android 要長期焦點、用途是媒體，
/// 同 Legado 的朗讀）。
class SessionAudioFocusPlatform implements AudioFocusPlatform {
  final Future<AudioSession> _session = AudioSession.instance;

  @override
  Future<bool> activate() async => (await _session).setActive(true);

  @override
  Future<void> deactivate() async => (await _session).setActive(false);

  @override
  Stream<AudioInterruptionEvent> get interruptions =>
      Stream.fromFuture(_session).asyncExpand((s) => s.interruptionEventStream);

  @override
  Stream<void> get becomingNoisy =>
      Stream.fromFuture(_session)
          .asyncExpand((s) => s.becomingNoisyEventStream);
}

/// 朗讀的音訊焦點：開始念之前要，被打斷、拔耳機時通知（[changes]）。對照
/// Legado 的 `BaseReadAloudService`：要不到就不念，暫時被拿走時停、還回來
/// 時接著念，被拿走不還與拔耳機時停。
///
/// 不放焦點：焦點是整個 App 一份，朗讀停了去放會把正在播的有聲書的焦點
/// 也放掉；別的 App 要焦點時系統自己會拿走。
class AudioFocus {
  AudioFocus({AudioFocusPlatform? platform}) : _platformOverride = platform;

  final AudioFocusPlatform? _platformOverride;
  AudioFocusPlatform? _platform;

  /// 用到才開工作階段：開 App 時不碰，測試與沒有這個外掛的平台也不碰。
  AudioFocusPlatform get _session {
    final existing = _platform;
    if (existing != null) return existing;
    final platform = _platformOverride ?? SessionAudioFocusPlatform();
    _platform = platform;
    platform.interruptions.listen(_handleInterruption, onError: _logError);
    platform.becomingNoisy.listen(
      (_) => _changes.add(AudioFocusChange.lost),
      onError: _logError,
    );
    return platform;
  }

  final StreamController<AudioFocusChange> _changes =
      StreamController<AudioFocusChange>.broadcast();

  /// 被打斷、打斷結束、拔耳機。有聲書在播時也會收到，收的一方要看自己有沒有
  /// 在播。
  Stream<AudioFocusChange> get changes => _changes.stream;

  /// 暫時被拿走（Android 的來電、語音助理），還沒還回來。`audio_session`
  /// 在 Android 上已經要過焦點就直接回「給了」、不再問系統，通話中按播放也
  /// 會說給了，所以這段時間自己回不給。
  bool _lostForNow = false;

  /// 要焦點；系統不給時回 false，不要念。
  Future<bool> request() async {
    final session = _session;
    if (_lostForNow) return false;
    try {
      if (await session.activate()) return true;
    } on MissingPluginException {
      // 這個平台沒有音訊工作階段（測試、桌面）：沒有別的聲音要讓，照念。
      return true;
    } on PlatformException catch (error) {
      // iOS 通話中要不到時是錯誤，不是 false。
      AppLog.d('AudioFocus: system refused audio focus: ${error.message}');
    }
    // Android 要不到時 `audio_session` 留著這次的請求，下次就直接回給了；
    // 放掉它，下次才會真的再問。這時 App 裡沒有人拿著焦點（有的話這次會直接
    // 給），放掉不影響有聲書。
    try {
      await session.deactivate();
    } catch (error) {
      _logError(error);
    }
    return false;
  }

  /// 照 `just_audio` 分打斷的開始與結束：Android 的暫時被拿走是 pause，
  /// 被拿走不還是 unknown（不會有結束）；iOS 的開始都是 unknown，結束時才
  /// 說要不要接著播。可以壓低音量的打斷（通知音、導航）系統自己壓低，不停。
  void _handleInterruption(AudioInterruptionEvent event) {
    if (event.type == AudioInterruptionType.duck) return;
    if (event.begin) {
      _lostForNow = event.type == AudioInterruptionType.pause;
      _changes.add(AudioFocusChange.interrupted);
      return;
    }
    _lostForNow = false;
    _changes.add(
      event.type == AudioInterruptionType.pause
          ? AudioFocusChange.regained
          : AudioFocusChange.lost,
    );
  }

  static void _logError(Object error) =>
      AppLog.e('AudioFocus: audio session error: $error', error: error);
}
