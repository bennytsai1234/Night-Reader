import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:night_reader/core/background_work/reading_fetches.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/engine/web_book/audio_url_resolver.dart';
import 'package:night_reader/core/exception/user_error.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/storage/book_chapter_files.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/core/storage/books_in_use.dart';
import 'package:night_reader/core/playback/audio_focus.dart';
import 'package:night_reader/core/playback/sleep_timer.dart';
import 'package:night_reader/core/playback/system_playback.dart';
import 'package:night_reader/core/sync/progress_sync.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/shared/widgets/book/default_book_cover.dart';
import 'package:night_reader/features/reader/session/reader_read_time_controller.dart';
import 'package:night_reader/core/storage/moved_chapters.dart';

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

/// 播放器在哪個階段（`docs/state-machines.md`「有聲書播放器」的階段表）。
/// 播放器頁、收聽圓鈕與系統播放資訊都照它畫。
enum AudiobookPhase {
  /// 沒有書：還沒開，或已經停止。
  idle,

  /// 開書中：讀書源、目錄與上次聽到哪。
  opening,

  /// 打不開：書源或目錄沒讀成，[AudiobookPlayer.error] 是原因。
  openFailed,

  /// 載入這一集：找下載好的檔、抓網址、開音訊。
  loading,

  /// 播著（緩衝時沒有聲音，[AudiobookPlayer.loading]）。
  playing,

  /// 暫停。
  paused,

  /// 這一集播不出來：換集失敗或播放途中出錯，[AudiobookPlayer.error] 是
  /// 原因；按播放重載這一集。
  failed,

  /// 最後一集播完（播完停）：按播放從這一集開頭。
  ended,
}

/// 要不到音訊焦點（例如通話中）時不播，提示這一句。
const String audiobookNoAudioFocusNotice = '通話中或其他聲音正在播放，有聲書已暫停';

/// 正文已經在畫面上之後才抓到另一台較新的進度，提示這一句。
const String audiobookNewerProgressNotice = '另一台聽到較新的地方';

/// 播放器頁開著時，抓到另一台較新的進度就交給它問要不要跳過去。頁面沒
/// 開著時沒人聽，照原本直接換過去。
class AudiobookProgressSuggestion {
  const AudiobookProgressSuggestion({
    required this.message,
    required this.jump,
  });

  final String message;

  /// 按了「跳過去」才執行；會再確認讀者沒按過什麼、還是同一筆。
  final Future<void> Function() jump;
}

/// 有聲書的播放（ADR 0055）。整個 App 一個，離開播放器畫面照樣在播；
/// 播放器畫面、離開播放器時的圓鈕、通知與鎖定畫面都看它。
///
/// 收聽進度記「章＋第幾毫秒」，毫秒存在 [Book.charOffset]，跟著閱讀進度
/// 同步：雲端那筆比較新、而且聽到的地方在這台後面才接。播著時每
/// [saveInterval] 存一次、每 [uploadInterval] 送一次，暫停時存好馬上送，
/// 換集、停止、App 退到背景時也存好再送；接著上次聽的地方開書時、回到前景
/// 時沒在播，抓這本書的雲端進度，比這台新又在後面：播放器頁開著就問要不要
/// 換到那一集的那一毫秒，頁沒開著照原本直接換過去。
class AudiobookPlayer extends ChangeNotifier implements PlaybackOwner {
  AudiobookPlayer({
    AudioEngine Function()? engine,
    this._bookDao,
    this._chapterDao,
    this._sourceDao,
    BookSourceService? sourceService,
    SyncService? sync,
    SystemPlayback? playback,
    AudioFocus? audioFocus,
    Random? random,
    DateTime Function()? now,
    this._readRecordDao,
  }) : _newEngine = engine ?? JustAudioEngine.new,
       _sourceService = sourceService ?? BookSourceService(),
       _sync = sync ?? SyncService.instance,
       _playback = playback ?? SystemPlayback.instance,
       _audioFocus = audioFocus ?? AudioFocus.instance,
       _random = random ?? Random(),
       _now = now ?? DateTime.now {
    sleepTimer = SleepTimer(onExpired: () => unawaited(pause()), now: now);
    _moves = AppEventBus()
        .onName(AppEventBus.sourceMoved)
        .listen((event) => _followMove(event.data as SourceMovedEvent));
  }

  late final StreamSubscription<AppEvent> _moves;

  static AudiobookPlayer? _instance;

  static AudiobookPlayer get instance => _instance ??= AudiobookPlayer();

  @visibleForTesting
  static set instance(AudiobookPlayer player) => _instance = player;

  /// 播著時多久存一次進度。
  static const Duration saveInterval = Duration(seconds: 5);

  /// 播著時多久把進度送上去一次，另一台切過去時接得上。
  static const Duration uploadInterval = Duration(seconds: 60);

  /// 倒退、快轉一次跳多少，和通知的跳秒一致。
  static const Duration skipStep = SystemPlayback.skipInterval;

