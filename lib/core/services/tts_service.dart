import 'dart:async';
import 'dart:convert';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reader/core/services/app_log_service.dart';
import 'package:reader/core/constant/prefer_key.dart';
import 'app_permission_service.dart';
import 'audio_handler.dart';

/// TTSService - 系統 TTS 朗讀服務（單例）
/// 對應 Android TTSReadAloudService.kt
///
/// 修復要點：
/// 1. 唯一 FlutterTts 引擎，避免與 ReaderAudioHandler 雙引擎衝突
/// 2. 完成事件透過 ReaderAudioHandler.emitEvent('onComplete') 廣播
/// 3. _audioHandler 改為 nullable，init() 失敗不影響基本 TTS 功能
class TTSService extends ChangeNotifier {
  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;

  bool _isInitialized = false;
  bool _notificationPermissionChecked = false;

  /// nullable：init() 失敗時不崩潰，只是缺少系統通知欄控制
  ReaderAudioHandler? _audioHandler;
  final FlutterTts _flutterTts = FlutterTts();
  final AppPermissionService _permissionService = AppPermissionService();

  bool _isPlaying = false;
  double _pitch = 1.0;
  double _volume = 1.0;
  double _rate = 1.0;
  String? _language;
  List<dynamic> _languages = [];
  List<String> _engines = <String>[];
  List<Map<String, String>> _voices = <Map<String, String>>[];
  String? _selectedEngine;
  Map<String, String>? _selectedVoice;

  Timer? _sleepTimer;
  int _remainingMinutes = 0;

  bool get isPlaying => _isPlaying;
  int get remainingMinutes => _remainingMinutes;
  double get pitch => _pitch;
  double get volume => _volume;
  double get rate => _rate;
  String? get language => _language;
  List<dynamic> get languages => _languages;
  List<String> get engines => List<String>.unmodifiable(_engines);
  List<Map<String, String>> get voices =>
      List<Map<String, String>>.unmodifiable(_voices);
  String? get selectedEngine => _selectedEngine;
  String? get selectedVoiceKey =>
      _selectedVoice == null ? null : voiceKeyOf(_selectedVoice!);

  String currentSpokenText = '';
  int currentWordStart = 0;
  int currentWordEnd = 0;
  int _resumeOffset = 0;

  TTSService._internal();

  /// 必須在 main.dart 的 runApp 之前呼叫
  Future<void> init() async {
    if (_isInitialized) return;

    await _ensureAudioHandler();
    await _initTts();
    _isInitialized = true;
  }

