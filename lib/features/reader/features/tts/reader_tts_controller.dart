import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/playback/system_playback.dart';
import 'package:night_reader/core/playback/tts_service.dart';
import 'package:night_reader/shared/widgets/book/default_book_cover.dart';
import 'package:night_reader/features/reader/chapter/reader_content.dart';
import 'package:night_reader/features/reader/features/tts/reader_tts_highlight.dart';
import 'package:night_reader/features/reader/features/tts/reader_tts_phase.dart';
import 'package:night_reader/features/reader/features/tts/reader_tts_sheet.dart';
import 'package:night_reader/features/reader/features/tts/reader_tts_segmenter.dart';
import 'package:night_reader/features/reader/features/tts/reader_tts_speech_text.dart';
import 'package:night_reader/core/playback/sleep_timer.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';
import 'package:night_reader/features/reader/session/reader_runtime.dart';
import 'package:night_reader/features/reader/use_cases/coordinators/reader_chapter_navigation_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class ReaderTtsEngine extends ChangeNotifier {
  bool get isPlaying;
  double get rate;
  double get pitch;
  String? get language;
  String get currentSpokenText;

  /// 每念完一段送出一次。
  Stream<void> get completions;

  Future<void> speak(String text);
  Future<void> stop();
  Future<void> setRate(double value);
  Future<void> setPitch(double value);
  Future<void> setLanguage(String value);
}

class ReaderSystemTtsEngine extends ReaderTtsEngine {
  ReaderSystemTtsEngine({TTSService? service})
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

class ReaderTtsController extends ChangeNotifier
    implements ReaderTtsSheetController, PlaybackOwner {
  ReaderTtsController({
    required this.runtime,
    ReaderTtsEngine? tts,
    SystemPlayback? playback,
    @visibleForTesting DateTime Function()? now,
  }) : _tts = tts ?? ReaderSystemTtsEngine(),
       _ownsTtsEngine = tts == null,
       _playback = playback ?? SystemPlayback.instance {
    sleepTimer = SleepTimer(onExpired: _pause, now: now);
    _observedContentGeneration = runtime.state.contentGeneration;
    runtime.addListener(_handleRuntimeChanged);
    _tts.addListener(_handleTtsChanged);
    _completionSubscription = _tts.completions.listen(
      (_) => _handleSpeechCompleted(),
    );
  }

  final ReaderRuntime runtime;
  final ReaderTtsEngine _tts;
  final bool _ownsTtsEngine;
  final SystemPlayback _playback;
  late final StreamSubscription<void> _completionSubscription;

  /// 念過的章節顯示的章名（含繁簡轉換與替換規則），系統播放資訊的標題用。
  final Map<int, String> _chapterTitles = <int, String>{};

  /// 現在在哪個階段（`docs/state-machines.md`「朗讀」）。每次進入載入或念
  /// 一句都換一個新的，等待回來時看現在還是不是它，晚到的載入與念完就作廢。
  _TtsState _state = const _Idle();

  /// 上次看到的正文版本（閱讀器的計數），分出這次通知是不是正文換了。
  late int _observedContentGeneration;

  /// 放掉了：任何階段都可能，之後不再通知。
  bool _disposed = false;

  @override
  late final SleepTimer sleepTimer;

  @override
  ReaderTtsPhase get phase => switch (_state) {
    _Idle() => ReaderTtsPhase.idle,
    _Loading() || _Speaking() => ReaderTtsPhase.reading,
    _Paused() => ReaderTtsPhase.paused,
  };

  /// 正在朗讀：念著一句，或要念的那一章還在載入。不看引擎有沒有在發聲：
  /// 句與句之間、換章載入時引擎是停的。
  bool get isPlaying => phase == ReaderTtsPhase.reading;

  @override
  double get rate => _tts.rate;

  @override
  double get pitch => _tts.pitch;

  String? get language => _tts.language;

  /// 高亮目前朗讀的整個句段；載入下一章與暫停時留在剛念的那句。
  ReaderTtsHighlight? get currentHighlight {
    final segment = _highlightSegment;
    if (segment == null) return null;
    return ReaderTtsHighlight(
      chapterIndex: segment.chapterIndex,
      sentenceStart: segment.startCharOffset,
      sentenceEnd: segment.endCharOffset,
    );
  }

  ReaderTtsSegment? get _highlightSegment => switch (_state) {
    _Idle() => null,
    final _Loading loading => loading.highlight,
    final _Speaking speaking => speaking.segment,
    final _Paused paused => paused.highlight,
  };

  /// 正在念、要載入或暫停在的那一章；沒在朗讀是 null。系統播放資訊與上一
  /// 章、下一章照它。
  int? get _chapterIndex => switch (_state) {
    _Idle() => null,
    final _Loading loading => loading.location.chapterIndex,
    final _Speaking speaking => speaking.segment.chapterIndex,
    final _Paused paused => paused.resumeAt.chapterIndex,
  };

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLanguage = prefs.getString(PreferKey.readerTtsLanguage);
    if (savedLanguage != null && savedLanguage.isNotEmpty) {
      await _tts.setLanguage(savedLanguage);
    }
    await sleepTimer.load();
    notifyListeners();
  }