  /// 開書時同步的閱讀進度還沒做完，最多等這麼久再照這台的位置開。
  static const Duration openGrace = Duration(milliseconds: 500);

  final AudioEngine Function() _newEngine;
  final ReadRecordDao? _readRecordDao;

  /// 收聽時間記進閱讀統計（使用者 2026-11-09 選「算進去、分開顯示」，
  /// ADR 0055）：只算真的出聲的時間，暫停、緩衝不算。照書的 `recordName`
  /// 記，有聲書帶類別前綴，統計頁分得出哪些是聽的。
  ReaderReadTimeController? _listenTime;
  String? _listenBookUrl;

  /// 真的在出聲：播著、沒在緩衝。收聽時間與定時都只算這段。
  bool get _sounding => _phase == AudiobookPhase.playing && !_buffering;

  /// 階段或緩衝變了就呼叫：收聽計時與定時倒數跟著出聲與否。
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
      _listenTime = ReaderReadTimeController(
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
  final AudioFocus _audioFocus;
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

  /// 播著的書登記成開著的（[BooksInUse]）：播的時候不自動換源，不然之後存的
  /// 收聽進度寫不到換過去的那本（ADR 0069）。
  BookInUse? _inUse;
  BookSource? _source;
  List<BookChapter> _chapters = const [];
  int _index = 0;
  Duration? _duration;
  AudiobookPhase _phase = AudiobookPhase.idle;

  /// 打不開、這一集播不出來的原因；只在這兩個階段有（[error]）。
  String? _failure;

  /// 引擎回報在等資料。播著與暫停時都可能（暫停中拖動也要等），所以不是
  /// 一個階段。
  bool _buffering = false;
  double _speed = 1.0;
  AudiobookPlayMode _mode = AudiobookPlayMode.inOrder;

  /// 哪一次開書或換集還有效：每次開書、換集、停止加一，每個等待之後拿它比，
  /// 比不上就是被之後的動作取代了。同一個階段（例如連按兩次下一集都在
  /// 載入這一集）也要分得出是哪一次，所以不收進階段。
  int _generation = 0;

  /// 正在換到哪一集：目錄選集、上一集、下一集按下去就記下，存好這一集的
  /// 進度、[_load] 接下它才清掉。等的這段時間上一集播完、回到前景接另一台
  /// 的進度都不接手，讀者選的那一集一定贏；停止、開了別本時跟著清掉。
  int? _switchingTo;

  DateTime? _lastSaved;

  /// 播著時上次送進度的時間（[uploadInterval]）；暫停、停止時清掉，再播時
  /// 重新數。
  DateTime? _lastSent;
  bool _markedOpen = false;

  /// 這一集的音訊請求（網址與標頭）；還沒解析好時是 null。
  AudioRequest? _request;
  bool _keepAwake = false;

  /// 預先解析好的下一集音訊請求。
  ({int index, AudioRequest request})? _prefetched;

  /// 播放器頁一打開就先抓的這本書雲端進度；開書時直接等這一個。播放器
  /// 整個 App 共用：沒被這次開書用掉（換頁動畫中就返回、開書失敗）的，
  /// 過了 [_prefetchFresh] 就不再用。
  ({String bookUrl, Future<PulledProgress?> pulling, DateTime at})?
  _prefetchedProgress;
  static const Duration _prefetchFresh = Duration(seconds: 5);

  /// 問過幾次要不要跳：換下一則之後，前一個按鈕按了也不動。
  int _suggestionSerial = 0;

  /// 使用者要不要出聲：載入中按了暫停（或定時到了、別的播放接手），載入完
  /// 就不自己開始播；暫停時在接手系統播放的那一下按了暫停也不出聲。開書中、
  /// 載入這一集、暫停時都可能是要或不要，所以不是一個階段。
  bool _wantPlay = false;

  /// 使用者按過幾次（開書、播放、暫停、拖動、換集、停止，含系統的按鍵與
  /// 定時到了）。回到前景接另一台的進度拿它看抓的途中有沒有按過什麼。
  int _commands = 0;

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

  AudiobookPhase get phase => _phase;

  bool get playing => _phase == AudiobookPhase.playing;

  /// 開書中、載入這一集，或引擎在等資料（播放鍵轉圈）。
  bool get loading =>
      _phase == AudiobookPhase.opening ||
      _phase == AudiobookPhase.loading ||
      _buffering;

  /// 打不開或這一集播不出來的原因（「播放失敗：原因」）；其他階段是 null。
  String? get error =>
      _phase == AudiobookPhase.openFailed || _phase == AudiobookPhase.failed
      ? _failure
      : null;

  /// 不影響階段的提示（例如通話中按播放沒出聲）；播放器頁與收聽圓鈕跳一則
  /// 提示。
  Stream<String> get notices => _notices.stream;
  final StreamController<String> _notices =
      StreamController<String>.broadcast();

  /// 抓到另一台較新的進度時交給播放器頁問要不要跳過去。只有播放器頁聽；
  /// 沒開著時沒人聽，照原本直接換過去（不影響畫面上的正文）。
  Stream<AudiobookProgressSuggestion> get progressSuggestions =>
      _progressSuggestions.stream;
  final StreamController<AudiobookProgressSuggestion> _progressSuggestions =
      StreamController<AudiobookProgressSuggestion>.broadcast();

  /// 使用者按過幾次（播放、暫停、拖動、換集、停止）：問要不要跳的提示在
  /// 按了什麼之後收起。
  int get interactions => _commands;

  /// 換到 [phase]：收聽計時與定時跟著出聲與否，畫面重畫。系統播放資訊由
  /// 呼叫的地方決定交不交（載入這一集時刻意不交，停在上一集）。
  void _moveTo(AudiobookPhase phase, {String? failure}) {
    _phase = phase;
    _failure = failure;
    _syncListenTime();
    notifyListeners();
  }

  /// 失敗了：還沒有目錄是打不開，有了是這一集播不出來。
  void _fail(String message) {
    _wantPlay = false;
    _moveTo(
      _chapters.isEmpty ? AudiobookPhase.openFailed : AudiobookPhase.failed,
      failure: message,
    );
  }

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

  /// 這本書的書源換了：播放頁進去編輯書源回來（網址或規則可能改了），或別處
  /// 換了書源網址（[_followMove]）。資料庫裡這本書已經改記新網址、書本資料夾
  /// 也搬了：照資料庫換上書與書源，換集時才找得到已下載的集數、照新書源抓；
  /// 照舊書源預抓的下一集作廢，系統播放資訊照新的封面路徑重交。
  Future<void> reloadBookOrigin() async {
    final book = _book;
    if (book == null) return;
    final stored = await _books.getByUrl(book.bookUrl);
    if (!identical(book, _book)) return;
    final source = await _sources.getByUrl(stored?.origin ?? book.origin);
    if (!identical(book, _book)) return;
    if (stored != null) {
      book
        ..origin = stored.origin
        ..originName = stored.originName
        ..coverLocalPath = stored.coverLocalPath
        ..customCoverLocalPath = stored.customCoverLocalPath;
    }
    if (source != null) _source = source;
    _prefetched = null;
    notifyListeners();
    // 開書、載入這一集時不交：載好時才交（[_load]）。
    if (_phase != AudiobookPhase.opening && _phase != AudiobookPhase.loading) {
      _publish();
    }
  }

  /// 別處換了書源網址：是這本書的書源就換上新的。書可能和其他頁面共用、那邊
  /// 先改了網址，手上的書源還是舊的也算。
  void _followMove(SourceMovedEvent event) {
    final book = _book;
    if (book == null) return;
    if (book.origin != event.fromUrl &&
        _source?.bookSourceUrl != event.fromUrl) {
      return;
    }
    unawaited(reloadBookOrigin());
  }

  // --- 開書與選集 ---

  /// 播放器頁一打開就先抓這本書的雲端進度，開書時直接等這一個抓取；同一本
  /// 已經開著時不用抓（開書也不會再抓）。
  void prefetchProgress(Book book) {
    if (isCurrent(book) && _phase != AudiobookPhase.openFailed) return;
    final earlier = _prefetchedProgress;
    if (earlier != null &&
        earlier.bookUrl == book.bookUrl &&
        DateTime.now().difference(earlier.at) < _prefetchFresh) {
      return;
    }
    _prefetchedProgress = (
      bookUrl: book.bookUrl,
      pulling: _sync.pullProgress(book.bookUrl),
      at: DateTime.now(),
    );
  }

  /// 開 [book] 來聽。同一本已經開著時不打斷，給了 [chapterIndex] 才換到那一集；
  /// 沒給時接著上次聽的地方。同一本上次連目錄都沒開成時重開一次（重試）。
  Future<void> open(Book book, {int? chapterIndex}) async {
    _commands++;
    if (!_timerLoaded) {
      _timerLoaded = true;
      try {
        await sleepTimer.load();
      } catch (error) {
        AppLog.e('讀定時設定失敗', error: error);
      }
    }
    if (isCurrent(book) && _phase != AudiobookPhase.openFailed) {
      // 從目錄點了某一集：照目錄選集一樣從頭播，點的是正在播的那集也是。
      if (chapterIndex != null) await playChapter(chapterIndex);
      return;
    }
    await _close();
    final generation = ++_generation;
    _book = book;
    _inUse = BooksInUse.hold(book.bookUrl);
    _chapters = const [];
    _index = book.chapterIndex;
    _duration = null;
    position.value = chapterIndex == null
        ? Duration(milliseconds: book.charOffset)
        : Duration.zero;
    // 開書就是要聽：開好就播，開書中按了暫停才不播。
    _wantPlay = true;
    _moveTo(AudiobookPhase.opening);
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
      Future<PulledProgress?>? lateProgress;
      if (chapterIndex == null) {
        // 先記成開著：背景的同步不再改這本，由開書時抓的那一筆決定。
        _markOpen(book);
        final (stored, late) = await _resumePosition(book);
        lateProgress = late;
        if (generation != _generation) {
          // 等的時候在目錄選了別集（[_switchTo]）：播選的那集，這本書照樣
          // 算開著；停止或開了別本時 [_book] 已經換掉。
          if (identical(_book, book)) {
            _markOpen(book);
            _ensureLifecycle();
          }
          return;
        }
        index = stored.chapterIndex;
        start = Duration(milliseconds: stored.charOffset);
      }
      _markOpen(book);
      _ensureLifecycle();
      final since = _commands;
      final opened = await _load(_playable(index), start: start);
      if (opened && lateProgress != null) {
        unawaited(_catchUpLate(book, lateProgress, since));
      }
    } catch (error, stackTrace) {
      if (generation != _generation) return;
      _fail(failureMessage('開啟有聲書', error, stackTrace));
    }
  }

