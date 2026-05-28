import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:reader/core/constant/prefer_key.dart';
import 'package:reader/core/services/tts_service.dart';
import 'package:reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';
import 'package:reader/features/reader_v2/features/tts/reader_v2_tts_sheet.dart';
import 'package:reader/features/reader_v2/runtime/reader_v2_location.dart';
import 'package:reader/features/reader_v2/runtime/reader_v2_runtime.dart';
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
  List<_ReaderV2TtsSegment> _segments = const <_ReaderV2TtsSegment>[];
  int _segmentIndex = -1;
  int _speechGeneration = 0;
  bool _handlingCompletion = false;
  bool _disposed = false;

  static const int _minSegmentLength = 24;
  static const int _maxSegmentLength = 220;

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
    final wordEnd =
        _tts.currentWordEnd > boundedWordStart
            ? _tts.currentWordEnd
            : boundedWordStart + 1;
    final boundedWordEnd =
        wordEnd.clamp(boundedWordStart + 1, segmentLength).toInt();
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
    final content = await runtime.loadContentForTts(location);
    final safeOffset =
        location.charOffset.clamp(0, content.displayText.length).toInt();
    final segments = _segmentsFor(
      text: content.displayText,
      chapterIndex: location.chapterIndex,
      startOffset: safeOffset,
    );
    if (!_isActiveGeneration(generation)) return false;
    _segments = segments;
    _segmentIndex = segments.isEmpty ? -1 : 0;
    if (segments.isEmpty) return _clearSpeechState(generation);
    return _speakCurrentSegment(generation);
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
      for (
        var chapterIndex = completedSegment.chapterIndex + 1;
        _isActiveGeneration(generation) && chapterIndex < runtime.chapterCount;
        chapterIndex += 1
      ) {
        final started = await _startFromLocation(
          ReaderV2Location(chapterIndex: chapterIndex, charOffset: 0),
          generation: generation,
        );
        if (started) return;
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

  _ReaderV2TtsSegment? get _currentSegment {
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
    _segments = const <_ReaderV2TtsSegment>[];
    _segmentIndex = -1;
  }

  List<_ReaderV2TtsSegment> _segmentsFor({
    required String text,
    required int chapterIndex,
    required int startOffset,
  }) {
    final span = _readableSpan(text, startOffset);
    if (span == null) return const <_ReaderV2TtsSegment>[];
    final segments = <_ReaderV2TtsSegment>[];
    var cursor = span.start;
    while (cursor < span.end) {
      while (cursor < span.end && _isWhitespace(text.codeUnitAt(cursor))) {
        cursor += 1;
      }
      if (cursor >= span.end) break;
      var end = _segmentEnd(text, cursor, span.end);
      while (end > cursor && _isWhitespace(text.codeUnitAt(end - 1))) {
        end -= 1;
      }
      if (end <= cursor) {
        cursor += 1;
        continue;
      }
      segments.add(
        _ReaderV2TtsSegment(
          chapterIndex: chapterIndex,
          startCharOffset: cursor,
          endCharOffset: end,
          text: text.substring(cursor, end),
        ),
      );
      cursor = end;
    }
    return segments;
  }

  int _segmentEnd(String text, int start, int chapterEnd) {
    final preferredLimit =
        (start + _maxSegmentLength).clamp(start + 1, chapterEnd).toInt();
    for (var index = start; index < preferredLimit; index += 1) {
      final length = index - start + 1;
      if (length < _minSegmentLength && index + 1 < chapterEnd) continue;
      final codeUnit = text.codeUnitAt(index);
      if (_isSegmentBoundary(codeUnit)) return index + 1;
    }
    for (var index = preferredLimit - 1; index > start; index -= 1) {
      if (_isWhitespace(text.codeUnitAt(index))) return index;
    }
    return preferredLimit;
  }

  bool _isSegmentBoundary(int codeUnit) {
    switch (codeUnit) {
      case 0x0A: // \n
      case 0x21: // !
      case 0x2E: // .
      case 0x3B: // ;
      case 0x3F: // ?
      case 0x3002: // 。
      case 0xFF01: // ！
      case 0xFF1B: // ；
      case 0xFF1F: // ？
        return true;
    }
    return false;
  }

  ({int start, int end})? _readableSpan(String text, int offset) {
    var start = offset.clamp(0, text.length).toInt();
    var end = text.length;
    while (start < end && _isWhitespace(text.codeUnitAt(start))) {
      start += 1;
    }
    while (end > start && _isWhitespace(text.codeUnitAt(end - 1))) {
      end -= 1;
    }
    if (start >= end) return null;
    return (start: start, end: end);
  }

  bool _isWhitespace(int codeUnit) {
    switch (codeUnit) {
      case 0x09:
      case 0x0A:
      case 0x0B:
      case 0x0C:
      case 0x0D:
      case 0x20:
      case 0x85:
      case 0xA0:
      case 0x2028:
      case 0x2029:
      case 0x3000:
        return true;
    }
    return false;
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

class _ReaderV2TtsSegment {
  const _ReaderV2TtsSegment({
    required this.chapterIndex,
    required this.startCharOffset,
    required this.endCharOffset,
    required this.text,
  });

  final int chapterIndex;
  final int startCharOffset;
  final int endCharOffset;
  final String text;
}
