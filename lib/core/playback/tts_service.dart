import 'dart:async';
import 'dart:convert';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/sync/settings_sync.dart';

import '../platform/app_permission_service.dart';
import 'audio_focus.dart';
import 'system_playback.dart';
import 'tts_speech_coordinator.dart';

/// 念一段沒念出來的原因（[TTSService.failures]）。
enum TtsFailure {
  /// 引擎沒開好、不收這句、念的途中出錯。
  engine,

  /// 系統不給音訊焦點（例如通話中），沒有開始念。
  noAudioFocus,
}

/// TTSService - 系統 TTS 朗讀服務（單例），對應 Legado 的 TTSReadAloudService。
///
/// 整個 App 只有一個 FlutterTts 引擎。這裡只管念、朗讀參數與音訊焦點；通知
/// 欄、鎖定畫面這些系統播放資訊由念的那一方（閱讀器的朗讀）交給
/// [SystemPlayback]。
class TTSService extends ChangeNotifier {
  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;

  bool _isInitialized = false;
  Future<void>? _initializationFuture;
  bool _notificationPermissionChecked = false;

  final FlutterTts _flutterTts = FlutterTts();
  final AppPermissionService _permissionService = AppPermissionService();
  final TtsSpeechCoordinator _speechCoordinator = TtsSpeechCoordinator();

  late AudioFocus _audioFocus;
  late StreamSubscription<AudioFocusChange> _audioFocusSubscription;

  /// 下一次念之前要先要音訊焦點：每次開始念（停了之後的第一句）與被打斷
  /// 之後要一次，句與句之間不再要（每次要都是一趟主執行緒上的系統呼叫）。
  bool _needsAudioFocus = true;

  @visibleForTesting
  set audioFocus(AudioFocus focus) {
    unawaited(_audioFocusSubscription.cancel());
    _useAudioFocus(focus);
  }

  void _useAudioFocus(AudioFocus focus) {
    _audioFocus = focus;
    _needsAudioFocus = true;
    _audioFocusSubscription = focus.changes.listen((change) {
      if (change != AudioFocusChange.regained) _needsAudioFocus = true;
    });
  }

  /// 被打斷、打斷結束、拔耳機（[AudioFocusChange]）。焦點整個 App 一份，
  /// 有聲書在播時也會收到；閱讀器的朗讀只在自己念著時照它停。
  Stream<AudioFocusChange> get audioFocusChanges => _audioFocus.changes;

  bool _isPlaying = false;
  double _pitch = defaultPitch;
  double _rate = defaultRate;
  String? _language;
  List<dynamic> _languages = [];
  List<String> _engines = <String>[];
  List<Map<String, String>> _voices = <Map<String, String>>[];
  String? _selectedEngine;
  Map<String, String>? _selectedVoice;

  bool get isPlaying => _isPlaying;
  double get pitch => _pitch;
  double get rate => _rate;
  String? get language => _language;
  List<dynamic> get languages => _languages;
  List<String> get engines => List<String>.unmodifiable(_engines);

  /// 引擎的顯示名稱；系統沒提供時退回套件名稱。
  String engineLabelOf(String engine) => _engineLabels[engine] ?? engine;
  Map<String, String> _engineLabels = <String, String>{};
  List<Map<String, String>> get voices =>
      List<Map<String, String>>.unmodifiable(_voices);

  /// 依顯示名稱排序的音色。朗讀時每個字都會通知監聽者，設定頁跟著重建；
  /// 排序結果只在音色清單換掉時重算。
  List<Map<String, String>> get sortedVoices {
    if (!identical(_sortedVoicesSource, _voices)) {
      _sortedVoicesSource = _voices;
      _sortedVoices = List<Map<String, String>>.unmodifiable(
        [..._voices]
          ..sort((a, b) => voiceLabelOf(a).compareTo(voiceLabelOf(b))),
      );
    }
    return _sortedVoices;
  }

  List<Map<String, String>>? _sortedVoicesSource;
  List<Map<String, String>> _sortedVoices = const [];
  String? get selectedEngine => _selectedEngine;
  String? get selectedVoiceKey =>
      _selectedVoice == null ? null : voiceKeyOf(_selectedVoice!);

  String currentSpokenText = '';
  int currentWordStart = 0;
  int currentWordEnd = 0;