  Future<void> _ensureAudioHandler() async {
    if (_audioHandler != null) return;
    try {
      _audioHandler = await AudioService.init(
        builder: () => ReaderAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.inkpage.reader.tts',
          androidNotificationChannelName: '夜讀朗讀',
          androidNotificationOngoing: true,
        ),
      );
    } catch (e) {
      AppLog.e(
        'TTSService: AudioService.init failed (notification disabled): $e',
        error: e,
      );
    }
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
    } catch (e) {
      AppLog.e('TTSService: iOS audio category setup failed: $e', error: e);
    }

    _flutterTts.setStartHandler(() {
      _isPlaying = true;
      _audioHandler?.setPlaying(true);
      notifyListeners();
    });

    // 【關鍵修復】完成時：更新狀態並廣播事件給閱讀器端控制器
    _flutterTts.setCompletionHandler(() {
      _isPlaying = false;
      currentSpokenText = '';
      currentWordStart = -1;
      currentWordEnd = -1;
      _resumeOffset = 0;
      _audioHandler?.setPlaying(false);
      ReaderAudioHandler.emitEvent('onComplete');
      notifyListeners();
    });

    _flutterTts.setErrorHandler((msg) {
      AppLog.e('TTSService: TTS error: $msg');
      _isPlaying = false;
      _audioHandler?.setPlaying(false);
      notifyListeners();
    });

    _flutterTts.setProgressHandler((
      String text,
      int start,
      int end,
      String word,
    ) {
      final adjustedStart = start + _resumeOffset;
      final adjustedEnd = end + _resumeOffset;
      if (adjustedStart == currentWordStart && adjustedEnd == currentWordEnd) {
        return;
      }
      currentSpokenText = text;
      currentWordStart = adjustedStart;
      currentWordEnd = adjustedEnd;
      notifyListeners();
    });

    _languages = await _flutterTts.getLanguages;
    // 優先繁中 → 簡中 → 第一個可用語言
    _language =
        _languages.contains('zh-TW')
            ? 'zh-TW'
            : _languages.contains('zh-CN')
            ? 'zh-CN'
            : (_languages.isNotEmpty ? _languages.first.toString() : 'zh-CN');

    await _flutterTts.setLanguage(_language!);
    await _flutterTts.setSpeechRate(_rate);
    await _flutterTts.setPitch(_pitch);
    await _flutterTts.setVolume(_volume);
    await _loadSystemVoiceOptions();
  }

  /// 更新系統通知欄書名/作者/封面
  void updateMediaInfo({
    required String title,
    required String author,
    String? coverUrl,
  }) {
    _audioHandler?.updateMetadata(
      title: title,
      author: author,
      artUri: coverUrl,
    );
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    if (!_notificationPermissionChecked) {
      _notificationPermissionChecked = true;
      await _permissionService.requestNotificationForTts();
      await _ensureAudioHandler();
    }
    _resumeOffset = 0;
    currentSpokenText = text;
    // 重置進度位置，防止 startHandler 的 notifyListeners 用舊值觸發錯誤高亮
    currentWordStart = -1;
    currentWordEnd = -1;
    _isPlaying = true;
    _audioHandler?.setPlaying(true);
    notifyListeners();
    await _flutterTts.speak(text);
  }

  Future<void> stop() async {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _remainingMinutes = 0;
    await _flutterTts.stop();
    currentSpokenText = '';
    currentWordStart = -1;
    currentWordEnd = -1;
    _resumeOffset = 0;
    _isPlaying = false;
    _audioHandler?.setPlaying(false);
    notifyListeners();
  }

  Future<void> pause() async {
    await _flutterTts.pause();
    _isPlaying = false;
    _audioHandler?.setPlaying(false);
    notifyListeners();
  }

  Future<void> resume() async {
    if (currentSpokenText.isNotEmpty) {
      // 從暫停位置繼續，而非從段落開頭重播
      // 注意：currentWordStart 已包含 _resumeOffset，需還原為原始文本位置
      final rawStart = (currentWordStart - _resumeOffset).clamp(
        0,
        currentSpokenText.length,
      );
      final remaining = currentSpokenText.substring(rawStart);
      if (remaining.trim().isNotEmpty) {
        _resumeOffset = rawStart;
        // 樂觀更新：立即反映播放狀態，避免按鈕在 TTS 非同步啟動前顯示錯誤圖示
        _isPlaying = true;
        _audioHandler?.setPlaying(true);
        notifyListeners();
        await _flutterTts.speak(remaining);
      }
    }
  }

  void setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    _remainingMinutes = minutes;
    if (minutes > 0) {
      _sleepTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
        if (_remainingMinutes > 0) {
          _remainingMinutes--;
          notifyListeners();
        } else {
          stop();
          timer.cancel();
        }
      });
    }
    notifyListeners();
  }

  Future<void> setLanguage(String lang) async {
    _language = lang;
    await _flutterTts.setLanguage(lang);
    notifyListeners();
  }

  Future<void> setPitch(double pitch) async {
    _pitch = pitch;
    await _flutterTts.setPitch(pitch);
    notifyListeners();
  }

  Future<void> setRate(double rate) async {
    _rate = rate;
    await _flutterTts.setSpeechRate(rate);
    notifyListeners();
  }

  Future<void> setVolume(double volume) async {
    _volume = volume;
    await _flutterTts.setVolume(volume);
    notifyListeners();
  }

  Future<void> setEngine(String? engine) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = engine?.trim() ?? '';
    if (normalized.isEmpty) {
      _selectedEngine = null;
      await prefs.remove(PreferKey.ttsEngine);
    } else {
      await _flutterTts.setEngine(normalized);
      _selectedEngine = normalized;
      await prefs.setString(PreferKey.ttsEngine, normalized);
    }
    _selectedVoice = null;
    await prefs.remove(PreferKey.ttsVoice);
    _voices = await _fetchVoices();
    notifyListeners();
  }

  Future<void> setVoiceByKey(String? voiceKey) async {
    final prefs = await SharedPreferences.getInstance();
    if (voiceKey == null || voiceKey.isEmpty) {
      _selectedVoice = null;
      try {
        await _flutterTts.clearVoice();
      } catch (_) {}
      await prefs.remove(PreferKey.ttsVoice);
      notifyListeners();
      return;
    }

    final matched = _voices.cast<Map<String, String>?>().firstWhere(
      (voice) => voice != null && voiceKeyOf(voice) == voiceKey,
      orElse: () => null,
    );
    if (matched == null) return;

    await _flutterTts.setVoice(matched);
    _selectedVoice = matched;
    await prefs.setString(PreferKey.ttsVoice, jsonEncode(matched));
    notifyListeners();
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

  /// 訂閱媒體控制事件 (onComplete / onPlay / onPause / onStop / onSkipToNext…)
  Stream<String> get audioEvents => ReaderAudioHandler.eventStream;

  Future<void> _loadSystemVoiceOptions() async {
    final prefs = await SharedPreferences.getInstance();
    _engines = await _fetchEngines();

    final savedEngine = prefs.getString(PreferKey.ttsEngine)?.trim() ?? '';
    if (savedEngine.isNotEmpty && _engines.contains(savedEngine)) {
      try {
        await _flutterTts.setEngine(savedEngine);
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
            await _flutterTts.setVoice(matched);
            _selectedVoice = matched;
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
        return raw
            .whereType<Object>()
            .map((engine) => engine.toString().trim())
            .where((engine) => engine.isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {}
    return const <String>[];
  }

  Future<List<Map<String, String>>> _fetchVoices() async {
    try {
      final raw = await _flutterTts.getVoices;
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map(
              (voice) => voice.map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              ),
            )
            .toList(growable: false);
      }
    } catch (_) {}
    return const <Map<String, String>>[];
  }
}
