import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/reading_fetches.dart';

import 'models/search_scope.dart';
import 'search_model.dart';

/// 一次搜尋用的條件：[kind] 是搜尋頁上選的類別，[byKind] 是有沒有照類別送
/// （書源不只一類時才照類別），[scope] 是範圍（[SearchScope] 的字串）。
typedef SearchConditions = ({
  BookSourceKind kind,
  bool byKind,
  String scope,
  bool precision,
});

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

  /// [url] 這個書源搜完：搜到 [books]（零本也算），或失敗、原因是 [failure]。
  void sourceDone(String url, List<SearchBook>? books, String? failure);
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
  SearchRun({SearchBookLoader? loader}) {
    _model = SearchModel(callback: this, loader: loader)
      ..onSourcesChosen = _rememberSources
      ..onSourceSearched = _recordSearched;
  }

  /// 讀回的暫停中或做完的搜尋：結果還沒合併成卡，搜尋頁打開、進場播完才
  /// 合（[mergeRestored]）。
  SearchRun.restored({
    SearchBookLoader? loader,
    required this.key,
    required SearchConditions this.conditions,
    required List<String> sourceUrls,
    required Map<String, List<SearchBook>> searched,
    required Map<String, String> failed,
  }) : _sourceUrls = sourceUrls,
       _unmerged = true {
    _model = SearchModel(callback: this, loader: loader)
      ..onSourcesChosen = _rememberSources
      ..onSourceSearched = _recordSearched;
    _searched.addAll(searched);
    _failedReasons.addAll(failed);
    completed = searched.length + failed.length;
    total = sourceUrls.length;
    this.failed = failed.length;
    searchedSourceCount = total;
  }

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

  /// 這次要搜的書源網址，照送出順序；每個書源搜完的結果與失敗原因。
  List<String> get sourceUrls => _sourceUrls;
  List<String> _sourceUrls = const [];
  Map<String, List<SearchBook>> get searched => _searched;
  final Map<String, List<SearchBook>> _searched = {};
  Map<String, String> get failedReasons => _failedReasons;
  final Map<String, String> _failedReasons = {};

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
    _model.beforeSource = value ? ReadingFetches.instance.idle : null;
    if (value) _model.resume();
  }

  /// 正在跑的這次搜尋，結束（做完、結束或取消）時完成。
  Future<void>? get running => _attempt?.future;
  Completer<void>? _attempt;

  /// 送出搜尋後、引擎真正開始前（存歷史、讀書源清單）就先進入搜尋中，這段
  /// 空檔才不會閃出空狀態，也擋住重複送出。
  void begin(String key, SearchConditions conditions) {
    this.key = key;
    this.conditions = conditions;
    results = const [];
    failures.clear();
    _searched.clear();
    _failedReasons.clear();
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
    notifyListeners();
  }

  void _startAttempt() {
    final previous = _attempt;
    _attempt = Completer<void>();
    if (previous != null && !previous.isCompleted) previous.complete();
  }

  Future<void> _track(Future<void> work) async {
    final attempt = _attempt ??= Completer<void>();
    try {
      await work;
    } finally {
      if (!attempt.isCompleted) attempt.complete();
    }
  }

  /// 照 [begin] 的條件在 [scope] 裡搜；[kind] 是只送給哪一類的書源。
  Future<void> searchIn(SearchScope scope, {BookSourceKind? kind}) {
    if (_disposed) return Future<void>.value();
    return _track(
      _model.search(
        key: key,
        scope: scope,
        precisionSearch: conditions!.precision,
        kind: kind,
      ),
    );
  }

  /// 照 [begin] 的條件只搜 [sources]。
  Future<void> searchSources(List<BookSource> sources) {
    if (_disposed) return Future<void>.value();
    return _track(
      _model.searchSources(
        key: key,
        sources: sources,
        precisionSearch: conditions!.precision,
      ),
    );
  }

  Future<void> retryFailed() async {
    if (key.isEmpty || failures.isEmpty || isSearching) return;
    final sources = failures
        .map((failure) => failure.source)
        .where((source) => source.isSearchEnabledByRuntime)
        .toList();
    if (sources.isEmpty) return;
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
  /// 這次要搜、這段時間刪掉或停用的書源算搜完。
  Future<void> continueWith(List<BookSource> remaining) async {
    await mergeRestored();
    _doneBefore = _sourceUrls.length - remaining.length;
    _failuresBefore = List.of(failures);
    _startAttempt();
    await _track(
      _model.searchSources(
        key: key,
        sources: remaining,
        precisionSearch: conditions!.precision,
        initialResults: [for (final books in _searched.values) ...books],
      ),
    );
  }

  /// 讀回的結果合成搜尋頁的卡、找回失敗的書源；只做一次。
  Future<void> mergeRestored() async {
    if (!_unmerged) return;
    _unmerged = false;
    results = SearchModel.cardsOf(
      [for (final books in _searched.values) ...books],
      key,
      conditions!.precision,
    );
    final dao = getIt<BookSourceDao>();
    for (final MapEntry(key: url, value: message) in _failedReasons.entries) {
      final source = await dao.getByUrl(url);
      if (source != null) {
        failures.add(SearchFailure(source: source, message: message));
      }
    }
    if (_disposed) return;
    failed = failures.length;
    notifyListeners();
  }

  /// 使用者按「結束」：已經收到的結果照常併入，再停下。
  void stop() {
    _model.stopSearch();
    isSearching = false;
    waitingSources = const [];
    notifyListeners();
  }

  /// 停下、不再送書源，正在搜的取消（暫停放到背景的搜尋）；它們的結果不收。
  void cancel() => _model.cancelSearch();

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

  void _rememberSources(List<BookSource> sources) {
    if (!_choosing) return;
    _choosing = false;
    _sourceUrls = [for (final source in sources) source.bookSourceUrl];
    recorder?.sourcesChosen();
  }

  void _recordSearched(BookSource source, List<SearchBook> books) {
    final url = source.bookSourceUrl;
    _searched[url] = books;
    _failedReasons.remove(url);
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
    _failedReasons[url] = failure.message;
    _searched.remove(url);
    recorder?.sourceDone(url, null, failure.message);
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

  @override
  void dispose() {
    _disposed = true;
    _model.dispose();
    final attempt = _attempt;
    if (attempt != null && !attempt.isCompleted) attempt.complete();
    _progress.dispose();
    super.dispose();
  }
}