  /// 面板的播放列：朗讀中暫停在這一句，暫停中從暫停處接著念，沒在朗讀就從
  /// 畫面這一頁開始。
  @override
  Future<void> toggle() async {
    switch ((phase, _state)) {
      case (ReaderTtsPhase.reading, _):
        _pause();
      case (_, final _Paused paused):
        await _load(_Loading(paused.resumeAt, highlight: paused.highlight));
      case _:
        await startFromVisibleLocation();
    }
  }

  /// 選單上的定時鍵：和播放列一樣；開始時照記住的定時倒數（定時關閉就不
  /// 定時）。
  Future<void> toggleTimed() => toggle();

  Future<void> startFromVisibleLocation() async {
    final location = runtime.state.visibleLocation.normalized(
      chapterCount: runtime.chapterCount,
    );
    await _load(_Loading(location));
  }

  /// 使用者手動跳到別處：正在朗讀就從新位置接著念；暫停中則丟掉舊句，
  /// 下次播放從新位置開始。
  Future<void> followManualJump() async {
    final wasPlaying = isPlaying;
    if (phase == ReaderTtsPhase.idle) return;
    await stop();
    if (wasPlaying) await startFromVisibleLocation();
  }

  /// 載入 [loading] 那一章並從它的位置念起；這一章已沒有可念的內容就往後
  /// 找下一個有正文的章節。章節載入失敗或念到書尾時停下並告知，不默默跳過。
  Future<void> _load(_Loading loading) async {
    _enter(loading);
    var current = loading;
    while (true) {
      final location = current.location;
      final ReaderContent content;
      try {
        content = await runtime.loadContentForTts(location);
      } catch (_) {
        if (_isCurrent(current)) {
          _finish('第 ${location.chapterIndex + 1} 章無法載入，朗讀已結束');
        }
        return;
      }
      if (!_isCurrent(current)) return;
      _chapterTitles[location.chapterIndex] = content.title;
      final segments = _segmentsFor(
        text: content.displayText,
        chapterIndex: location.chapterIndex,
        startOffset: location.charOffset
            .clamp(0, content.displayText.length)
            .toInt(),
      );
      if (segments.isNotEmpty) {
        await _speak(_Speaking(segments, 0));
        return;
      }
      final next = _chapterAfter(location.chapterIndex, 1);
      if (next == null) {
        _finish(_endNoticeAfter(location.chapterIndex));
        return;
      }
      current = _Loading(_chapterStart(next));
      _enter(current);
    }
  }

