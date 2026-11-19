import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/search/search_book.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/background_work/reading_fetches.dart';

import 'models/search_scope.dart';
import 'search_model.dart';

/// 一次搜尋用的條件：[kind] 是搜尋頁上選的類別，[byKind] 是有沒有照類別送
/// 與篩（書源不只一類時才照類別），[scope] 是範圍（[SearchScope] 的字串）。
typedef SearchConditions = ({
  BookSourceKind kind,
  bool byKind,
  String scope,
  bool precision,
});

/// 一個書源搜尋失敗的原因，與當時的書源名稱（書源之後被刪掉也寫得出來）。
typedef SearchFailureNote = ({String name, String message});

/// 剩下的書源不超過這個數時，進度改列出還在等哪幾個；三個名稱大致排得進
/// 一行。
const int namedWaitingLimit = 3;

/// 搜尋進度那一列的字，通知內文也用同一句（ADR 0058、0070）。
String searchProgressText({
  required int completed,
  required int total,
  required List<String> waiting,
}) {
  final remaining = total - completed;
  if (total > 0 && remaining <= namedWaitingLimit && waiting.isNotEmpty) {
    return '還在等：${waiting.join('、')}';
  }
  return total > 0 ? '正在搜尋 $completed/$total' : '正在搜尋';
}

/// 放到背景的搜尋記下每個書源搜完的樣子（[SearchRun.recorder]）。
abstract interface class SearchRecorder {
  /// 這次要搜的書源排好了。
  void sourcesChosen();

  /// [url] 這個書源搜完：搜到 [books]（零本也算），或失敗（[failure]）。
  void sourceDone(
    String url,
    List<SearchBook>? books,
    SearchFailureNote? failure,
  );
}

/// 進度的訂閱與結果清單分開，書源每次送出或回來不必重建搜尋結果。
class _ProgressUpdates extends ChangeNotifier {
  void publish() => notifyListeners();
}

/// 一次搜尋的進行與結果：搜尋頁（[SearchProvider]）訂閱它、畫它。放到背景時
/// 這一份交給背景工作，搜尋頁關了照跑，再打開時接回同一份（ADR 0070）。
///
/// 結果與狀態變了通知自己的監聽者；只有進度、等待中的書源與失敗變了時通知
/// [progressUpdates]。
class SearchRun extends ChangeNotifier implements SearchModelCallback {
  SearchRun({this._loader, ReadingFetches? readingFetches})
    : _readingFetches = readingFetches ?? ReadingFetches.instance {
    _model = _newModel();
  }

  /// 讀回的暫停中或做完的搜尋：結果還沒合併成卡，搜尋頁打開、進場播完才
  /// 合（[mergeRestored]）。
  SearchRun.restored({
    this._loader,
    ReadingFetches? readingFetches,
    required this.key,
    required SearchConditions this.conditions,
    required List<String> sourceUrls,
    required Map<String, List<SearchBook>> searched,
    required Map<String, SearchFailureNote> failed,
  }) : _readingFetches = readingFetches ?? ReadingFetches.instance,
       _sourceUrls = sourceUrls,
       _unmerged = true {
    _model = _newModel();
    _searched.addAll(searched);
    _failedNotes.addAll(failed);
    completed = searched.length + failed.length;
    total = sourceUrls.length;
    this.failed = failed.length;
    searchedSourceCount = total;
  }

  /// 照 [other] 現在的樣子（條件、結果、失敗）另開一份，給接回的背景搜尋
  /// 做完後重試失敗的書源：重試是普通的搜尋，不屬於背景那件。
  SearchRun.copyOf(SearchRun other)
    : _loader = other._loader,
      _readingFetches = other._readingFetches,
      _sourceUrls = other._sourceUrls {
    _model = _newModel();
    key = other.key;
    conditions = other.conditions;
    scopeAsked = other.scopeAsked;
    results = other.results;
    failures.addAll(other.failures);
    _searched.addAll(other._searched);
    _failedNotes.addAll(other._failedNotes);
    completed = other.completed;
    total = other.total;
    failed = other.failed;
    searchedSourceCount = other.searchedSourceCount;
  }