  TTSService._internal() {
    _useAudioFocus(AudioFocus());
    SettingsSync.applied.addListener(_reloadSyncedParams);
  }

  /// 同步套用了另一台的語速與音調。引擎還沒開的話不用管，開的時候會讀。
  Future<void> _reloadSyncedParams() async {
    if (!_isInitialized) return;
    await _loadSavedSpeechParams();
    notifyListeners();
    await _applyRateToEngine();
    await _applyPitchToEngine();
  }

  /// 朗讀參數的合法範圍與步進；閱讀器朗讀面板與「朗讀與語音」設定頁共用。
  ///
  /// - 語速：以使用者感受的倍速表示，1.0 = 正常速度。flutter_tts 為了
  ///   跨平台一致，把 iOS AVSpeechUtterance 的「0.5 = 正常」當作共同刻度，
  ///   Android 端再 ×2 換成引擎倍速（third_party/flutter_tts
  ///   FlutterTtsPlugin.kt）。這個換算只屬於外掛介面，由 [_engineRate]
  ///   在送出前處理；外掛上限 1.5 對應 3.0 倍速。
  /// - 音調：外掛只接受 0.5～2.0，超出範圍的值會被忽略。
  /// - 音量：0～1。
  static const double minRate = 0.2;
  static const double maxRate = 3.0;

  /// 沒調過時的語速：2 倍（維護者自己聽書用的設定，2026-11-06）。
  static const double defaultRate = 2.0;
  static const double rateStep = 0.1;
  static const double defaultPitch = 1.0;
  static const double minPitch = 0.5;
  static const double maxPitch = 2.0;
  static const double pitchStep = 0.1;

  /// 朗讀引擎的音量固定滿格，大小聲照系統的媒體音量；原本另有一個 App 內的
  /// 音量設定，和系統音量鍵是同一件事的兩個控制（ADR 0030）。
  static const double _engineVolume = 1.0;

  /// flutter_tts 的語速刻度：0.5 = 正常速度。
  static const double _flutterTtsNormalRate = 0.5;

  double get _engineRate => _rate * _flutterTtsNormalRate;

  /// 已保存語速的使用者倍速：新鍵優先；舊版鍵存的是 flutter_tts 刻度
  /// （0.5 = 正常），換算後實際朗讀速度不變。
  @visibleForTesting
  static double? resolveStoredRate({double? multiplier, double? legacyRate}) {
    if (multiplier != null) return multiplier;
    if (legacyRate == null) return null;
    return legacyRate / _flutterTtsNormalRate;
  }

  static double _clampParam(
    double value,
    double min,
    double max,
    double fallback,
  ) {
    if (!value.isFinite) return fallback;
    return value.clamp(min, max).toDouble();
  }

