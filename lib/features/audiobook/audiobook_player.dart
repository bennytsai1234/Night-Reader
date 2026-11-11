import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/web_book/audio_url_resolver.dart';
import 'package:night_reader/core/exception/user_error.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/book_chapter_files.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/sleep_timer.dart';
import 'package:night_reader/core/services/system_playback/system_playback.dart';
import 'package:night_reader/core/sync/progress_sync.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/core/widgets/default_book_cover.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_read_time_controller.dart';

import 'audio_engine.dart';

/// 一集播完之後接著怎麼播（同 Legado `AudioPlay.PlayMode`）。
enum AudiobookPlayMode {
  /// 播下一集，最後一集播完就停。
  inOrder('播完停'),
  singleLoop('單集循環'),
  shuffle('隨機播放'),

  /// 播下一集，最後一集播完從第一集接著播。
  listLoop('列表循環');

  const AudiobookPlayMode(this.label);

  final String label;

  AudiobookPlayMode get next => values[(index + 1) % values.length];
}

/// 有聲書的播放（ADR 0055）。整個 App 一個，離開播放器畫面照樣在播；
/// 播放器畫面、離開播放器時的圓鈕、通知與鎖定畫面都看它。
///
/// 收聽進度記「章＋第幾毫秒」，毫秒存在 [Book.charOffset]，跟著閱讀進度
/// 同步：播著時每 [saveInterval] 存一次，暫停、換集、停止、App 退到背景
/// 時也存；回到前景時沒在播就接上另一台較新的進度，同一集差 [nearMs]
/// 以內不跳。
class AudiobookPlayer extends ChangeNotifier implements PlaybackOwner {
  AudiobookPlayer({
    AudioEngine Function()? engine,
    this._bookDao,
    this._chapterDao,
    this._sourceDao,
    BookSourceService? sourceService,
    SyncService? sync,
    SystemPlayback? playback,
    Random? random,
    DateTime Function()? now,
    this._readRecordDao,
  }) : _newEngine = engine ?? JustAudioEngine.new,
       _sourceService = sourceService ?? BookSourceService(),
       _sync = sync ?? SyncService.instance,
       _playback = playback ?? SystemPlayback.instance,
       _random = random ?? Random(),
       _now = now ?? DateTime.now {
    sleepTimer = SleepTimer(onExpired: () => unawaited(pause()), now: now);
  }

  static AudiobookPlayer? _instance;

  static AudiobookPlayer get instance => _instance ??= AudiobookPlayer();

  @visibleForTesting
  static set instance(AudiobookPlayer player) => _instance = player;

  /// 播著時多久存一次進度。
  static const Duration saveInterval = Duration(seconds: 5);

  /// 同一集兩台差這麼多以內不跳（對應文字書的 100 字）。
  static const int nearMs = 10000;

  /// 倒退、快轉一次跳多少，和通知的跳秒一致。
  static const Duration skipStep = SystemPlayback.skipInterval;

  /// 開書時同步的閱讀進度還沒做完，最多等這麼久再照這台的位置開。
  static const Duration openGrace = Duration(milliseconds: 500);

  final AudioEngine Function() _newEngine;
  final ReadRecordDao? _readRecordDao;

  /// 收聽時間記進閱讀統計（使用者 2026-11-09 選「算進去、分開顯示」，
  /// ADR 0055）：只算真的出聲的時間，暫停、緩衝不算。照書的 `recordName`
  /// 記，有聲書帶類別前綴，統計頁分得出哪些是聽的。
  ReaderV2ReadTimeController? _listenTime;
  String? _listenBookUrl;

  /// 真的在出聲：播著、沒在載入或緩衝。收聽時間與定時都只算這段。
  bool get _sounding => _book != null && _playing && !_buffering && !_loading;

  /// 播放、載入、緩衝或錯誤變了就呼叫：收聽計時與定時倒數跟著出聲與否。
  void _syncListenTime() {
    sleepTimer.sync(active: _book != null, running: _sounding);
    final book = _book;
    if (book == null || !_sounding) {
      unawaited(_listenTime?.stop());
      return;
    }
    if (_listenBookUrl != book.bookUrl) {
      unawaited(_listenTime?.close());
      _listenTime = null;
      _listenBookUrl = book.bookUrl;
      final dao =
          _readRecordDao ??
          (getIt.isRegistered<ReadRecordDao>() ? getIt<ReadRecordDao>() : null);
      if (dao == null) return;
      _listenTime = ReaderV2ReadTimeController(
        bookName: () async =>
            (await _books.getByUrl(book.bookUrl))?.recordName ??
            book.recordName,
        readRecordDao: dao,
        now: _now,
      );
    }
    _listenTime?.start();
  }

