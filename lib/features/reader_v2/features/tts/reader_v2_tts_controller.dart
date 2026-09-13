import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/services/tts_service.dart';
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
  int get currentWordStart;
  int get currentWordEnd;
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
  int get currentWordStart => _service.currentWordStart;

  @override
  int get currentWordEnd => _service.currentWordEnd;

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
  bool _handlingCompletion = false;
  bool _disposed = false;

  @override
  bool get isPlaying => _tts.isPlaying;

  @override
  double get rate => _tts.rate;

  @override
  double get pitch => _tts.pitch;

  String? get language => _tts.language;
  ReaderV2Location? get speechStartLocation => _speechStartLocation;

  ReaderV2TtsHighlight? get currentHighlight {
    final segment = _currentSegment;
    if (segment == null) return null;
    final wordStart = _tts.currentWordStart;
    final segmentLength = segment.text.length;
    if (wordStart < 0 || segmentLength <= 0 || wordStart >= segmentLength) {
      return ReaderV2TtsHighlight(
        chapterIndex: segment.chapterIndex,
        highlightStart: segment.startCharOffset,
        highlightEnd: segment.endCharOffset,
      );
    }
    final boundedWordStart = wordStart.clamp(0, segmentLength - 1).toInt();
    final wordEnd = _tts.currentWordEnd > boundedWordStart
        ? _tts.currentWordEnd
        : boundedWordStart + 1;
    final boundedWordEnd = wordEnd
        .clamp(boundedWordStart + 1, segmentLength)
        .toInt();
    return ReaderV2TtsHighlight(
      chapterIndex: segment.chapterIndex,
      highlightStart: segment.startCharOffset + boundedWordStart,
      highlightEnd: segment.startCharOffset + boundedWordEnd,
    );
  }

  ReaderV2Location? get highlightLocation {
    final highlight = currentHighlight;
    if (highlight == null) return null;
    return ReaderV2Location(
      chapterIndex: highlight.chapterIndex,
      charOffset: highlight.highlightStart,
    );
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRate = prefs.getDouble(PreferKey.readerTtsRate);
    final savedPitch = prefs.getDouble(PreferKey.readerTtsPitch);
    final savedLanguage = prefs.getString(PreferKey.readerTtsLanguage);
    if (savedRate != null) await _tts.setRate(savedRate);
    if (savedPitch != null) await _tts.setPitch(savedPitch);
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
    if (_tts.currentSpokenText.isNotEmpty) {
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
    await _startFromLocation(location, generation: generation);
  }

  Future<bool> _startFromLocation(
    ReaderV2Location location, {
    required int generation,
  }) async {
    try {
      final content = await runtime.loadContentForTts(location);
      final safeOffset = location.charOffset
          .clamp(0, content.displayText.length)
          .toInt();
      final segments = _segmentsFor(
        text: content.displayText,
        chapterIndex: location.chapterIndex,
        startOffset: safeOffset,
      );
      if (!_isActiveGeneration(generation)) return false;
      _segments = segments;
      _segmentIndex = segments.isEmpty ? -1 : 0;
      if (segments.isEmpty) return false;
      return await _speakCurrentSegment(generation);
    } catch (_) {
      if (!_isActiveGeneration(generation)) return false;
      return false;
    }
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
    await _tts.setRate(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(PreferKey.readerTtsRate, value);
    notifyListeners();
  }

  @override
  Future<void> setPitch(double value) async {
    await _tts.setPitch(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(PreferKey.readerTtsPitch, value);
    notifyListeners();
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
      var failCount = 0;
      for (
        var chapterIndex = completedSegment.chapterIndex + 1;
        _isActiveGeneration(generation) && chapterIndex < runtime.chapterCount;
        chapterIndex += 1
      ) {
        final started = await _startFromLocation(
          ReaderV2Location(
            chapterIndex: chapterIndex,
            charOffset: 0,
            visualOffsetPx: runtime.state.layoutSpec.anchorOffsetInViewport,
          ),
          generation: generation,
        );
        if (started) {
          return;
        } else {
          failCount++;
          if (failCount >= 3) {
            break;
          }
        }
      }
      if (_isActiveGeneration(generation)) {
        _clearSpeechStateWithoutNotify();
        notifyListeners();
      }
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
    _speechGeneration += 1;
    _clearSpeechStateWithoutNotify();
    unawaited(_eventSubscription.cancel());
    _tts.removeListener(_handleTtsChanged);
    unawaited(_tts.stop());
    if (_ownsTtsEngine) _tts.dispose();
    super.dispose();
  }
}