  /// 念 [speaking] 那一句。引擎出錯時記下來、停下，不卡在朗讀中。
  Future<void> _speak(_Speaking speaking) async {
    _state = speaking;
    try {
      await _tts.speak(ReaderTtsSpeechText.prepare(speaking.segment.text));
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'reader_tts_controller',
          context: ErrorDescription('speaking a TTS segment'),
        ),
      );
      if (_isCurrent(speaking)) {
        _state = const _Idle();
        notifyListeners();
      }
      return;
    }
    if (_isCurrent(speaking)) notifyListeners();
  }

  /// 念完一段只在念一句時算數：載入中、暫停後引擎補報的念完不理。
  void _handleSpeechCompleted() {
    final state = _state;
    if (_disposed || state is! _Speaking) return;
    final next = state.next;
    if (next != null) {
      unawaited(_speak(next));
      return;
    }
    final chapterIndex = _chapterAfter(state.segment.chapterIndex, 1);
    if (chapterIndex == null) {
      _finish(_endNoticeAfter(state.segment.chapterIndex));
      return;
    }
    unawaited(
      _load(_Loading(_chapterStart(chapterIndex), highlight: state.segment)),
    );
  }

  void _finish(String notice) {
    _state = const _Idle();
    runtime.emitUserNotice(notice);
    notifyListeners();
  }

  bool _isCurrent(_TtsState state) => !_disposed && identical(_state, state);

  /// 換到 [loading] 並通知：要載入的那一章馬上算朗讀中，系統播放資訊換到它。
  void _enter(_Loading loading) {
    if (identical(_state, loading)) return;
    _state = loading;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _state = const _Idle();
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

  /// 每次通知前把階段告訴定時與系統播放資訊；朗讀中引擎每個字都會通知，
  /// 兩邊在狀態沒變時都不做事。
  @override
  void notifyListeners() {
    if (_disposed) return;
    final phase = this.phase;
    sleepTimer.sync(
      active: phase != ReaderTtsPhase.idle,
      running: phase == ReaderTtsPhase.reading,
    );
    _syncSystemPlayback(playing: phase == ReaderTtsPhase.reading);
    super.notifyListeners();
  }

  /// 正在念或暫停中：把正在念的章、這本書與做得到的按鈕交給系統播放資訊；
  /// 停了就收掉。
  void _syncSystemPlayback({required bool playing}) {
    final chapterIndex = _chapterIndex;
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
    AppLog.d('朗讀收到系統的播放：${_phaseLabel(phase)}');
    if (!isPlaying) unawaited(toggle());
  }

  static String _phaseLabel(ReaderTtsPhase phase) => switch (phase) {
    ReaderTtsPhase.idle => '沒在朗讀',
    ReaderTtsPhase.reading => '朗讀中',
    ReaderTtsPhase.paused => '已暫停',
  };

  @override
  void onPause() => _pause();

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

  /// 上一章、下一章：從那一章開頭接著念，暫停中按了也開始念；連按時從還在
  /// 載入的那章往下算。畫面跟著朗讀的那一句過去，和念完一章自動換章一樣。
  Future<void> _skipChapter(int delta) async {
    final current = _chapterIndex;
    if (current == null) return;
    final target = _chapterAfter(current, delta);
    if (target == null) return;
    final loading = _Loading(
      _chapterStart(target),
      highlight: _highlightSegment,
    );
    _enter(loading);
    await _tts.stop();
    if (_isCurrent(loading)) await _load(loading);
  }

  /// 從 [from] 往 [delta] 的方向數過去、跳過付費章節的那一章（ADR 0057）；
  /// 沒有時是 null。
  int? _chapterAfter(int from, int delta) =>
      ReaderChapterNavigationResolver.resolveRelativeTarget(
        currentChapterIndex: from,
        chapterCount: runtime.chapterCount,
        delta: delta,
        skip: (index) => runtime.chapterAt(index)?.isLocked ?? false,
      );

  /// [chapterIndex] 之後沒有能念的章時的提示：後面還有章卻沒有能念的，
  /// 都是付費章節（ADR 0057）。
  String _endNoticeAfter(int chapterIndex) =>
      chapterIndex + 1 < runtime.chapterCount ? lockedChapterNotice : '已朗讀到書尾';

  ReaderLocation _chapterStart(int chapterIndex) => ReaderLocation(
    chapterIndex: chapterIndex,
    charOffset: 0,
    visualOffsetPx: runtime.state.layoutSpec.anchorOffsetInViewport,
  );

  /// 暫停（面板、定時鍵、定時到了、系統或耳機按了暫停、另一方開始播）：
  /// 停在目前這句，播放鍵從這句開頭接著念；要念的那一章還在載入時，停在要
  /// 念的位置（按了上一章、下一章或自動換章是那一章開頭）。已經暫停就不動，
  /// 停的位置不變。用停止而不是引擎的暫停：句與句之間引擎沒有在念，暫停不
  /// 會生效，下一句照樣會開始。
  void _pause() {
    final paused = switch (_state) {
      _Idle() || _Paused() => null,
      final _Loading loading => _Paused(
        loading.location,
        highlight: loading.highlight,
      ),
      final _Speaking speaking => _Paused(
        ReaderLocation(
          chapterIndex: speaking.segment.chapterIndex,
          charOffset: speaking.segment.startCharOffset,
        ),
        highlight: speaking.segment,
      ),
    };
    if (paused == null) return;
    _state = paused;
    unawaited(_tts.stop());
    notifyListeners();
  }

  void _handleRuntimeChanged() {
    final contentGeneration = runtime.state.contentGeneration;
    if (contentGeneration == _observedContentGeneration) return;
    _observedContentGeneration = contentGeneration;

    // 句段與高亮是某一版正文裡的 UTF-16 座標；正文換了就停下，晚到的載入
    // 與念完跟著作廢，舊正文的座標一起丟掉。
    _state = const _Idle();
    unawaited(_tts.stop());
    notifyListeners();
  }

  List<ReaderTtsSegment> _segmentsFor({
    required String text,
    required int chapterIndex,
    required int startOffset,
  }) {
    final segments = const ReaderTtsSegmenter().segment(
      text: text,
      chapterIndex: chapterIndex,
      startOffset: startOffset,
    );
    // 刪節號獨立成行時沒有可念的文字；保留原文排版與座標，
    // 只從朗讀隊列略過，避免 TTS 一個個念「點」。
    return segments
        .where(
          (segment) => ReaderTtsSpeechText.prepare(segment.text).isNotEmpty,
        )
        .toList(growable: false);
  }

  @override
  void dispose() {
    _disposed = true;
    runtime.removeListener(_handleRuntimeChanged);
    _state = const _Idle();
    _playback.release(this);
    unawaited(_completionSubscription.cancel());
    _tts.removeListener(_handleTtsChanged);
    unawaited(_tts.stop());
    if (_ownsTtsEngine) _tts.dispose();
    sleepTimer.dispose();
    super.dispose();
  }
}