  SearchModel _newModel() => SearchModel(callback: this, loader: _loader)
    ..onSourcesChosen = _rememberSources
    ..onScopeNarrowed = _narrowScope
    ..onSourceSearched = _recordSearched;

  final SearchBookLoader? _loader;
  final ReadingFetches _readingFetches;
  late final SearchModel _model;

  /// 這次搜的關鍵字；還沒搜過是空的。
  String key = '';

  /// 這次搜尋的條件；還沒搜過是 null。
  SearchConditions? conditions;

  List<SearchBook> results = const [];
  bool isSearching = false;

  /// 已經送出、還沒回來的書源名稱。
  List<String> waitingSources = const [];
  int completed = 0;
  int total = 0;
  int failed = 0;
  final List<SearchFailure> failures = [];

  /// 這次搜尋的書源總數；重試失敗書源時不會被縮成重試的數量。
  int searchedSourceCount = 0;
  bool _retrying = false;

  final _ProgressUpdates _progress = _ProgressUpdates();
  Listenable get progressUpdates => _progress;

  /// 接著搜暫停的搜尋時，前面已經搜完的書源數與失敗：進度接著數。
  int _doneBefore = 0;
  List<SearchFailure> _failuresBefore = const [];

  /// 這次要搜的書源網址，照送出順序；每個書源搜完的結果與失敗。
  List<String> get sourceUrls => _sourceUrls;
  List<String> _sourceUrls = const [];
  Map<String, List<SearchBook>> get searched => _searched;
  final Map<String, List<SearchBook>> _searched = {};
  Map<String, SearchFailureNote> get failedNotes => _failedNotes;
  final Map<String, SearchFailureNote> _failedNotes = {};

  /// 下一次選好書源時記下（新的一次搜尋；重試與接著搜不改）。
  bool _choosing = false;

  bool _unmerged = false;
  bool _disposed = false;

  /// 讀回的結果還沒合併成卡。
  bool get isRestoring => _unmerged;

  /// 放到背景之後記下每個書源的那一位。
  SearchRecorder? recorder;

  /// 放到背景了：不跟著頁面暫停，送每個書源前先等閱讀時的抓章。
  bool get background => _background;
  bool _background = false;
  set background(bool value) {
    _background = value;
    _model.beforeSource = value ? _readingFetches.idle : null;
    if (value) _model.resume();
  }

  /// 正在跑的這次搜尋，結束（做完、結束、暫停或取消）時完成。
  Future<void>? get running => _attempt?.future;
  Completer<void>? _attempt;

  /// [begin] 之後、[start] 之前（頁面在存搜尋紀錄）：這段時間按了結束、
  /// 暫停或開始新的一次，[start] 就不開始。
  int _ticket = 0;
  bool _pending = false;

  /// 送出搜尋後、引擎真正開始前（存歷史、讀書源清單）就先進入搜尋中，這段
  /// 空檔才不會閃出空狀態，也擋住重複送出。傳回給 [start] 的號碼。
  int begin(String key, SearchConditions conditions) {
    // 上一次馬上停：存歷史這段空檔裡它回來的結果與範圍不算進這一次。
    _model.cancelSearch();
    this.key = key;
    this.conditions = conditions;
    scopeAsked = null;
    results = const [];
    failures.clear();
    _searched.clear();
    _failedNotes.clear();
    _sourceUrls = const [];
    _doneBefore = 0;
    _failuresBefore = const [];
    _unmerged = false;
    _choosing = true;
    isSearching = true;
    completed = 0;
    total = 0;
    failed = 0;
    waitingSources = const [];
    _startAttempt();
    _pending = true;
    notifyListeners();
    return ++_ticket;
  }

  void _startAttempt() {
    final previous = _attempt;
    _attempt = Completer<void>();
    if (previous != null && !previous.isCompleted) previous.complete();
  }

  void _endAttempt() {
    final attempt = _attempt;
    if (attempt != null && !attempt.isCompleted) attempt.complete();
  }

  Future<void> _track(Future<void> work) async {
    final attempt = _attempt ??= Completer<void>();
    try {
      await work;
    } finally {
      if (!attempt.isCompleted) attempt.complete();
    }
  }