  /// 從偏好設定還原朗讀參數。
  ///
  /// 語速存於 `readerTtsSpeedMultiplier`（使用者倍速）。舊版鍵
  /// （`reader_tts_rate`／`ttsSpeechRate`）存的是 flutter_tts 刻度，
  /// 只在新鍵不存在時換算遷移，實際朗讀速度不變。音調以閱讀器面板的鍵
  /// 為準，`speech_pitch` 為遷移來源。
  Future<void> _loadSavedSpeechParams() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rate = resolveStoredRate(
        multiplier: prefs.getDouble(PreferKey.readerTtsSpeedMultiplier),
        legacyRate:
            prefs.getDouble(PreferKey.readerTtsRate) ??
            prefs.getDouble(PreferKey.ttsSpeechRate),
      );
      final pitch =
          prefs.getDouble(PreferKey.readerTtsPitch) ??
          prefs.getDouble(PreferKey.speechPitch);
      // 沒存過（或同步刪掉了）就回到預設，不留著記憶體裡上一次的值。
      _rate = rate == null
          ? defaultRate
          : _clampParam(rate, minRate, maxRate, defaultRate);
      _pitch = pitch == null
          ? defaultPitch
          : _clampParam(pitch, minPitch, maxPitch, defaultPitch);
      _persistedParams
        ..[PreferKey.readerTtsSpeedMultiplier] = _rate
        ..[PreferKey.readerTtsPitch] = _pitch;
    } catch (e) {
      AppLog.e('TTSService: load speech params failed: $e', error: e);
    }
  }

  /// 開朗讀引擎（系統通知欄的播放控制與 flutter_tts）。開 App 時就開始
  /// （`configureDependencies`）。進場只等播放控制（[SystemPlayback.ready]），
  /// 不等引擎：`flutter_tts` 的呼叫在外掛自己的執行緒上做
  /// （`third_party/flutter_tts/PATCHES.md` nightreader.5），系統的朗讀服務
  /// 約 1 秒後才回應，回應時不佔 Flutter 畫畫面的主執行緒。
  Future<void> init() {
    if (_isInitialized) return Future<void>.value();
    final pending = _initializationFuture;
    if (pending != null) return pending;

    final future = _initialize();
    _initializationFuture = future;
    return future;
  }

  Future<void> _initialize() async {
    await _loadSavedSpeechParams();
    notifyListeners();
    try {
      // 媒體工作階段和朗讀引擎各開各的：系統一直不回應工作階段時，朗讀照樣
      // 能念（工作階段開好時會補上播放資訊）。
      unawaited(SystemPlayback.instance.start());
      await _initTts();
      _isInitialized = true;
      // 引擎、音色清單與保存的選擇都載好了：設定頁跟著更新。
      notifyListeners();
    } catch (e, stackTrace) {
      // Android 沒有可用 TTS engine 或 platform channel 異常時，
      // 朗讀功能降級，但書架與閱讀器仍可正常啟動。
      AppLog.e(
        'TTSService initialization failed; TTS is unavailable: $e',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      _initializationFuture = null;
    }
  }

  /// iOS 的音訊類別不在這裡設：要焦點時由 `audio_session` 設成和有聲書
  /// 一樣的（[AudioFocus]），整個 App 一份，誰先播都一樣。
  Future<void> _initTts() async {
    _flutterTts.setStartHandler(() {
      _isPlaying = true;
      notifyListeners();
    });

    // 念完一段：閱讀器的朗讀聽 [completions] 接著念下一句。
    _flutterTts.setCompletionHandler(() {
      _isPlaying = false;
      currentSpokenText = '';
      currentWordStart = -1;
      currentWordEnd = -1;
      _completions.add(null);
      notifyListeners();
    });

    _flutterTts.setErrorHandler((msg) {
      AppLog.e('TTSService: TTS error: $msg');
      _reportFailure(TtsFailure.engine);
    });

    _flutterTts.setProgressHandler((
      String text,
      int start,
      int end,
      String word,
    ) {
      if (start == currentWordStart && end == currentWordEnd) return;
      currentSpokenText = text;
      currentWordStart = start;
      currentWordEnd = end;
      notifyListeners();
    });

    _languages = await _flutterTts.getLanguages;
    // 優先繁中 → 簡中 → 第一個可用語言
    _language = _languages.contains('zh-TW')
        ? 'zh-TW'
        : _languages.contains('zh-CN')
        ? 'zh-CN'
        : (_languages.isNotEmpty ? _languages.first.toString() : 'zh-CN');

    await _flutterTts.setLanguage(_language!);
    await _flutterTts.setSpeechRate(_engineRate);
    await _flutterTts.setPitch(_pitch);
    await _flutterTts.setVolume(_engineVolume);
    await _loadSystemVoiceOptions();
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _speechCoordinator.speak(
      prepare: () async {
        await init();
        if (!_isInitialized) {
          _reportFailure(TtsFailure.engine);
          return false;
        }
        if (!_notificationPermissionChecked) {
          _notificationPermissionChecked = true;
          await _permissionService.requestNotification();
          await SystemPlayback.instance.start();
        }
        // 每次開始念先要音訊焦點，要不到不念（同 Legado）：別的 App 的聲音
        // 停下或壓低，來電與拔耳機時才收得到消息。
        if (_needsAudioFocus) {
          if (!await _audioFocus.request()) {
            _reportFailure(TtsFailure.noAudioFocus);
            return false;
          }
          _needsAudioFocus = false;
        }
        return true;
      },
      speak: () async {
        currentSpokenText = text;
        // 重置進度位置，防止 startHandler 的 notifyListeners 用舊值觸發錯誤高亮
        currentWordStart = -1;
        currentWordEnd = -1;
        _isPlaying = true;
        notifyListeners();
        // 引擎連著但不收這句時回 0（`third_party/flutter_tts`）。
        if (await _flutterTts.speak(text) == 0) {
          _reportFailure(TtsFailure.engine);
        }
      },
    );
  }

  Future<void> stop() async {
    _needsAudioFocus = true;
    await _speechCoordinator.stop(
      stop: () async {
        // 引擎還沒開就沒有在念的東西；不為了停止去開它。
        if (!_isInitialized) return;
        try {
          // 保留 stop() 的 platform call 契約；沒有可用 TTS engine 時，
          // 只記錄降級，不讓清理動作冒出未處理例外。
          await _flutterTts.stop();
        } catch (e) {
          AppLog.e('TTSService: stop failed while TTS is unavailable: $e');
        }
      },
    );
    currentSpokenText = '';
    currentWordStart = -1;
    currentWordEnd = -1;
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> setLanguage(String lang) async {
    final normalized = lang.trim();
    if (normalized.isEmpty) return;

    await init();
    if (!_isInitialized) return;
    await _flutterTts.setLanguage(normalized);
    _language = normalized;
    _voices = await _fetchVoices();

    final selectedVoice = _selectedVoice;
    if (selectedVoice != null) {
      final matched = _findVoiceByKey(voiceKeyOf(selectedVoice));
      if (matched == null) {
        _selectedVoice = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(PreferKey.ttsVoice);
      } else {
        try {
          await _applyVoice(matched);
          _selectedVoice = matched;
        } catch (e) {
          _selectedVoice = null;
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(PreferKey.ttsVoice);
          AppLog.e(
            'TTSService: reapply voice after language change failed: $e',
          );
        }
      }
    }
    notifyListeners();
  }

  // 先完成 init()（含從偏好設定還原參數），再寫入新值，
  // 避免初始化晚於使用者調整而把新值覆蓋回舊值。
  Future<void> setPitch(double pitch) async {
    await init();
    _pitch = _clampParam(pitch, minPitch, maxPitch, _pitch);
    notifyListeners();
    await _applyPitchToEngine();
    await _persistParam(PreferKey.readerTtsPitch, _pitch, (value) async {
      _pitch = value;
      await _applyPitchToEngine();
    });
  }

  Future<void> setRate(double rate) async {
    await init();
    _rate = _clampParam(rate, minRate, maxRate, _rate);
    notifyListeners();
    await _applyRateToEngine();
    await _persistParam(PreferKey.readerTtsSpeedMultiplier, _rate, (
      value,
    ) async {
      _rate = value;
      await _applyRateToEngine();
    });
  }

  Future<void> _applyPitchToEngine() async {
    if (_isInitialized) await _flutterTts.setPitch(_pitch);
  }

  Future<void> _applyRateToEngine() async {
    if (_isInitialized) await _flutterTts.setSpeechRate(_engineRate);
  }

  /// 最後一次確定落地（載入或保存成功）的朗讀參數。
  final Map<String, double> _persistedParams = <String, double>{};
  final Map<String, int> _saveGenerations = <String, int>{};

  /// 保存朗讀參數。失敗時把記憶體與引擎的值還原為最後一次成功保存的值，
  /// 畫面不會停在一個重開後就消失的設定上；錯誤再往上拋給呼叫端提示。
  ///
  /// 連續步進時只有最新一次寫入的失敗會觸發還原，
  /// 較早的失敗不得把較新的值蓋回去。
  Future<void> _persistParam(
    String key,
    double value,
    Future<void> Function(double persisted) restore,
  ) async {
    final generation = (_saveGenerations[key] ?? 0) + 1;
    _saveGenerations[key] = generation;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setDouble(key, value);
      if (!saved) throw StateError('SharedPreferences rejected $key');
      _persistedParams[key] = value;
    } catch (e, stack) {
      AppLog.e('TTSService: save $key failed: $e', error: e, stackTrace: stack);
      if (_saveGenerations[key] == generation) {
        await restore(
          _persistedParams[key] ??
              (key == PreferKey.readerTtsSpeedMultiplier
                  ? defaultRate
                  : defaultPitch),
        );
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> setEngine(String? engine) async {
    await init();
    if (!_isInitialized) return;
    final prefs = await SharedPreferences.getInstance();
    final normalized = engine?.trim() ?? '';
    try {
      final targetEngine = normalized.isEmpty
          ? await _fetchDefaultEngine()
          : normalized;
      if (targetEngine != null && targetEngine.isNotEmpty) {
        await _flutterTts.setEngine(targetEngine);
        await _applyCurrentTtsSettings();
      }

      if (normalized.isEmpty) {
        _selectedEngine = null;
        await prefs.remove(PreferKey.ttsEngine);
      } else {
        _selectedEngine = normalized;
        await prefs.setString(PreferKey.ttsEngine, normalized);
      }
      _selectedVoice = null;
      await prefs.remove(PreferKey.ttsVoice);
      _voices = await _fetchVoices();
      notifyListeners();
    } catch (e) {
      notifyListeners();
      AppLog.e('TTSService: set engine failed: $e', error: e);
      rethrow;
    }
  }

  Future<void> setVoiceByKey(String? voiceKey) async {
    await init();
    if (!_isInitialized) return;
    final prefs = await SharedPreferences.getInstance();
    if (voiceKey == null || voiceKey.isEmpty) {
      try {
        final result = await _flutterTts.clearVoice();
        if (!_isSuccessfulTtsResult(result)) {
          throw StateError('系統未接受系統預設音色');
        }
      } catch (e) {
        notifyListeners();
        AppLog.e('TTSService: clear voice failed: $e', error: e);
        rethrow;
      }
      _selectedVoice = null;
      await prefs.remove(PreferKey.ttsVoice);
      notifyListeners();
      return;
    }

    final matched = _voices.cast<Map<String, String>?>().firstWhere(
      (voice) => voice != null && voiceKeyOf(voice) == voiceKey,
      orElse: () => null,
    );
    if (matched == null) return;

    try {
      await _applyVoice(matched);
    } catch (e) {
      notifyListeners();
      AppLog.e('TTSService: set voice failed: $e', error: e);
      rethrow;
    }
    _selectedVoice = matched;
    await prefs.setString(PreferKey.ttsVoice, jsonEncode(matched));
    notifyListeners();
  }

  Map<String, String>? _findVoiceByKey(String voiceKey) {
    return _voices.cast<Map<String, String>?>().firstWhere(
      (voice) => voice != null && voiceKeyOf(voice) == voiceKey,
      orElse: () => null,
    );
  }

  Future<void> _applyVoice(Map<String, String> voice) async {
    final result = await _flutterTts.setVoice(voice);
    if (!_isSuccessfulTtsResult(result)) {
      throw StateError('系統未接受音色：${voiceLabelOf(voice)}');
    }
  }

  static bool _isSuccessfulTtsResult(dynamic result) {
    return !((result is num && result <= 0) || (result is bool && !result));
  }

  String voiceKeyOf(Map<String, String> voice) {
    final identifier = voice['identifier']?.trim();
    if (identifier != null && identifier.isNotEmpty) {
      return 'id:$identifier';
    }
    final name = voice['name']?.trim() ?? '';
    final locale = voice['locale']?.trim() ?? '';
    return 'name:$name|locale:$locale';
  }

  String voiceLabelOf(Map<String, String> voice) {
    final name = voice['name']?.trim();
    final locale = voice['locale']?.trim();
    if (name == null || name.isEmpty) {
      return (locale == null || locale.isEmpty) ? '未命名語音' : locale;
    }
    return (locale == null || locale.isEmpty) ? name : '$name ($locale)';
  }

  /// 每念完一段送出一次。
  Stream<void> get completions => _completions.stream;
  final StreamController<void> _completions =
      StreamController<void>.broadcast();

  /// 念一段沒念出來時送出一次，帶著原因（[TtsFailure]）。閱讀器的朗讀聽它
  /// 停在這句，不一直停在「朗讀中」。
  Stream<TtsFailure> get failures => _failures.stream;
  final StreamController<TtsFailure> _failures =
      StreamController<TtsFailure>.broadcast();

  void _reportFailure(TtsFailure reason) {
    _isPlaying = false;
    currentSpokenText = '';
    currentWordStart = -1;
    currentWordEnd = -1;
    _failures.add(reason);
    notifyListeners();
  }

  Future<void> _loadSystemVoiceOptions() async {
    final prefs = await SharedPreferences.getInstance();
    _engines = await _fetchEngines();

    final savedEngine = prefs.getString(PreferKey.ttsEngine)?.trim() ?? '';
    if (savedEngine.isNotEmpty && _engines.contains(savedEngine)) {
      try {
        await _flutterTts.setEngine(savedEngine);
        await _applyCurrentTtsSettings();
        _selectedEngine = savedEngine;
      } catch (e) {
        AppLog.e('TTSService: set saved engine failed: $e', error: e);
        _selectedEngine = null;
      }
    }

    _voices = await _fetchVoices();
    final savedVoiceRaw = prefs.getString(PreferKey.ttsVoice);
    if (savedVoiceRaw != null && savedVoiceRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(savedVoiceRaw);
        if (decoded is Map) {
          final savedVoice = decoded.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          );
          final matched = _voices.cast<Map<String, String>?>().firstWhere(
            (voice) =>
                voice != null && voiceKeyOf(voice) == voiceKeyOf(savedVoice),
            orElse: () => null,
          );
          if (matched != null) {
            try {
              await _applyVoice(matched);
              _selectedVoice = matched;
            } catch (e) {
              AppLog.e('TTSService: restore saved voice failed: $e', error: e);
            }
          }
        }
      } catch (e) {
        AppLog.e('TTSService: restore saved voice failed: $e', error: e);
      }
    }
  }

  Future<List<String>> _fetchEngines() async {
    try {
      final raw = await _flutterTts.getEngines;
      if (raw is List) {
        final names = <String>[];
        final labels = <String, String>{};
        for (final engine in raw) {
          // 外掛回傳 {name, label}；name 給 setEngine，label 給畫面顯示。
          final name = (engine is Map ? engine['name'] : engine)
              ?.toString()
              .trim();
          if (name == null || name.isEmpty) continue;
          names.add(name);
          final label = engine is Map
              ? engine['label']?.toString().trim()
              : null;
          if (label != null && label.isNotEmpty) labels[name] = label;
        }
        _engineLabels = labels;
        return names;
      }
    } catch (_) {}
    return const <String>[];
  }

  Future<String?> _fetchDefaultEngine() async {
    try {
      final raw = await _flutterTts.getDefaultEngine;
      final engine = raw?.toString().trim() ?? '';
      return engine.isEmpty ? null : engine;
    } catch (_) {
      return null;
    }
  }

  Future<void> _applyCurrentTtsSettings() async {
    final language = _language?.trim();
    if (language != null && language.isNotEmpty) {
      await _flutterTts.setLanguage(language);
    }
    await _flutterTts.setSpeechRate(_engineRate);
    await _flutterTts.setPitch(_pitch);
    await _flutterTts.setVolume(_engineVolume);
  }

  Future<List<Map<String, String>>> _fetchVoices() async {
    try {
      final raw = await _flutterTts.getVoices;
      if (raw is List) {
        final voices = raw
            .whereType<Map>()
            .map(
              (voice) => voice.map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              ),
            )
            .toList(growable: false);
        final usableVoices = voices
            .where(TTSService._isUsableVoice)
            .toList(growable: false);
        final language = _language;
        if (language == null || language.trim().isEmpty) {
          return usableVoices;
        }
        final languageVoices = usableVoices
            .where((voice) => TTSService._voiceMatchesLanguage(voice, language))
            .toList(growable: false);
        return languageVoices.isNotEmpty ? languageVoices : usableVoices;
      }
    } catch (_) {}
    return const <Map<String, String>>[];
  }

  static bool _isUsableVoice(Map<String, String> voice) {
    final networkRequired = voice['network_required']?.trim().toLowerCase();
    if (networkRequired == '1' || networkRequired == 'true') return false;

    final features =
        voice['features']
            ?.split(RegExp(r'[\t, ]+'))
            .map((feature) => feature.trim().toLowerCase())
            .where((feature) => feature.isNotEmpty) ??
        const <String>[];
    return !features.contains('notinstalled');
  }

  static bool _voiceMatchesLanguage(
    Map<String, String> voice,
    String language,
  ) {
    final target = _normalizeLocale(language);
    final locale = _normalizeLocale(voice['locale'] ?? '');
    if (target.isEmpty || locale.isEmpty) return true;

    final targetLanguage = target.split('-').first;
    return locale == target ||
        locale == targetLanguage ||
        locale.startsWith('$targetLanguage-');
  }

  static String _normalizeLocale(String value) {
    return value.trim().replaceAll('_', '-').toLowerCase();
  }
}
