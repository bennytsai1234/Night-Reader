import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/services/tts_service.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_sheet.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_segmenter.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class ReaderV2TtsEngine extends ChangeNotifier {
  bool get isPlaying;
  double get rate;
  double get pitch;
  String? get language;
  String get currentSpokenText;
  Stream<String> get events;

  Future<void> speak(String text);
  Future<void> stop();
  Future<void> pause();
  Future<void> resume();
  Future<void> setRate(double value);
  Future<void> setPitch(double value);
  Future<void> setLanguage(String value);
}

class ReaderV2SystemTtsEngine extends ReaderV2TtsEngine {
  ReaderV2SystemTtsEngine({TTSService? service})
    : _service = service ?? TTSService() {
    _service.addListener(notifyListeners);
  }

  final TTSService _service;

  @override
  bool get isPlaying => _service.isPlaying;

  @override
  double get rate => _service.rate;

  @override
  double get pitch => _service.pitch;

  @override
  String? get language => _service.language;

  @override
  String get currentSpokenText => _service.currentSpokenText;

  @override
  Stream<String> get events => _service.audioEvents;

  @override
  Future<void> speak(String text) => _service.speak(text);

  @override
  Future<void> stop() => _service.stop();

  @override
  Future<void> pause() => _service.pause();

  @override
  Future<void> resume() => _service.resume();

  @override
  Future<void> setRate(double value) => _service.setRate(value);

  @override
  Future<void> setPitch(double value) => _service.setPitch(value);

  @override
  Future<void> setLanguage(String value) => _service.setLanguage(value);

  @override
  void dispose() {
    _service.removeListener(notifyListeners);
    super.dispose();
  }
}