  /// 從目錄點了某一集：從頭播。
  Future<void> playChapter(int index) async {
    _commands++;
    if (_book == null || _chapters.isEmpty) return;
    await _switchTo(_playable(index));
  }

  /// 使用者換到第 [index] 集（目錄選集、上一集、下一集）：先存好這一集聽到
  /// 哪，再從頭播那一集。按下去就換一次 [_generation]：之前還在做的載入與
  /// 換集作廢；存的這段時間停止、開了別本或又換了集就不換，最後按的那一次
  /// 算數。
  ///
  /// 換集就是要出聲，先記成要播；存的這段時間按了暫停（系統的暫停鍵、定時
  /// 到了）載好才不出聲。上一集播完、回到前景接另一台的進度看 [_switchingTo]，
  /// 不接手。
  Future<void> _switchTo(int index) async {
    final generation = ++_generation;
    _switchingTo = index;
    _wantPlay = true;
    await _saveProgress();
    if (generation != _generation) return;
    await _load(index, start: Duration.zero);
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

  /// 接著上次聽的地方：抓這本書的雲端進度，最多等 [openGrace]，等到了而且
  /// 比這台新就先寫進這台的資料庫，再讀資料庫裡的位置（ADR 0039）。等不及
  /// 的話照這台的位置開，一併傳回還在抓的那一次，晚到時接上
  /// （[_catchUpLate]）。
  Future<(Book, Future<PulledProgress?>?)> _resumePosition(Book book) async {
    final prefetched = _prefetchedProgress;
    _prefetchedProgress = null;
    final pulling =
        prefetched != null &&
            prefetched.bookUrl == book.bookUrl &&
            DateTime.now().difference(prefetched.at) < _prefetchFresh
        ? prefetched.pulling
        : _sync.pullProgress(book.bookUrl);
    Future<PulledProgress?>? late;
    if (await settlesWithin(pulling, openGrace)) {
      try {
        await (await pulling)?.applyBeforeOpen();
      } catch (error, stackTrace) {
        AppLog.e('接上雲端進度失敗', error: error, stackTrace: stackTrace);
      }
    } else {
      late = pulling;
    }
    try {
      final stored = await _books.getByUrl(book.bookUrl);
      if (stored == null) return (book, late);
      // 手上的書之後可能整筆寫回資料庫，位置移動的時間要跟著。
      book.progressTime = stored.progressTime;
      return (stored, late);
    } catch (error, stackTrace) {
      AppLog.e('讀收聽紀錄失敗', error: error, stackTrace: stackTrace);
      return (book, late);
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

  /// 開書時目錄讀到之前（或沒讀成）[_chapters] 是空的、[_index] 已經是上次
  /// 聽的那集，從清單的範圍內往前找。
  int? _previousPlayable(int from) {
    for (var i = min(from, _chapters.length) - 1; i >= 0; i--) {
      if (!_chapters[i].isSkippedWhenReading) return i;
    }
    return null;
  }

  /// 換到第 [index] 集、停在 [start]。[play] 是這次要不要出聲（使用者換集、
  /// 重播是要，回到前景接另一台的進度是不要）；null 照使用者現在的意思（開書、
  /// 播完接下一集、開書後接上晚到的進度）。載入途中按的播放或暫停蓋過它，
  /// 載好照最後的意思播不播。傳回這一集有沒有開好：播不出來、被之後的開書、
  /// 換集、停止取代都是 false。
  Future<bool> _load(int index, {required Duration start, bool? play}) async {
    final book = _book;
    final source = _source;
    // 目錄還沒讀到或沒讀成時沒有集可換（[_previousPlayable]）。
    if (book == null || source == null || index >= _chapters.length) {
      return false;
    }
    // 換集先讓上一集停聲：新的一集抓不到時，不會畫面停在新集、耳朵還聽著
    // 舊集，舊集的位置也不會記到新集上。
    // 等上一集停聲的這段時間停止了、開了別本或又換了集：不再往下做，這時的
    // 書與目錄已經不是按下去時的那一份。
    final entry = _generation;
    final previous = _engine;
    if (previous != null && previous.playing) await previous.pause();
    if (entry != _generation) return false;
    if (play != null) _wantPlay = play;
    final generation = ++_generation;
    // 載入途中被之後的開書、換集、停止取代：這次載入不再往下做。
    bool stale() => generation != _generation;
    final chapter = _chapters[index];
    _index = index;
    if (_switchingTo == index) _switchingTo = null;
    _duration = null;
    _request = null;
    position.value = start;
    _moveTo(AudiobookPhase.loading);
    final engine = _ensureEngine();
    try {
      // 下載好的集放本機檔（ADR 0055），不再問書源。
      final local = await _downloadedFile(book, chapter);
      if (stale()) return false;
      final prefetched = _prefetched;
      final request = local != null
          ? AudioRequest(url: local.uri.toString(), headers: const {})
          : prefetched != null && prefetched.index == index
          ? prefetched.request
          // 聽的時候抓這一集：背景搜尋先讓（ADR 0070）。
          : await ReadingFetches.instance.track(
              () => _sourceService.getAudioRequest(source, book, chapter),
            );
      if (stale()) return false;
      _prefetched = null;
      _request = request;
      await engine.open(
        Uri.parse(request.url),
        headers: request.headers,
        start: start,
      );
      if (stale()) return false;
      await engine.setSpeed(_speed);
      if (stale()) return false;
      _duration = engine.duration;
      _moveTo(engine.playing ? AudiobookPhase.playing : AudiobookPhase.paused);
      if (_wantPlay) await _startPlaying(engine);
      notifyListeners();
      _publish();
      unawaited(_saveProgress());
      unawaited(_prefetch(generation));
      return !stale();
    } catch (error, stackTrace) {
      if (stale()) return false;
      _fail(failureMessage('播放', error, stackTrace));
      _publish();
      return false;
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
      final request = await ReadingFetches.instance.track(
        () => _sourceService.getAudioRequest(source, book, _chapters[next]),
      );
      // 抓的期間換了書源（[reloadBookOrigin]）就不算。
      if (generation == _generation && identical(source, _source)) {
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
    _commands++;
    final book = _book;
    final engine = _engine;
    switch (_phase) {
      case AudiobookPhase.idle:
        return;
      // 打不開：按播放就是重試，接著上次聽的地方。
      case AudiobookPhase.openFailed:
        if (book != null) await open(book);
      // 這一集播不出來：從停下的地方重新載入；播完了：從這一集開頭。
      case AudiobookPhase.failed:
        await _load(_index, start: position.value, play: true);
      case AudiobookPhase.ended:
        await _load(_index, start: Duration.zero, play: true);
      // 還在開書或載入：只記下要出聲，載好才播。引擎裡還是上一集（或停掉
      // 的上一本），現在叫它播會先出上一集的聲音。
      case AudiobookPhase.opening || AudiobookPhase.loading:
        _wantPlay = true;
      case AudiobookPhase.playing || AudiobookPhase.paused:
        if (engine == null) return;
        _wantPlay = true;
        await _startPlaying(engine);
    }
  }

  /// 暫停：存好進度馬上送，另一台切過去時接得上。
  Future<void> pause() async {
    _commands++;
    _wantPlay = false;
    _lastSent = null;
    await _engine?.pause();
    await _saveProgress();
    if (_book != null) _sync.requestSyncProgressFirst();
  }

  Future<void> toggle() => playing ? pause() : play();

  Future<void> seek(Duration to) async {
    _commands++;
    final engine = _engine;
    if (engine == null) return;
    switch (_phase) {
      // 還沒有開好的一集：引擎裡是上一集，拖了會把位置記到新的一集上。
      case AudiobookPhase.idle ||
          AudiobookPhase.opening ||
          AudiobookPhase.openFailed ||
          AudiobookPhase.loading:
        return;
      // 播完後拖回去：停在拖到的地方，按播放從這裡接著播，不再從開頭；引擎
      // 還沒拖好就按播放也一樣。
      case AudiobookPhase.ended:
        _moveTo(AudiobookPhase.paused);
      case AudiobookPhase.playing ||
          AudiobookPhase.paused ||
          AudiobookPhase.failed:
    }
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
      _nextPlayable(_index) != null ||
      (_mode == AudiobookPlayMode.listLoop && _chapters.isNotEmpty);

  Future<void> next() async {
    _commands++;
    final next =
        _nextPlayable(_index) ??
        (_mode == AudiobookPlayMode.listLoop ? _playable(0) : null);
    if (next == null) return;
    await _switchTo(next);
  }

  Future<void> previous() async {
    _commands++;
    final previous = _previousPlayable(_index);
    if (previous == null) return;
    await _switchTo(previous);
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
    _commands++;
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
    _inUse?.release();
    _inUse = null;
    _source = null;
    _chapters = const [];
    _prefetched = null;
    _request = null;
    _wantPlay = false;
    _switchingTo = null;
    _buffering = false;
    _lastSent = null;
    _phase = AudiobookPhase.idle;
    _failure = null;
    sleepTimer.sync(active: false, running: false);
    _playback.release(this);
    if (_markedOpen) {
      _sync.closeBook(book);
      _markedOpen = false;
    }
    _sync.uploadsOnHide(this, false);
    _sync.requestSyncProgressFirst();
  }

  Future<void> _onCompleted() async {
    // 播完只在這一集開好時算；引擎回報播完時可能已經先報了停（暫停）。
    if (_phase != AudiobookPhase.playing && _phase != AudiobookPhase.paused) {
      return;
    }
    // 正在換到別集（等存進度）：讀者選的那一集算數，不自動接下一集。
    if (_switchingTo != null) return;
    final generation = _generation;
    switch (_mode) {
      case AudiobookPlayMode.singleLoop:
        await _replay(generation);
      case AudiobookPlayMode.shuffle:
        final candidates = [
          for (var i = 0; i < _chapters.length; i++)
            if (!_chapters[i].isSkippedWhenReading && i != _index) i,
        ];
        if (candidates.isEmpty) {
          await _replay(generation);
        } else {
          final pick = candidates[_random.nextInt(candidates.length)];
          await _load(pick, start: Duration.zero);
        }
      case AudiobookPlayMode.listLoop:
      case AudiobookPlayMode.inOrder:
        final next =
            _nextPlayable(_index) ??
            (_mode == AudiobookPlayMode.listLoop ? _playable(0) : null);
        if (next != null) {
          await _load(next, start: Duration.zero);
        } else if (generation == _generation) {
          // 最後一集聽完：停在結尾，再按播放從這一集開頭。
          _moveTo(AudiobookPhase.ended);
          _publish();
          await _engine?.pause();
          await _saveProgress();
        }
    }
  }

  /// 單集循環（與隨機只剩這一集）：從頭再播這一集。回到開頭要存進度，等的
  /// 途中按了暫停、換了集或停了就不播（[_startPlaying]）。
  Future<void> _replay(int generation) async {
    await seek(Duration.zero);
    final engine = _engine;
    if (engine == null || generation != _generation) return;
    await _startPlaying(engine);
  }

  // --- 引擎事件 ---

  /// 引擎回報播或停：只在這一集開好時換播著或暫停；載入中是上一集停聲，
  /// 播完、播不出來時引擎跟著停，都不改階段。
  void _onPlaying(bool playing) {
    final AudiobookPhase next;
    switch ((_phase, playing)) {
      case (AudiobookPhase.paused, true):
        next = AudiobookPhase.playing;
      case (AudiobookPhase.playing, false):
        next = AudiobookPhase.paused;
      default:
        return;
    }
    _moveTo(next);
    if (!playing) unawaited(_saveProgress());
    _publish();
  }

  void _onPosition(Duration at) {
    if (_phase == AudiobookPhase.opening || _phase == AudiobookPhase.loading) {
      return;
    }
    position.value = at;
    final last = _lastSaved;
    if (playing && (last == null || _now().difference(last) >= saveInterval)) {
      unawaited(
        _uploadDue()
            ? _saveProgress().whenComplete(_sync.requestSyncProgressFirst)
            : _saveProgress(),
      );
    }
  }

  /// 播著時到了該送進度的時候（[uploadInterval]）。剛開始播時從這時起算。
  bool _uploadDue() {
    final now = _now();
    final last = _lastSent;
    if (last != null && now.difference(last) < uploadInterval) return false;
    _lastSent = now;
    return last != null;
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
  /// 開書中、載入這一集時引擎送來的錯是上一集（或上一本）的：這一集開不了
  /// 由 [AudioEngine.open] 丟出來，在 [_load] 接，不從這裡算。
  void _onError(Object error) {
    switch (_phase) {
      case AudiobookPhase.idle ||
          AudiobookPhase.opening ||
          AudiobookPhase.loading:
        return;
      default:
    }
    _fail(failureMessage('播放', error));
    unawaited(_engine?.pause());
    _publish();
  }

  // --- 進度與同步 ---

  /// 現在聽到哪寫進書與資料庫（換源前用：照它對到新書源的同一集）。
  Future<void> saveProgress() => _saveProgress();

  /// 存好這一集聽到哪；傳回有沒有存成。
  Future<bool> _saveProgress() async {
    if (_phase == AudiobookPhase.opening) return false;
    final book = _book;
    final indexAtSave = _index;
    final chapter = this.chapter;
    if (book == null || chapter == null) return false;
    final ms = position.value.inMilliseconds;
    _lastSaved = _now();
    book
      ..chapterIndex = _index
      ..durChapterTitle = chapter.title
      ..charOffset = ms;
    try {
      // 播放器開著時書架檢查更新可能已換上新目錄、集數重新編號（書源在前面
      // 插了幾集）；播放器手上仍是開書時的目錄。寫進資料庫的序號照這一集的
      // 網址換成目前目錄的（書源換了網址的照換目錄時記下的新網址，換了網址
      // 又換了集數、只認得集名的照集名，[MovedChapters]），重開才接回同一
      // 集；新目錄裡沒有這一集時照播放器的序號寫。同文字閱讀器
      // （`ReaderProgressController`）與漫畫閱讀器。
      final chapters = _chapterStore;
      int? moved;
      await chapters.transaction(() async {
        // 手上的書照舊記播放器目錄的序號：換源照這份目錄估位置。
        final index =
            await MovedChapters.indexOf(
              chapters,
              book.bookUrl,
              chapter.url,
              title: chapter.title,
              oldIndex: indexAtSave,
              oldTotalCount: _chapters.length,
            ) ??
            indexAtSave;
        moved = await _books.updateProgress(
          book.bookUrl,
          index,
          chapter.title,
          ms,
        );
      });
      if (moved case final time?) book.progressTime = time;
      return true;
    } catch (error, stackTrace) {
      AppLog.e('存收聽進度失敗', error: error, stackTrace: stackTrace);
      return false;
    }
  }

  void _markOpen(Book book) {
    if (_markedOpen) return;
    _sync.openBook(book);
    _sync.uploadsOnHide(this, true);
    _markedOpen = true;
  }

  void _ensureLifecycle() {
    _lifecycle ??= AppLifecycleListener(
      onHide: () {
        // 停止之後沒有要送的，退到背景由主畫面照常同步。
        if (_book == null) return;
        unawaited(_saveProgress().whenComplete(_sync.requestSyncProgressFirst));
      },
      onShow: () => unawaited(_catchUpAfterResume()),
    );
  }

  /// 這一集開好了、沒在出聲：暫停、播不出來或播完。
  bool get _canCatchUp => switch (_phase) {
    AudiobookPhase.paused ||
    AudiobookPhase.failed ||
    AudiobookPhase.ended => true,
    _ => false,
  };

  /// 回到前景時沒在播：另一台聽到較新的地方，播放器頁開著就先問要不要跳
  /// 過去（停在那裡，不自動播）；頁沒開著（只剩收聽圓鈕）照原本直接換過去，
  /// 不動畫面上的正文。沒按就不跳、不記成同步過。
  Future<void> _catchUpAfterResume() async {
    final book = _book;
    // 開書中、打不開（沒有目錄）跳不過去；正在換集（等存進度）時讀者選的
    // 那一集算數；不跳就不記成同步過，下次還會再抓到。
    if (book == null || !_canCatchUp || _switchingTo != null) return;
    final since = _commands;
    final pulled = await _sync.pullProgress(book.bookUrl);
    if (pulled == null || !pulled.isCurrent || !isCurrent(book)) return;
    // 抓的這段時間按了什麼（播放、暫停、換集、拖動）：照使用者按的，不問。
    // 還在等系統接手、重載還沒出聲時，階段、集數與位置都還沒變，只看得出
    // 按過。
    if (_commands != since || !_canCatchUp || _switchingTo != null) return;
    if (_progressSuggestions.hasListener) {
      _offerProgress(book, pulled, since, play: false);
    } else {
      await _jumpToPulled(book, pulled, since, play: false);
    }
  }

  /// 開書時雲端進度還沒抓到、先照這台的位置開了（開好就播）：抓到時讀者
  /// 沒按過什麼（[since] 之後，播著時位置自己往前走不算），播放器頁開著就
  /// 問要不要換到另一台聽到的地方，照樣播著；頁沒開著照原本直接換過去。
  Future<void> _catchUpLate(
    Book book,
    Future<PulledProgress?> pulling,
    int since,
  ) async {
    final pulled = await pulling;
    if (pulled == null || !pulled.isCurrent || !isCurrent(book)) return;
    if (_commands != since || _switchingTo != null) return;
    if (_phase != AudiobookPhase.playing && _phase != AudiobookPhase.paused) {
      return;
    }
    // 播著的這段時間已經聽過另一台停的地方：這台才是最新的，不倒回去。
    if (_phase == AudiobookPhase.playing && !_aheadOfHere(book, pulled)) return;
    if (_progressSuggestions.hasListener) {
      _offerProgress(book, pulled, since);
    } else {
      await _jumpToPulled(book, pulled, since);
    }
  }

  /// 正文已經在畫面上才抓到比這台新的進度：位置一樣就照舊記成同步過；
  /// 不一樣就交給播放器頁問，不自己跳。頁面沒開著時沒人聽。
  void _offerProgress(
    Book book,
    PulledProgress pulled,
    int since, {
    bool? play,
  }) {
    final index = _pulledIndex(book, pulled);
    final at = Duration(milliseconds: pulled.progress.charOffset);
    if (index == _index && at == position.value) {
      unawaited(_jumpToPulled(book, pulled, since, play: play));
      return;
    }
    final serial = ++_suggestionSerial;
    _progressSuggestions.add(
      AudiobookProgressSuggestion(
        message: audiobookNewerProgressNotice,
        jump: () async {
          // 按下時再確認：沒被下一則取代、提示出現後沒按過什麼、還是這本與
          // 同一個同步空間，播著的話還沒聽過另一台停的地方（不倒回去）。
          if (serial != _suggestionSerial ||
              _commands != since ||
              !isCurrent(book) ||
              !pulled.isCurrent ||
              (_phase == AudiobookPhase.playing &&
                  !_aheadOfHere(book, pulled))) {
            return;
          }
          await _jumpToPulled(book, pulled, since, play: play);
        },
      ),
    );
  }

  /// 另一台停的地方（集、毫秒）在這台正在播的位置之後。
  bool _aheadOfHere(Book book, PulledProgress pulled) {
    final index = _pulledIndex(book, pulled);
    return index > _index ||
        (index == _index &&
            pulled.progress.charOffset > position.value.inMilliseconds);
  }

  int _pulledIndex(Book book, PulledProgress pulled) => _playable(
    pulled.progress.chapterIndexIn([
      for (final chapter in _chapters) chapter.title,
    ], reversed: book.getReverseToc()),
  );

  /// 換到另一台聽到的那一集的那一毫秒，位置完全一樣才不動；接上、存好才
  /// 記成同步過。[play] 同 [_load]。
  Future<void> _jumpToPulled(
    Book book,
    PulledProgress pulled,
    int since, {
    bool? play,
  }) async {
    final index = _pulledIndex(book, pulled);
    final at = Duration(milliseconds: pulled.progress.charOffset);
    if (index != _index || at != position.value) {
      // 那一集播不出來、被別的動作取代：沒接上，不記成同步過，下次再抓。
      if (!await _load(index, start: at, play: play)) return;
    }
    // 載入途中停止、開了別本或換了集（在目錄選了別集）：沒接上，不記成
    // 同步過，下次回到前景再抓。
    if (_commands != since ||
        _switchingTo != null ||
        !isCurrent(book) ||
        _index != index) {
      return;
    }
    if (!await _saveProgress()) return;
    // 存進度的途中又按了什麼：這次接的進度沒留住，同樣不記。
    if (_commands != since || _switchingTo != null || !isCurrent(book)) return;
    try {
      // 存檔記的是這台的時間；記成不比雲端那一筆早，之後往前聽的才比另一台
      // 記的新（`BookDao.markProgressSynced`）。
      final time = await _books.markProgressSynced(
        book.bookUrl,
        syncedTime: pulled.progress.time,
      );
      if (time == null) return;
      book.progressTime = time;
    } catch (error, stackTrace) {
      AppLog.e('存收聽進度失敗', error: error, stackTrace: stackTrace);
      return;
    }
    await pulled.commit(ProgressSync.recordOf(book));
  }

  // --- 系統播放資訊 ---

  /// 開始播：先接手系統播放資訊（原本在播的朗讀收到暫停），再讓引擎播。
  /// 叫引擎出聲都經過這裡：還要出聲、還是同一次載入、這一集開好了才播；
  /// 要不到音訊焦點（通話中、別的 App 正在出聲）不播，留在暫停並說一聲。
  Future<void> _startPlaying(AudioEngine engine) async {
    final generation = _generation;
    await _playback.start();
    // 等系統播放控制的這段時間按了暫停、換了集或停了：不出聲。
    bool ready() =>
        _wantPlay &&
        generation == _generation &&
        (_phase == AudiobookPhase.playing || _phase == AudiobookPhase.paused);
    if (!ready()) return;
    // `audio_session` 已經要過焦點時會直接回「給了」，不再問系統：通話中
    // 按播放也說給了。焦點整個 App 一份（[AudioFocus]），和有聲書原本的
    // 打斷處理照同一份走，通話中的這一下由這裡擋住。
    if (!await _audioFocus.request()) {
      if (!ready()) return;
      _wantPlay = false;
      _notices.add(audiobookNoAudioFocusNotice);
      if (_phase == AudiobookPhase.playing) {
        await engine.pause();
        _moveTo(AudiobookPhase.paused);
      } else {
        notifyListeners();
      }
      return;
    }
    if (!ready()) return;
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
        coverOrigin: book.origin,
        kind: BookSourceKind.audio,
        duration: _duration,
      ),
      playing: playing ?? this.playing,
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
    unawaited(_moves.cancel());
    _lifecycle?.dispose();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_engine?.dispose());
    _inUse?.release();
    sleepTimer.dispose();
    position.dispose();
    unawaited(_notices.close());
    unawaited(_progressSuggestions.close());
    super.dispose();
  }
}
