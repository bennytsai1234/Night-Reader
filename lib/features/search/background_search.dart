import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/background_work/background_work.dart';
import 'package:night_reader/features/source_manager/ai_repair/repair_runs.dart';
import 'package:path_provider/path_provider.dart';

import 'search_model.dart';
import 'search_page.dart';
import 'search_run.dart';

/// 放到背景的搜尋放在哪：哪一件、背景工作的位置、結果檔的資料夾（ADR 0070）。
/// 一次只有一件；測試換成自己的一份。
class BackgroundSearches {
  BackgroundSearches({
    RepairRuns? runs,
    BackgroundWork? work,
    Future<Directory> Function()? directory,
    this.loader,
  }) : runs = runs ?? RepairRuns(newEndsPaused: true),
       work = work ?? BackgroundWork.instance,
       _directory = directory ?? _defaultDirectory;

  static BackgroundSearches instance = BackgroundSearches();

  /// 暫停中的那件不擋新的一件：再把一次搜尋放到背景時它就結束（同修書源）。
  final RepairRuns runs;
  final BackgroundWork work;
  final Future<Directory> Function() _directory;

  /// 讀回的搜尋接著搜時向書源搜尋的那一步（測試從記憶體回傳）。
  final SearchBookLoader? loader;

  static Future<Directory> _defaultDirectory() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/paused_work/search',
  );

  BackgroundSearchRun? get current => runs.current as BackgroundSearchRun?;

  /// 沒帶關鍵字打開的搜尋頁接回的那一件：正在跑、暫停中，或做完還沒看過。
  BackgroundSearchRun? get resumable {
    final run = current;
    return run != null && !run.isDone && !run.abandoned ? run : null;
  }

  /// 「放到背景」能不能按：沒有別的背景工作在跑、沒有一件做完還沒看過。
  bool get canMoveToBackground => runs.canStartNew && !work.isBusy;

  /// 把 [search] 放到背景；不能放時是 null。要在 App 看得到時呼叫（使用者
  /// 剛按下去）：Android 不讓背景的 App 開前景服務。
  BackgroundSearchRun? moveToBackground(SearchRun search) {
    if (!canMoveToBackground) return null;
    final id = DateTime.now().microsecondsSinceEpoch;
    final run = BackgroundSearchRun(
      search,
      file: SearchResultsFile(
        () async => File('${(await _directory()).path}/$id.jsonl'),
      ),
      work: work,
    );
    if (!runs.adopt(run)) {
      run.dispose();
      return null;
    }
    return run;
  }

  /// 開 App 時讀回上次的那一件（被系統收掉、從最近使用滑掉都算暫停，做完
  /// 還沒看過的照舊留著）。結果檔在背景 isolate 讀與解析；合併成卡等搜尋頁
  /// 打開、進場播完才做（ADR 0018）。
  Future<void> restore() async {
    final List<File> files;
    try {
      final dir = await _directory();
      if (!await dir.exists()) return;
      files = [
        for (final entry in await dir.list().toList())
          if (entry is File && entry.path.endsWith('.jsonl')) entry,
      ]..sort((a, b) => a.path.compareTo(b.path));
    } catch (error) {
      AppLog.w('BackgroundSearches: 讀不到結果檔：$error');
      return;
    }
    if (files.isEmpty || runs.current != null) return;
    final newest = files.removeLast();
    for (final old in files) {
      unawaited(old.delete().catchError((Object _) => old));
    }
    final path = newest.path;
    final _Restored? read;
    try {
      read = await _readInBackground(path);
    } catch (error) {
      AppLog.w('BackgroundSearches: 結果檔讀不出來：$error');
      await newest.delete().catchError((Object _) => newest);
      return;
    }
    if (read == null) {
      await newest.delete().catchError((Object _) => newest);
      return;
    }
    final restored = read;
    if (runs.current != null) return;
    final finished =
        restored.ended ||
        restored.sourceUrls.every(
          (url) =>
              restored.searched.containsKey(url) ||
              restored.failed.containsKey(url),
        );
    final run = BackgroundSearchRun.restored(
      SearchRun.restored(
        loader: loader,
        key: restored.key,
        conditions: restored.conditions,
        sourceUrls: restored.sourceUrls,
        searched: restored.searched,
        failed: restored.failed,
      ),
      file: SearchResultsFile(() async => newest),
      finished: finished,
      work: work,
    );
    if (!runs.adopt(run)) {
      run
        ..disposeWork()
        ..dispose();
    }
  }
}

/// 結果檔的格式版本：改了存什麼就加一，舊版的讀不回來。
const int _resultsVersion = 1;