class ReaderV2TtsController extends ChangeNotifier
    implements ReaderV2TtsSheetController {
  ReaderV2TtsController({required this.runtime, ReaderV2TtsEngine? tts})
    : _tts = tts ?? ReaderV2SystemTtsEngine(),
      _ownsTtsEngine = tts == null {
    _observedContentGeneration = runtime.state.contentGeneration;
    runtime.addListener(_handleRuntimeChanged);
    _tts.addListener(_handleTtsChanged);
    _eventSubscription = _tts.events.listen(_handleTtsEvent);
  }

  final ReaderV2Runtime runtime;
  final ReaderV2TtsEngine _tts;
  final bool _ownsTtsEngine;
  late final StreamSubscription<String> _eventSubscription;
  ReaderV2Location? _speechStartLocation;
  List<ReaderV2TtsSegment> _segments = const <ReaderV2TtsSegment>[];
  int _segmentIndex = -1;
  int _speechGeneration = 0;
  late int _observedContentGeneration;
  bool _handlingCompletion = false;
  bool _disposed = false;

  @override
  bool get isPlaying => _tts.isPlaying;

  @override
  bool get isPaused => !_tts.isPlaying && _tts.currentSpokenText.isNotEmpty;

  @override
  double get rate => _tts.rate;

  @override
  double get pitch => _tts.pitch;

  String? get language => _tts.language;
  ReaderV2Location? get speechStartLocation => _speechStartLocation;

  /// 高亮目前朗讀的整個句段。
  ReaderV2TtsHighlight? get currentHighlight {
    final segment = _currentSegment;
    if (segment == null) return null;
    return ReaderV2TtsHighlight(
      chapterIndex: segment.chapterIndex,
      sentenceStart: segment.startCharOffset,
      sentenceEnd: segment.endCharOffset,
    );
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLanguage = prefs.getString(PreferKey.readerTtsLanguage);
    if (savedLanguage != null && savedLanguage.isNotEmpty) {
      await _tts.setLanguage(savedLanguage);
    }
    notifyListeners();
  }

  @override
  Future<void> toggle() async {
    if (_tts.isPlaying) {
      await _tts.pause();
      return;
    }
    if (isPaused) {
      await _tts.resume();
      return;
    }
    await startFromVisibleLocation();
  }

  Future<void> startFromVisibleLocation() async {
    final generation = ++_speechGeneration;
    final location = runtime.state.visibleLocation.normalized(
      chapterCount: runtime.chapterCount,
    );
    await _speakFrom(location, generation: generation);
  }

  /// 使用者手動跳到別處：正在朗讀就從新位置接著念；暫停中則丟掉舊句，
  /// 下次播放從新位置開始。
  Future<void> followManualJump() async {
    final wasPlaying = _tts.isPlaying;
    if (!wasPlaying &&
        _currentSegment == null &&
        _tts.currentSpokenText.isEmpty) {
      return;
    }
    await stop();
    if (wasPlaying) await startFromVisibleLocation();
  }

  /// 從 [location] 開始朗讀；這一章已沒有可念的內容就往後找下一個有正文的
  /// 章節。章節載入失敗或念到書尾時停下並告知，不默默跳過。
  Future<void> _speakFrom(
    ReaderV2Location location, {
    required int generation,
  }) async {
    var next = location;
    while (_isActiveGeneration(generation)) {
      switch (await _startFromLocation(next, generation: generation)) {
        case _SpeechStart.started:
        case _SpeechStart.cancelled:
          return;
        case _SpeechStart.unavailable:
          _finishSpeech(
            generation,
            notice: '第 ${next.chapterIndex + 1} 章無法載入，朗讀已停止',
          );
          return;
        case _SpeechStart.empty:
          final chapterIndex = next.chapterIndex + 1;
          if (chapterIndex >= runtime.chapterCount) {
            _finishSpeech(generation, notice: '已朗讀到書尾');
            return;
          }
          next = ReaderV2Location(
            chapterIndex: chapterIndex,
            charOffset: 0,
            visualOffsetPx: runtime.state.layoutSpec.anchorOffsetInViewport,
          );
      }
    }
  }

  Future<_SpeechStart> _startFromLocation(
    ReaderV2Location location, {
    required int generation,
  }) async {
    final ReaderV2Content content;
    try {
      content = await runtime.loadContentForTts(location);
    } catch (_) {
      return _isActiveGeneration(generation)
          ? _SpeechStart.unavailable
          : _SpeechStart.cancelled;
    }
    if (!_isActiveGeneration(generation)) return _SpeechStart.cancelled;
    final safeOffset = location.charOffset
        .clamp(0, content.displayText.length)
        .toInt();
    final segments = _segmentsFor(
      text: content.displayText,
      chapterIndex: location.chapterIndex,
      startOffset: safeOffset,
    );
    _segments = segments;
    _segmentIndex = segments.isEmpty ? -1 : 0;
    if (segments.isEmpty) return _SpeechStart.empty;
    return await _speakCurrentSegment(generation)
        ? _SpeechStart.started
        : _SpeechStart.cancelled;
  }

  void _finishSpeech(int generation, {required String notice}) {
    if (!_isActiveGeneration(generation)) return;
    _clearSpeechStateWithoutNotify();
    runtime.emitUserNotice(notice);
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _speechGeneration += 1;
    _clearSpeechStateWithoutNotify();
    await _tts.stop();
    notifyListeners();
  }

  @override
  Future<void> setRate(double value) async {
    // 語速的保存、範圍與保存失敗時的還原由 TTSService 負責；
    // 失敗時也要通知面板顯示還原後的值。
    try {
      await _tts.setRate(value);
    } finally {
      notifyListeners();
    }
  }

  @override
  Future<void> setPitch(double value) async {
    try {
      await _tts.setPitch(value);
    } finally {
      notifyListeners();
    }
  }

  Future<void> setLanguage(String value) async {
    await _tts.setLanguage(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PreferKey.readerTtsLanguage, value);
    notifyListeners();
  }

  void _handleTtsChanged() {
    notifyListeners();
  }

  void _handleRuntimeChanged() {
    final contentGeneration = runtime.state.contentGeneration;
    if (contentGeneration == _observedContentGeneration) return;
    _observedContentGeneration = contentGeneration;

    // Segments and highlights are UTF-16 coordinates in one concrete content
    // generation. Once that generation changes, fence every in-flight speech
    // continuation and remove coordinates owned by the old display text.
    _speechGeneration += 1;
    _clearSpeechStateWithoutNotify();
    unawaited(_tts.stop());
    notifyListeners();
  }

  void _handleTtsEvent(String event) {
    switch (event) {
      case 'onComplete':
        unawaited(_handleSpeechCompleted());
        return;
      case 'onPlay':
        if (!_tts.isPlaying) unawaited(toggle());
        return;
      case 'onPause':
        if (_tts.isPlaying) unawaited(_tts.pause());
        return;
      case 'onStop':
        unawaited(stop());
        return;
    }
  }

  Future<void> _handleSpeechCompleted() async {
    if (_handlingCompletion || _disposed) return;
    final completedSegment = _currentSegment;
    if (completedSegment == null) {
      notifyListeners();
      return;
    }
    final generation = _speechGeneration;
    _handlingCompletion = true;
    try {
      if (_advanceSegment()) {
        await _speakCurrentSegment(generation);
        return;
      }
      final chapterIndex = completedSegment.chapterIndex + 1;
      if (chapterIndex >= runtime.chapterCount) {
        _finishSpeech(generation, notice: '已朗讀到書尾');
        return;
      }
      await _speakFrom(
        ReaderV2Location(
          chapterIndex: chapterIndex,
          charOffset: 0,
          visualOffsetPx: runtime.state.layoutSpec.anchorOffsetInViewport,
        ),
        generation: generation,
      );
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'reader_v2_tts_controller',
          context: ErrorDescription('advancing TTS after completion'),
        ),
      );
      if (_isActiveGeneration(generation)) {
        _clearSpeechStateWithoutNotify();
        notifyListeners();
      }
    } finally {
      _handlingCompletion = false;
    }
  }

  bool _isActiveGeneration(int generation) {
    return !_disposed && generation == _speechGeneration;
  }

  ReaderV2TtsSegment? get _currentSegment {
    final index = _segmentIndex;
    if (index < 0 || index >= _segments.length) return null;
    return _segments[index];
  }

  bool _advanceSegment() {
    if (_segmentIndex + 1 >= _segments.length) return false;
    _segmentIndex += 1;
    return true;
  }

  Future<bool> _speakCurrentSegment(int generation) async {
    final segment = _currentSegment;
    if (segment == null) return _clearSpeechState(generation);
    _speechStartLocation = ReaderV2Location(
      chapterIndex: segment.chapterIndex,
      charOffset: segment.startCharOffset,
    );
    await _tts.speak(segment.text);
    if (!_isActiveGeneration(generation)) return false;
    notifyListeners();
    return true;
  }

  bool _clearSpeechState(int generation) {
    if (!_isActiveGeneration(generation)) return false;
    _clearSpeechStateWithoutNotify();
    notifyListeners();
    return false;
  }

  void _clearSpeechStateWithoutNotify() {
    _speechStartLocation = null;
    _segments = const <ReaderV2TtsSegment>[];
    _segmentIndex = -1;
  }

  List<ReaderV2TtsSegment> _segmentsFor({
    required String text,
    required int chapterIndex,
    required int startOffset,
  }) {
    return const ReaderV2TtsSegmenter().segment(
      text: text,
      chapterIndex: chapterIndex,
      startOffset: startOffset,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    runtime.removeListener(_handleRuntimeChanged);
    _speechGeneration += 1;
    _clearSpeechStateWithoutNotify();
    unawaited(_eventSubscription.cancel());
    _tts.removeListener(_handleTtsChanged);
    unawaited(_tts.stop());
    if (_ownsTtsEngine) _tts.dispose();
    super.dispose();
  }
}

enum _SpeechStart { started, empty, unavailable, cancelled }