  /// 照 [begin] 的條件開始搜；[ticket] 不是最後一次 [begin] 的、或這段時間
  /// 按了結束或暫停時不開始。
  Future<void> start(int ticket) {
    if (_disposed || ticket != _ticket || !_pending) {
      return Future<void>.value();
    }
    _pending = false;
    return _searchByConditions();
  }

  Future<void> _searchByConditions() {
    final conditions = this.conditions!;
    return _track(
      _model.search(
        key: key,
        scope: SearchScope(conditions.scope),
        precisionSearch: conditions.precision,
        kind: conditions.byKind ? conditions.kind : null,
      ),
    );
  }

  /// 「重試失敗」重試得了的書源：照網址讀現在的書源（同接著搜暫停的搜尋）。
  /// 失敗之後刪掉、停用的略過，它們的失敗從畫面與結果檔一起拿掉；全部略過
  /// 時沒有失敗可列，「重試失敗」跟著不在。
  Future<List<BookSource>> retryableSources() async {
    final enabled = {
      for (final source in await getIt<BookSourceDao>().getEnabled())
        if (source.isSearchEnabledByRuntime) source.bookSourceUrl: source,
    };
    if (_disposed) return const [];
    final skipped = {
      for (final failure in failures)
        if (!enabled.containsKey(failure.source.bookSourceUrl))
          failure.source.bookSourceUrl,
    };
    if (skipped.isNotEmpty) {
      failures.removeWhere((f) => skipped.contains(f.source.bookSourceUrl));
      skipped.forEach(_failedNotes.remove);
      failed = failures.length;
      notifyListeners();
    }
    return [
      for (final failure in failures) enabled[failure.source.bookSourceUrl]!,
    ];
  }

  Future<void> retryFailed() async {
    if (key.isEmpty || failures.isEmpty || isSearching) return;
    final ticket = _ticket;
    final sources = await retryableSources();
    // 讀書源的時候開始了新的一次或另一次重試，這次就不重試。
    if (_disposed || ticket != _ticket || isSearching || sources.isEmpty) {
      return;
    }
    final existing = List<SearchBook>.from(results);
    failures.clear();
    _failuresBefore = const [];
    _doneBefore = 0;
    _startAttempt();
    notifyListeners();
    _retrying = true;
    try {
      await _track(
        _model.searchSources(
          key: key,
          sources: sources,
          precisionSearch: conditions!.precision,
          initialResults: existing,
        ),
      );
    } finally {
      _retrying = false;
    }
  }

  /// 接著搜暫停的搜尋：只搜 [remaining]，前面搜完的結果帶著、進度接著數。
  /// 這次要搜、這段時間刪掉或停用的書源算搜完。還沒選好書源就暫停的
  /// （[remaining] 是 null）照條件重新搜。
  Future<void> continueWith(List<BookSource>? remaining) async {
    await mergeRestored();
    // 引擎真正開始前（讀字典、讀同時搜幾個）就算搜尋中，不閃出工具列。
    isSearching = true;
    _startAttempt();
    notifyListeners();
    if (remaining == null) {
      _choosing = true;
      await _searchByConditions();
      return;
    }
    _doneBefore = _sourceUrls.length - remaining.length;
    _failuresBefore = List.of(failures);
    await _track(
      _model.searchSources(
        key: key,
        sources: remaining,
        precisionSearch: conditions!.precision,
        initialResults: [for (final books in _searched.values) ...books],
      ),
    );
  }

  /// 讀回的結果合成搜尋頁的卡、找回失敗的書源，並把搜到的書放回搜尋快取
  /// （開 App 時清掉了；從結果進書籍詳情後換源、換封面先列它們）；只做一次。
  Future<void> mergeRestored() async {
    if (!_unmerged) return;
    _unmerged = false;
    final raw = [for (final books in _searched.values) ...books];
    results = SearchModel.cardsOf(raw, key, conditions!.precision);
    final dao = getIt<BookSourceDao>();
    for (final MapEntry(key: url, value: note) in _failedNotes.entries) {
      // 書源之後被刪掉的照樣列出原因，只是不能重試。
      final source =
          await dao.getByUrl(url) ??
          BookSource(
            bookSourceUrl: url,
            bookSourceName: note.name,
            enabled: false,
          );
      failures.add(SearchFailure(source: source, message: note.message));
    }
    if (_disposed) return;
    failed = failures.length;
    notifyListeners();
    if (raw.isNotEmpty) {
      try {
        await getIt<SearchBookDao>().insertList(raw);
      } catch (error) {
        AppLog.w('SearchRun: 讀回的結果沒放回搜尋快取：$error');
      }
    }
  }

