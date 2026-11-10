import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/system_playback/system_playback.dart';
import 'package:night_reader/core/services/tts_service.dart';
import 'package:night_reader/core/widgets/default_book_cover.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_highlight.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_sheet.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_segmenter.dart';
import 'package:night_reader/core/services/sleep_timer.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/use_cases/coordinators/reader_v2_chapter_navigation_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class ReaderV2TtsEngine extends ChangeNotifier {
  bool get isPlaying;
  double get rate;
  double get pitch;
  String? get language;
  String get currentSpokenText;

  /// 每念完一段送出一次。
  Stream<void> get completions;

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
  Stream<void> get completions => _service.completions;

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
    implements ReaderV2TtsSheetController, PlaybackOwner {
  ReaderV2TtsController({
    required this.runtime,
    ReaderV2TtsEngine? tts,
    SystemPlayback? playback,
    @visibleForTesting DateTime Function()? now,
  }) : _tts = tts ?? ReaderV2SystemTtsEngine(),
       _ownsTtsEngine = tts == null,
       _playback = playback ?? SystemPlayback.instance {
    sleepTimer = SleepTimer(onExpired: _pauseAtSentence, now: now);
    _observedContentGeneration = runtime.state.contentGeneration;
    runtime.addListener(_handleRuntimeChanged);
    _tts.addListener(_handleTtsChanged);
    _completionSubscription = _tts.completions.listen(
      (_) => unawaited(_handleSpeechCompleted()),
    );
  }

  final ReaderV2Runtime runtime;
  final ReaderV2TtsEngine _tts;
  final bool _ownsTtsEngine;
  final SystemPlayback _playback;
  late final StreamSubscription<void> _completionSubscription;

  /// 念過的章節顯示的章名（含繁簡轉換與替換規則），系統播放資訊的標題用。
  final Map<int, String> _chapterTitles = <int, String>{};
  ReaderV2Location? _speechStartLocation;
  List<ReaderV2TtsSegment> _segments = const <ReaderV2TtsSegment>[];
  int _segmentIndex = -1;
  int _speechGeneration = 0;
  late int _observedContentGeneration;

  /// 正在處理念完一段的那一輪朗讀（[_speechGeneration]）。同一輪不重複處理；
  /// 換了一輪（跳章、手動跳轉）時新一輪的念完照常處理，不被還在等下一章的
  /// 舊一輪擋掉。
  int? _completionGeneration;

  /// 按了上一章、下一章，還在載入的那一章與那一輪朗讀。連按時從這一章往下
  /// 算，不從還沒換掉的舊章算；換了一輪就作廢。
  ({int generation, int chapterIndex})? _skipTarget;
  bool _disposed = false;

  /// 停在一句之後（[_pauseAtSentence]），播放鍵從這裡接著念；暫停時已停掉
  /// 引擎，只剩這個位置。
  ReaderV2Location? _resumeLocation;

  @override
  late final SleepTimer sleepTimer;

  @override
  bool get isPlaying => _tts.isPlaying;

  @override
  bool get isPaused =>
      _resumeLocation != null ||
      (!_tts.isPlaying && _tts.currentSpokenText.isNotEmpty);

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
    await sleepTimer.load();
    notifyListeners();
  }

  @override
  Future<void> toggle() async {
    if (_tts.isPlaying) {
      await _tts.pause();
      return;
    }
    final resumeLocation = _resumeLocation;
    if (resumeLocation != null) {
      _resumeLocation = null;
      await _speakFrom(resumeLocation, generation: ++_speechGeneration);
      return;
    }
    if (isPaused) {
      await _tts.resume();
      return;
    }
    await startFromVisibleLocation();
  }

  /// 選單上的定時鍵：正在念就停止；否則照記住的定時開始朗讀（定時是關閉
  /// 時改用 30 分），暫停中則從暫停處接著念。
  Future<void> toggleTimed() async {
    if (_tts.isPlaying) {
      await stop();
      return;
    }
    if (sleepTimer.option == SleepTimerOption.off) {
      await sleepTimer.choose(SleepTimerOption.minutes30);
    }
    await toggle();
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
        _resumeLocation == null &&
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
    _chapterTitles[location.chapterIndex] = content.title;
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
    _skipTarget = null;
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

  /// 每次通知前把播放狀態告訴定時與系統播放資訊；朗讀中引擎每個字都會
  /// 通知，兩邊在狀態沒變時都不做事。
  @override
  void notifyListeners() {
    if (_disposed) return;
    final running = _currentSegment != null && !isPaused;
    sleepTimer.sync(
      active: _currentSegment != null || _resumeLocation != null,
      running: running,
    );
    _syncSystemPlayback(playing: running);
    super.notifyListeners();
  }

  /// 正在念或暫停中：把正在念的章、這本書與做得到的按鈕交給系統播放資訊；
  /// 停了就收掉。
  void _syncSystemPlayback({required bool playing}) {
    final chapterIndex = _speakingChapterIndex;
    if (chapterIndex == null) {
      _playback.release(this);
      return;
    }
    final book = runtime.book;
    _playback.show(
      this,
      item: NowPlaying(
        id: '${book.bookUrl}#$chapterIndex',
        title: _chapterTitleOf(chapterIndex),
        bookName: book.name,
        author: book.getRealAuthor(),
        coverSource: UnifiedCovers.coverOf(book),
      ),
      playing: playing,
      controls: {
        if (chapterIndex > 0) PlaybackControl.skipToPrevious,
        if (chapterIndex + 1 < runtime.chapterCount) PlaybackControl.skipToNext,
        PlaybackControl.stop,
      },
    );
  }

  String _chapterTitleOf(int chapterIndex) {
    for (final title in [
      _chapterTitles[chapterIndex],
      runtime.chapterAt(chapterIndex)?.title,
    ]) {
      final trimmed = title?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return '第 ${chapterIndex + 1} 章';
  }

  // --- 系統播放資訊、耳機與藍牙的按鍵 ---

  @override
  void onPlay() {
    if (!isPlaying) unawaited(toggle());
  }

  @override
  void onPause() => _pauseAtSentence();

  @override
  void onStop() => unawaited(stop());

  @override
  void onSkipToNext() => unawaited(_skipChapter(1));

  @override
  void onSkipToPrevious() => unawaited(_skipChapter(-1));

  /// 朗讀不宣告拖動與跳秒（[PlaybackControl.seek]、
  /// [PlaybackControl.rewind]、[PlaybackControl.fastForward]），系統不會送來。
  @override
  void onSeek(Duration position) {}

  @override
  void onRewind() {}

  @override
  void onFastForward() {}

  /// 上一章、下一章：從那一章開頭接著念，暫停中按了也開始念。畫面跟著
  /// 朗讀的那一句過去，和念完一章自動換章一樣。
  Future<void> _skipChapter(int delta) async {
    final current = _speakingChapterIndex;
    if (current == null) return;
    final target = _chapterAfter(current, delta);
    if (target == null) return;
    final generation = ++_speechGeneration;
    _skipTarget = (generation: generation, chapterIndex: target);
    _resumeLocation = null;
    notifyListeners();
    await _tts.stop();
    await _speakFrom(_chapterStart(target), generation: generation);
  }

  /// 從 [from] 往 [delta] 的方向數過去、跳過付費章節的那一章（ADR 0057）；
  /// 沒有時是 null。
  int? _chapterAfter(int from, int delta) =>
      ReaderV2ChapterNavigationResolver.resolveRelativeTarget(
        currentChapterIndex: from,
        chapterCount: runtime.chapterCount,
        delta: delta,
        skip: (index) => runtime.chapterAt(index)?.isLocked ?? false,
      );

  /// 正在念、暫停中或按了上一章／下一章正在載入的那一章；沒在朗讀是 null。
  int? get _speakingChapterIndex =>
      _pendingSkipTarget ??
      _resumeLocation?.chapterIndex ??
      _currentSegment?.chapterIndex;

  int? get _pendingSkipTarget {
    final skip = _skipTarget;
    return skip != null && skip.generation == _speechGeneration
        ? skip.chapterIndex
        : null;
  }

  ReaderV2Location _chapterStart(int chapterIndex) => ReaderV2Location(
    chapterIndex: chapterIndex,
    charOffset: 0,
    visualOffsetPx: runtime.state.layoutSpec.anchorOffsetInViewport,
  );

  /// 定時到了、系統或耳機按了暫停、另一方開始播：停在目前這句，播放鍵從
  /// 這句開頭接著念；剛按了上一章／下一章、那一章還在載入時，停在那一章
  /// 開頭。用停止而不是引擎的暫停：句與句之間引擎沒有在念，暫停不會生效，
  /// 下一句照樣會開始。
  void _pauseAtSentence() {
    final skipTarget = _pendingSkipTarget;
    final segment = _currentSegment;
    final ReaderV2Location resumeLocation;
    if (skipTarget != null) {
      resumeLocation = _chapterStart(skipTarget);
    } else if (segment != null) {
      resumeLocation = ReaderV2Location(
        chapterIndex: segment.chapterIndex,
        charOffset: segment.startCharOffset,
      );
    } else {
      return;
    }
    _speechGeneration += 1;
    _resumeLocation = resumeLocation;
    unawaited(_tts.stop());
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

  Future<void> _handleSpeechCompleted() async {
    // 停在一句時停掉了引擎，引擎事後補報的完成不能讓朗讀接著念下去。
    if (_completionGeneration == _speechGeneration ||
        _disposed ||
        _resumeLocation != null) {
      return;
    }
    final completedSegment = _currentSegment;
    if (completedSegment == null) {
      notifyListeners();
      return;
    }
    final generation = _speechGeneration;
    _completionGeneration = generation;
    try {
      if (_advanceSegment()) {
        await _speakCurrentSegment(generation);
        return;
      }
      final chapterIndex = _chapterAfter(completedSegment.chapterIndex, 1);
      if (chapterIndex == null) {
        // 後面還有章卻沒有能念的，都是付費章節（ADR 0057）。
        final paidAhead =
            completedSegment.chapterIndex + 1 < runtime.chapterCount;
        _finishSpeech(
          generation,
          notice: paidAhead ? lockedChapterNotice : '已朗讀到書尾',
        );
        return;
      }
      await _speakFrom(_chapterStart(chapterIndex), generation: generation);
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
      if (_completionGeneration == generation) _completionGeneration = null;
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
    _resumeLocation = null;
    _skipTarget = null;
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
    _playback.release(this);
    unawaited(_completionSubscription.cancel());
    _tts.removeListener(_handleTtsChanged);
    unawaited(_tts.stop());
    if (_ownsTtsEngine) _tts.dispose();
    sleepTimer.dispose();
    super.dispose();
  }
}

enum _SpeechStart { started, empty, unavailable, cancelled }