/// 朗讀內部的階段：[ReaderTtsPhase] 的朗讀中分成載入那一章與念一句，因為
/// 念完一段只在念一句時算數。
sealed class _TtsState {
  const _TtsState();
}

final class _Idle extends _TtsState {
  const _Idle();
}

/// 要念的那一章還在載入：載入好就從 [location] 念起。[highlight] 是剛念的
/// 那句，載入中高亮留在那裡。
final class _Loading extends _TtsState {
  _Loading(this.location, {this.highlight});

  final ReaderLocation location;
  final ReaderTtsSegment? highlight;
}

/// 念著 [segments] 的第 [index] 句（這一章從朗讀起點往後的句子）。
final class _Speaking extends _TtsState {
  _Speaking(this.segments, this.index);

  final List<ReaderTtsSegment> segments;
  final int index;

  ReaderTtsSegment get segment => segments[index];

  /// 同一章的下一句；這章念完了是 null。
  _Speaking? get next =>
      index + 1 < segments.length ? _Speaking(segments, index + 1) : null;
}

/// 停在 [resumeAt]，播放鍵從這裡接著念；[highlight] 是停的那句。
final class _Paused extends _TtsState {
  _Paused(this.resumeAt, {this.highlight});

  final ReaderLocation resumeAt;
  final ReaderTtsSegment? highlight;
}