/// 一件放到背景的搜尋的結果檔：第一行是搜尋條件與這次要搜的書源，之後每搜完
/// 一個書源附加一行（搜到的書或失敗原因，零本也記），結束時附加一行
/// `{"end":true}`。每次只寫一個書源的那份，不重寫整份（ADR 0070）。
///
/// 寫入與刪除排成一列；刪了之後不再寫。寫到一半被收掉時，最後那行讀的時候
/// 略過。
class SearchResultsFile {
  SearchResultsFile(this._file);

  final Future<File> Function() _file;
  Future<void> _queue = Future<void>.value();
  bool _deleted = false;

  /// 附加 [text]；[replace] 時整份換成它。
  void write(String text, {bool replace = false}) {
    if (_deleted) return;
    _queue = _queue.then((_) async {
      if (_deleted) return;
      try {
        final file = await _file();
        await file.parent.create(recursive: true);
        await file.writeAsString(
          text,
          mode: replace ? FileMode.write : FileMode.append,
          flush: true,
        );
      } catch (error) {
        AppLog.w('SearchResultsFile: 存不進去：$error');
      }
    });
  }

  /// 寫完排著的；測試等它。
  Future<void> flush() => _queue;

  Future<void> delete() {
    _deleted = true;
    return _queue = _queue.then((_) async {
      try {
        final file = await _file();
        if (await file.exists()) await file.delete();
      } catch (error) {
        AppLog.w('SearchResultsFile: 刪不掉：$error');
      }
    });
  }
}

typedef _Restored = ({
  String key,
  SearchConditions conditions,
  List<String> sourceUrls,
  Map<String, List<SearchBook>> searched,
  Map<String, String> failed,
  bool ended,
});

/// 在背景 isolate 讀結果檔：頂層函式，送過去的只有路徑。
Future<_Restored?> _readInBackground(String path) =>
    Isolate.run(() => _readResults(path));

/// 讀結果檔（在背景 isolate 跑）。版本不對、第一行讀不出來是 null。
_Restored? _readResults(String path) {
  final lines = File(path).readAsLinesSync();
  if (lines.isEmpty) return null;
  final header = jsonDecode(lines.first);
  if (header case {
    'version': _resultsVersion,
    'key': final String key,
    'kind': final String kind,
    'byKind': final bool byKind,
    'scope': final String scope,
    'precision': final bool precision,
    'sources': final List<Object?> sources,
  }) {
    final searched = <String, List<SearchBook>>{};
    final failed = <String, String>{};
    var ended = false;
    for (final line in lines.skip(1)) {
      final Object? json;
      try {
        json = jsonDecode(line);
      } on FormatException {
        // 寫到一半被收掉的最後一行。
        break;
      }
      switch (json) {
        case {'end': true}:
          ended = true;
        case {'url': final String url, 'books': final List<Object?> books}:
          searched[url] = [
            for (final book in books)
              if (book is Map<String, dynamic>) SearchBook.fromJson(book),
          ];
          failed.remove(url);
        case {'url': final String url, 'failure': final String failure}:
          failed[url] = failure;
          searched.remove(url);
      }
    }
    return (
      key: key,
      conditions: (
        kind: BookSourceKind.values.asNameMap()[kind] ?? BookSourceKind.novel,
        byKind: byKind,
        scope: scope,
        precision: precision,
      ),
      sourceUrls: [for (final url in sources) '$url'],
      searched: searched,
      failed: failed,
      ended: ended,
    );
  }
  return null;
}

/// 一件放到背景的搜尋（ADR 0070，ADR 0058 的第五件背景工作）：搜尋頁關了照跑，
/// 通知欄標題「搜尋書籍 · 關鍵字」、內文同搜尋頁的進度那一列。暫停是不再送
/// 新的書源、正在搜的取消，按繼續只搜沒搜完的；結束是結果留著、不再續搜。
class BackgroundSearchRun extends RepairRun implements SearchRecorder {
  BackgroundSearchRun(this.search, {required this._file, super.work})
    : _resumeFromFile = false {
    _adopt();
  }

  /// 開 App 時讀回的那一件：暫停中，或做完還沒看過。
  BackgroundSearchRun.restored(
    this.search, {
    required this._file,
    required super.finished,
    super.work,
  }) : _resumeFromFile = true,
       _headerWritten = true,
       super(paused: !finished) {
    _adopt();
  }

  final SearchRun search;
  final SearchResultsFile _file;

  /// 讀回的那件，結果檔已經在了。
  final bool _resumeFromFile;
  bool _headerWritten = false;

  bool _pausing = false;
  bool _ending = false;
  bool _pausedWork = false;
  List<BookSource>? _remaining;