  /// 使用者按「結束」：已經收到的結果照常併入，再停下。
  void stop() {
    _model.stopSearch();
    isSearching = false;
    waitingSources = const [];
    _endAttemptIfPending();
    notifyListeners();
  }

  /// 暫停放到背景的搜尋：已經收到的結果照常併入，不再送書源，正在搜的取消
  /// （繼續時重搜它們）。
  void halt() {
    _model.stopSearch();
    _endAttemptIfPending();
  }

  /// 還沒開始就結束或暫停：等著它的背景工作不必等存搜尋紀錄。
  void _endAttemptIfPending() {
    if (!_pending) return;
    _pending = false;
    _endAttempt();
  }

  /// 暫停好了：不在搜尋中，進度停在那裡。
  void markPaused() {
    isSearching = false;
    waitingSources = const [];
    notifyListeners();
  }

  /// 搜尋頁被整頁蓋住時暫停還沒送出的書源（放到背景的不暫停）。
  void pause() {
    if (!_background) _model.pause();
  }

  void resume() => _model.resume();

  bool get isPaused => _model.isPaused;

  /// 範圍被引擎改掉之前選的那個（[_narrowScope]）；沒改過是 null。
  String? scopeAsked;

  /// 實際搜的範圍記進條件：頁首照它（照 Legado，分組清掉了就寫清掉後的）。
  void _narrowScope(String scope) {
    final c = conditions;
    if (c == null) return;
    scopeAsked ??= c.scope;
    conditions = (
      kind: c.kind,
      byKind: c.byKind,
      scope: scope,
      precision: c.precision,
    );
    notifyListeners();
  }

  void _rememberSources(List<BookSource> sources) {
    if (!_choosing) return;
    _choosing = false;
    _sourceUrls = [for (final source in sources) source.bookSourceUrl];
    recorder?.sourcesChosen();
  }

  void _recordSearched(BookSource source, List<SearchBook> books) {
    final url = source.bookSourceUrl;
    _searched[url] = books;
    _failedNotes.remove(url);
    recorder?.sourceDone(url, books, null);
  }

  // ═══════════════════════════════════════════
  // SearchModelCallback
  // ═══════════════════════════════════════════

  @override
  void onSearchStart() {
    isSearching = true;
    failed = _failuresBefore.length;
    completed = _doneBefore;
    total = _doneBefore;
    waitingSources = const [];
    failures
      ..clear()
      ..addAll(_failuresBefore);
    notifyListeners();
  }

  @override
  void onSearchSuccess(List<SearchBook> searchBooks) {
    results = searchBooks;
    notifyListeners();
  }

  @override
  void onSearchFailure(SearchFailure failure) {
    failures.add(failure);
    final url = failure.source.bookSourceUrl;
    final note = (
      name: failure.source.bookSourceName,
      message: failure.message,
    );
    _failedNotes[url] = note;
    _searched.remove(url);
    recorder?.sourceDone(url, null, note);
    _progress.publish();
  }

  @override
  void onSearchFinish({required bool isEmpty}) {
    isSearching = false;
    notifyListeners();
  }

  @override
  void onSearchProgress({
    required List<String> waitingSources,
    required int completed,
    required int total,
    required int failed,
  }) {
    this.waitingSources = waitingSources;
    this.completed = _doneBefore + completed;
    this.total = _doneBefore + total;
    this.failed = _failuresBefore.length + failed;
    if (!_retrying) searchedSourceCount = this.total;
    _progress.publish();
  }

  bool get isDisposed => _disposed;

  @override
  void dispose() {
    _disposed = true;
    _model.dispose();
    _endAttempt();
    _progress.dispose();
    super.dispose();
  }
}