  final BookDao? _bookDao;
  final ChapterDao? _chapterDao;
  final BookSourceDao? _sourceDao;
  final BookSourceService _sourceService;
  final SyncService _sync;
  final SystemPlayback _playback;
  final Random _random;
  final DateTime Function() _now;

  BookDao get _books => _bookDao ?? getIt<BookDao>();
  ChapterDao get _chapterStore => _chapterDao ?? getIt<ChapterDao>();
  BookSourceDao get _sources => _sourceDao ?? getIt<BookSourceDao>();

  late final SleepTimer sleepTimer;

  /// 播到哪裡；播著時每 0.2–0.5 秒更新，畫面只讓用到它的元件重建。
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);

  AudioEngine? _engine;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  AppLifecycleListener? _lifecycle;

  Book? _book;
  BookSource? _source;
  List<BookChapter> _chapters = const [];
  int _index = 0;
  Duration? _duration;
  bool _playing = false;
  bool _loading = false;
  bool _buffering = false;
  bool _ended = false;
  String? _error;
  double _speed = 1.0;
  AudiobookPlayMode _mode = AudiobookPlayMode.inOrder;
  int _generation = 0;
  DateTime? _lastSaved;
  bool _markedOpen = false;

  /// 這一集的音訊請求（網址與標頭）；還沒解析好時是 null。
  AudioRequest? _request;
  bool _keepAwake = false;

  /// 預先解析好的下一集音訊請求。
  ({int index, AudioRequest request})? _prefetched;

  /// 使用者要不要出聲：載入中按了暫停（或定時到了、別的播放接手），載入完
  /// 就不自己開始播。和引擎回報的 [playing] 分開記。
  bool _wantPlay = false;

  /// 定時的選項只在第一次開書時從偏好設定讀一次。
  bool _timerLoaded = false;

  /// 正在播或暫停中的書；沒有時是 null（還沒開或已經停止）。
  Book? get book => _book;

  /// 這本書的書源；還沒開好時是 null。
  BookSource? get source => _source;
  List<BookChapter> get chapters => _chapters;
  int get chapterIndex => _index;
  BookChapter? get chapter =>
      _index >= 0 && _index < _chapters.length ? _chapters[_index] : null;
  Duration? get duration => _duration;
  bool get playing => _playing;

  /// 正在取得這一集的網址或等資料。
  bool get loading => _loading || _buffering;

  /// 最後一次的失敗（「播放失敗：原因」）；換集或重播時清掉。
  String? get error => _error;
  double get speed => _speed;
  AudiobookPlayMode get mode => _mode;

  /// 這一集的音訊網址與標頭（「複製音訊網址」）；還沒解析好時是 null。
  AudioRequest? get request => _request;

  /// 播放器開著時螢幕不熄（「更多」裡的保持喚醒），這次開 App 有效。
  bool get keepAwake => _keepAwake;

  void toggleKeepAwake() {
    _keepAwake = !_keepAwake;
    notifyListeners();
  }

  /// 這本書在播或暫停中。
  bool isCurrent(Book other) => _book?.bookUrl == other.bookUrl;

  // --- 開書與選集 ---

  /// 開 [book] 來聽。同一本已經開著時不打斷，給了 [chapterIndex] 才換到那一集；
  /// 沒給時接著上次聽的地方。同一本上次連目錄都沒開成時重開一次（重試）。
  Future<void> open(Book book, {int? chapterIndex}) async {
    if (!_timerLoaded) {
      _timerLoaded = true;
      try {
        await sleepTimer.load();
      } catch (error) {
        AppLog.e('讀定時設定失敗', error: error);
      }
    }
    if (isCurrent(book) && !(_chapters.isEmpty && _error != null)) {
      // 從目錄點了某一集：照目錄選集一樣從頭播，點的是正在播的那集也是。
      if (chapterIndex != null) await playChapter(chapterIndex);
      return;
    }
    await _close();
    final generation = ++_generation;
    _book = book;
    _chapters = const [];
    _index = book.chapterIndex;
    _duration = null;
    _ended = false;
    _error = null;
    _loading = true;
    position.value = chapterIndex == null
        ? Duration(milliseconds: book.charOffset)
        : Duration.zero;
    notifyListeners();
    try {
      final source = await _sources.getByUrl(book.origin);
      if (source == null) throw StateError('找不到書源');
      // 目錄抓不到也要知道書源，失敗畫面才給得出「登入」「前往驗證」。
      if (generation != _generation) return;
      _source = source;
      final chapters = await _loadChapters(source, book);
      if (generation != _generation) return;
      _chapters = chapters;
      var start = Duration.zero;
      var index = chapterIndex ?? book.chapterIndex;
      if (chapterIndex == null) {
        final stored = await _resumePosition(book);
        if (generation != _generation) return;
        index = stored.chapterIndex;
        start = Duration(milliseconds: stored.charOffset);
      }
      _markOpen(book);
      _ensureLifecycle();
      await _load(_playable(index), start: start, autoplay: true);
    } catch (error, stackTrace) {
      if (generation != _generation) return;
      _loading = false;
      _error = failureMessage('開啟有聲書', error, stackTrace);
      notifyListeners();
    }
  }

  /// 從目錄點了某一集：從頭播。
  Future<void> playChapter(int index) async {
    if (_book == null || _chapters.isEmpty) return;
    await _saveProgress();
    await _load(_playable(index), start: Duration.zero, autoplay: true);
  }

  Future<List<BookChapter>> _loadChapters(BookSource source, Book book) async {
    final stored = await _chapterStore.getByBook(book.bookUrl);
    if (stored.isNotEmpty) return stored;
    final fetched = await _sourceService.getChapterList(source, book);
    if (fetched.isEmpty) throw StateError('目錄是空的');
    for (var i = 0; i < fetched.length; i++) {
      fetched[i]
        ..index = i
        ..bookUrl = book.bookUrl;
    }
    await _chapterStore.insertChapters(fetched);
    return fetched;
  }

  /// 接著上次聽的地方：開 App 或回到 App 的那次同步還沒做完閱讀進度就等它
  /// （最多 [openGrace]），再讀這台資料庫裡的位置（ADR 0039）。
  Future<Book> _resumePosition(Book book) async {
    final ready = _sync.progressReady;
    if (ready != null) {
      await ready.timeout(openGrace, onTimeout: () {});
    }
    try {
      return await _books.getByUrl(book.bookUrl) ?? book;
    } catch (error, stackTrace) {
      AppLog.e('讀收聽紀錄失敗', error: error, stackTrace: stackTrace);
      return book;
    }
  }

  /// [index] 或之後第一個不跳過的集（[BookChapter.isSkippedWhenReading]）；
  /// 之後都沒有就往前找。
  int _playable(int index) {
    if (_chapters.isEmpty) return 0;
    final start = index.clamp(0, _chapters.length - 1);
    for (var i = start; i < _chapters.length; i++) {
      if (!_chapters[i].isSkippedWhenReading) return i;
    }
    for (var i = start - 1; i >= 0; i--) {
      if (!_chapters[i].isSkippedWhenReading) return i;
    }
    return start;
  }

  int? _nextPlayable(int from) {
    for (var i = from + 1; i < _chapters.length; i++) {
      if (!_chapters[i].isSkippedWhenReading) return i;
    }
    return null;
  }

  int? _previousPlayable(int from) {
    for (var i = from - 1; i >= 0; i--) {
      if (!_chapters[i].isSkippedWhenReading) return i;
    }
    return null;
  }

  /// 換到第 [index] 集、停在 [start]。
  Future<void> _load(
    int index, {
    required Duration start,
    required bool autoplay,
  }) async {
    final book = _book;
    final source = _source;
    if (book == null || source == null) return;
    // 換集先讓上一集停聲：新的一集抓不到時，不會畫面停在新集、耳朵還聽著
    // 舊集，舊集的位置也不會記到新集上。
    final previous = _engine;
    if (previous != null && previous.playing) await previous.pause();
    if (autoplay) _wantPlay = true;
    final generation = ++_generation;
    final chapter = _chapters[index];
    _index = index;
    _duration = null;
    _request = null;
    _ended = false;
    _error = null;
    _loading = true;
    position.value = start;
    notifyListeners();
    final engine = _ensureEngine();
    try {
      // 下載好的集放本機檔（ADR 0055），不再問書源。
      final local = await _downloadedFile(book, chapter);
      if (generation != _generation) return;
      final prefetched = _prefetched;
      final request = local != null
          ? AudioRequest(url: local.uri.toString(), headers: const {})
          : prefetched != null && prefetched.index == index
          ? prefetched.request
          : await _sourceService.getAudioRequest(source, book, chapter);
      _prefetched = null;
      if (generation != _generation) return;
      _request = request;
      await engine.open(
        Uri.parse(request.url),
        headers: request.headers,
        start: start,
      );
      if (generation != _generation) return;
      await engine.setSpeed(_speed);
      if (generation != _generation) return;
      _loading = false;
      _duration = engine.duration;
      _syncListenTime();
      if (autoplay && _wantPlay) await _startPlaying(engine);
      notifyListeners();
      _publish();
      unawaited(_saveProgress());
      unawaited(_prefetch(generation));
    } catch (error, stackTrace) {
      if (generation != _generation) return;
      _loading = false;
      _playing = false;
      _wantPlay = false;
      _error = failureMessage('播放', error, stackTrace);
      _syncListenTime();
      notifyListeners();
      _publish();
    }
  }

  static Future<File?> _downloadedFile(Book book, BookChapter chapter) async {
    try {
      return await BookChapterFiles.fileFor(book, chapter);
    } catch (error) {
      // 讀不到資料夾就照網路播。
      AppLog.e('讀已下載的音訊失敗', error: error);
      return null;
    }
  }

  /// 先解析下一集的音訊網址，換集時不用再等書源。
  Future<void> _prefetch(int generation) async {
    final book = _book;
    final source = _source;
    final next = _nextPlayable(_index);
    if (book == null || source == null || next == null) return;
    try {
      final request = await _sourceService.getAudioRequest(
        source,
        book,
        _chapters[next],
      );
      if (generation == _generation) {
        _prefetched = (index: next, request: request);
      }
    } catch (error) {
      // 輪到那一集時再抓一次，失敗才給使用者看。
      AppLog.d('預先解析下一集失敗：$error');
    }
  }

  AudioEngine _ensureEngine() {
    final existing = _engine;
    if (existing != null) return existing;
    final engine = _engine = _newEngine();
    _subscriptions
      ..add(engine.playingStream.listen(_onPlaying))
      ..add(engine.positionStream.listen(_onPosition))
      ..add(engine.durationStream.listen(_onDuration))
      ..add(engine.bufferingStream.listen(_onBuffering))
      ..add(engine.completedStream.listen((_) => unawaited(_onCompleted())))
      ..add(engine.errorStream.listen(_onError));
    return engine;
  }

  // --- 播放控制 ---

  Future<void> play() async {
    final engine = _engine;
    if (_book == null || engine == null) return;
    if (_error != null || _ended) {
      // 上次失敗或播完了：重新載入這一集（播完的從頭）。
      await _load(
        _index,
        start: _ended ? Duration.zero : position.value,
        autoplay: true,
      );
      return;
    }
    _wantPlay = true;
    await _startPlaying(engine);
  }

  Future<void> pause() async {
    _wantPlay = false;
    await _engine?.pause();
    await _saveProgress();
  }

  Future<void> toggle() => _playing ? pause() : play();

  Future<void> seek(Duration to) async {
    final engine = _engine;
    if (engine == null || _book == null) return;
    final total = _duration;
    var target = to < Duration.zero ? Duration.zero : to;
    if (total != null && target > total) target = total;
    position.value = target;
    await engine.seek(target);
    _publish();
    await _saveProgress();
  }

  /// 倒退或快轉 [delta]（負的是倒退）。
  Future<void> skipBy(Duration delta) => seek(position.value + delta);

  /// 有上一集可以換（播放器的上一集鈕、系統播放控制都照它）。
  bool get hasPrevious => _previousPlayable(_index) != null;

  /// 有下一集可以換；列表循環時最後一集的下一集是第一集。
  bool get hasNext =>
      _nextPlayable(_index) != null || _mode == AudiobookPlayMode.listLoop;

  Future<void> next() async {
    final next =
        _nextPlayable(_index) ??
        (_mode == AudiobookPlayMode.listLoop ? _playable(0) : null);
    if (next == null) return;
    await _saveProgress();
    await _load(next, start: Duration.zero, autoplay: true);
  }

  Future<void> previous() async {
    final previous = _previousPlayable(_index);
    if (previous == null) return;
    await _saveProgress();
    await _load(previous, start: Duration.zero, autoplay: true);
  }

  Future<void> setSpeed(double speed) async {
    _speed = speed;
    await _engine?.setSpeed(speed);
    notifyListeners();
    _publish();
  }

  void cycleMode() {
    _mode = _mode.next;
    notifyListeners();
    _publish();
  }

  /// 停止播放：存好進度，通知與圓鈕收起。從書架點書接著聽。
  Future<void> stop() async {
    if (_book == null) return;
    await _close();
    notifyListeners();
  }

  Future<void> _close() async {
    final book = _book;
    if (book == null) return;
    _generation++;
    await _saveProgress();
    await _listenTime?.stop();
    await _engine?.stop();
    _book = null;
    _source = null;
    _chapters = const [];
    _prefetched = null;
    _request = null;
    _playing = false;
    _wantPlay = false;
    _loading = false;
    _buffering = false;
    _error = null;
    sleepTimer.sync(active: false, running: false);
    _playback.release(this);
    if (_markedOpen) {
      _sync.closeBook(book);
      _markedOpen = false;
    }
    _sync.requestSyncProgressFirst();
  }

  Future<void> _onCompleted() async {
    if (_book == null || _loading) return;
    final generation = _generation;
    switch (_mode) {
      case AudiobookPlayMode.singleLoop:
        await seek(Duration.zero);
        await _engine?.play();
      case AudiobookPlayMode.shuffle:
        final candidates = [
          for (var i = 0; i < _chapters.length; i++)
            if (!_chapters[i].isSkippedWhenReading && i != _index) i,
        ];
        if (candidates.isEmpty) {
          await seek(Duration.zero);
          await _engine?.play();
        } else {
          final pick = candidates[_random.nextInt(candidates.length)];
          await _load(pick, start: Duration.zero, autoplay: true);
        }
      case AudiobookPlayMode.listLoop:
      case AudiobookPlayMode.inOrder:
        final next =
            _nextPlayable(_index) ??
            (_mode == AudiobookPlayMode.listLoop ? _playable(0) : null);
        if (next != null) {
          await _load(next, start: Duration.zero, autoplay: true);
        } else if (generation == _generation) {
          // 最後一集聽完：停在結尾，再按播放從這一集開頭。
          _ended = true;
          await _engine?.pause();
          await _saveProgress();
          notifyListeners();
        }
    }
  }

  // --- 引擎事件 ---

  void _onPlaying(bool playing) {
    if (_playing == playing) return;
    _playing = playing;
    _syncListenTime();
    if (!playing) unawaited(_saveProgress());
    notifyListeners();
    _publish();
  }

  void _onPosition(Duration at) {
    if (_loading) return;
    position.value = at;
    final last = _lastSaved;
    if (_playing && (last == null || _now().difference(last) >= saveInterval)) {
      unawaited(_saveProgress());
    }
  }

  void _onDuration(Duration? duration) {
    if (_duration == duration || duration == null) return;
    _duration = duration;
    notifyListeners();
    _publish();
  }

  void _onBuffering(bool buffering) {
    if (_buffering == buffering) return;
    _buffering = buffering;
    _syncListenTime();
    notifyListeners();
    _publish();
  }

  /// 播放途中出錯：引擎停下、記下原因，按播放時重新載入這一集（[play]）。
  void _onError(Object error) {
    if (_book == null) return;
    _playing = false;
    _loading = false;
    _wantPlay = false;
    _error = failureMessage('播放', error);
    unawaited(_engine?.pause());
    _syncListenTime();
    notifyListeners();
    _publish();
  }

  // --- 進度與同步 ---

  /// 現在聽到哪寫進書與資料庫（換源前用：照它對到新書源的同一集）。
  Future<void> saveProgress() => _saveProgress();

  Future<void> _saveProgress() async {
    final book = _book;
    final chapter = this.chapter;
    if (book == null || chapter == null) return;
    final ms = position.value.inMilliseconds;
    _lastSaved = _now();
    book
      ..chapterIndex = _index
      ..durChapterTitle = chapter.title
      ..charOffset = ms;
    try {
      final moved = await _books.updateProgress(
        book.bookUrl,
        _index,
        chapter.title,
        ms,
      );
      if (moved != null) book.progressTime = moved;
    } catch (error, stackTrace) {
      AppLog.e('存收聽進度失敗', error: error, stackTrace: stackTrace);
    }
  }

  void _markOpen(Book book) {
    _sync.openBook(book);
    _markedOpen = true;
  }

  void _ensureLifecycle() {
    _lifecycle ??= AppLifecycleListener(
      onHide: () => unawaited(
        _saveProgress().whenComplete(_sync.requestSyncProgressFirst),
      ),
      onShow: () => unawaited(_catchUpAfterResume()),
    );
  }

  /// 回到前景時沒在播：另一台聽到較新的地方就跳過去（停在那裡，不自動播）。
  Future<void> _catchUpAfterResume() async {
    final book = _book;
    if (book == null || _playing || _loading) return;
    final since = (index: _index, at: position.value);
    final pulled = await _sync.pullProgress(book.bookUrl);
    if (pulled == null || !pulled.isCurrent || !isCurrent(book)) return;
    if (_playing || _index != since.index || position.value != since.at) {
      return;
    }
    final index = _playable(
      pulled.progress.chapterIndexIn([
        for (final chapter in _chapters) chapter.title,
      ]),
    );
    final at = Duration(milliseconds: pulled.progress.charOffset);
    if (index != _index ||
        (at - position.value).inMilliseconds.abs() > nearMs) {
      await _load(index, start: at, autoplay: false);
    }
    await _saveProgress();
    await pulled.commit(ProgressSync.recordOf(book));
  }

  // --- 系統播放資訊 ---

  /// 開始播：先接手系統播放資訊（原本在播的朗讀收到暫停），再讓引擎播。
  Future<void> _startPlaying(AudioEngine engine) async {
    final generation = _generation;
    await _playback.start();
    // 等系統播放控制的這段時間按了暫停、換了集或停了：不出聲。
    if (!_wantPlay || generation != _generation || _book == null) return;
    _publish(playing: true);
    await engine.play();
  }

  /// 把這一集、播到哪裡與按鈕交給系統播放資訊；沒在播也還沒接手時不交
  /// （[SystemPlayback.show]）。
  void _publish({bool? playing}) {
    final book = _book;
    final chapter = this.chapter;
    if (book == null || chapter == null) return;
    _playback.show(
      this,
      item: NowPlaying(
        id: '${book.bookUrl}#$_index',
        title: chapter.title,
        bookName: book.name,
        author: book.getRealAuthor(),
        coverSource: UnifiedCovers.coverOf(book),
        kind: BookSourceKind.audio,
        duration: _duration,
      ),
      playing: playing ?? _playing,
      controls: {
        if (hasPrevious) PlaybackControl.skipToPrevious,
        PlaybackControl.rewind,
        PlaybackControl.fastForward,
        if (hasNext) PlaybackControl.skipToNext,
        if (_duration != null) PlaybackControl.seek,
      },
      position: _engine?.position ?? position.value,
      speed: _speed,
      buffering: loading,
    );
  }

  @override
  void onPlay() => unawaited(play());

  @override
  void onPause() => unawaited(pause());

  @override
  void onStop() => unawaited(stop());

  @override
  void onSkipToNext() => unawaited(next());

  @override
  void onSkipToPrevious() => unawaited(previous());

  @override
  void onRewind() => unawaited(skipBy(-skipStep));

  @override
  void onFastForward() => unawaited(skipBy(skipStep));

  @override
  void onSeek(Duration position) => unawaited(seek(position));

  @override
  void dispose() {
    _generation++;
    _lifecycle?.dispose();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_engine?.dispose());
    sleepTimer.dispose();
    position.dispose();
    super.dispose();
  }
}