  /// 接回它的搜尋頁開始了別的搜尋：結束、做完就收掉，不再接回。
  bool get abandoned => _abandoned;
  bool _abandoned = false;

  void _adopt() {
    search
      ..background = true
      ..recorder = this
      ..addListener(changed)
      ..progressUpdates.addListener(changed);
  }

  @override
  bool get isDone => super.isDone || (_abandoned && isFinished);

  @override
  bool get canPause => true;

  @override
  bool get workPaused => _pausedWork;

  @override
  BackgroundWorkStatus get status {
    final title = '搜尋書籍 · ${search.key}';
    final progress = search.total > 0 ? search.completed / search.total : 0.0;
    if (_pausing || _ending) {
      return BackgroundWorkStatus.settling(
        title,
        pausing: _pausing,
        progress: progress,
      );
    }
    return BackgroundWorkStatus(
      title: title,
      text: searchProgressText(
        completed: search.completed,
        total: search.total,
        waiting: search.waitingSources,
      ),
      progress: progress,
      pausable: true,
    );
  }

  /// 結果檔寫完排著的（測試在「重開 App」前等它）。
  Future<void> flushResults() => _file.flush();

  /// 按了暫停或結束、還沒停好。
  bool get isPausing => _pausing;
  bool get isStopping => _ending;

  @override
  Future<void> run() async {
    _pausing = false;
    _pausedWork = false;
    final remaining = _remaining;
    _remaining = null;
    if (remaining != null) {
      await search.continueWith(remaining);
    } else {
      _writeStart();
      await (search.running ?? Future<void>.value());
    }
    if (_pausing) {
      _pausing = false;
      _pausedWork = true;
      search.markPaused();
      return;
    }
    _ending = false;
    _file.write('${jsonEncode({'end': true})}\n');
  }

  /// 放到背景的那一刻：條件、要搜的書源與已經搜完的書源一次寫下。書源還沒
  /// 選好時等選好（[sourcesChosen]）。
  void _writeStart() {
    if (_headerWritten || _resumeFromFile || search.sourceUrls.isEmpty) return;
    _headerWritten = true;
    final conditions = search.conditions!;
    final text = StringBuffer()
      ..writeln(
        jsonEncode({
          'version': _resultsVersion,
          'key': search.key,
          'kind': conditions.kind.name,
          'byKind': conditions.byKind,
          'scope': conditions.scope,
          'precision': conditions.precision,
          'sources': search.sourceUrls,
        }),
      );
    for (final MapEntry(key: url, value: books) in search.searched.entries) {
      text.writeln(_line(url, books, null));
    }
    for (final MapEntry(key: url, value: failure)
        in search.failedReasons.entries) {
      text.writeln(_line(url, null, failure));
    }
    _file.write(text.toString(), replace: true);
  }

  static String _line(String url, List<SearchBook>? books, String? failure) =>
      jsonEncode({
        'url': url,
        if (books != null) 'books': [for (final book in books) book.toJson()],
        'failure': ?failure,
      });

  @override
  void sourcesChosen() {
    if (isRunning) _writeStart();
  }

  @override
  void sourceDone(String url, List<SearchBook>? books, String? failure) {
    if (!_headerWritten) return;
    _file.write('${_line(url, books, failure)}\n');
  }

  @override
  void stop() {
    _ending = true;
    search.stop();
  }

  @override
  void pause() {
    _pausing = true;
    search.cancel();
  }

  @override
  Future<void> endPaused() async {
    _file.write('${jsonEncode({'end': true})}\n');
  }

  @override
  Future<bool> prepareResume() async {
    await search.mergeRestored();
    final done = {...search.searched.keys, ...search.failedReasons.keys};
    final enabled = {
      for (final source in await getIt<BookSourceDao>().getEnabled())
        if (source.isSearchEnabledByRuntime) source.bookSourceUrl: source,
    };
    _remaining = [
      for (final url in search.sourceUrls)
        if (!done.contains(url)) ?enabled[url],
    ];
    return true;
  }

  @override
  void discardResume() => _remaining = null;

  /// 接回它的搜尋頁開始了別的搜尋：正在跑或暫停中的結束，結果不留。
  void abandon() {
    if (_abandoned) return;
    _abandoned = true;
    if (isFinished) {
      scheduleMicrotask(notifyListeners);
    } else {
      unawaited(end());
    }
  }

  @override
  Widget page() => const SearchPage();

  @override
  void disposeWork() {
    search
      ..removeListener(changed)
      ..progressUpdates.removeListener(changed)
      ..recorder = null
      ..dispose();
    unawaited(_file.delete());
  }
}
