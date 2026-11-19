import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/background_work/background_work.dart';
import 'package:night_reader/core/background_work/reading_fetches.dart';
import 'package:night_reader/features/source_manager/ai_repair/repair_runs.dart';
import 'package:path_provider/path_provider.dart';

import 'search_model.dart';
import 'search_page.dart';
import 'search_run.dart';

/// 放到背景的搜尋放在哪：哪一件、背景工作的位置、結果檔的資料夾、閱讀時的
/// 抓章（ADR 0070）。一次只有一件；測試換成自己的一份。
class BackgroundSearches {
  BackgroundSearches({
    RepairRuns? runs,
    BackgroundWork? work,
    Future<Directory> Function()? directory,
    ReadingFetches? readingFetches,
    this.loader,
  }) : runs = runs ?? RepairRuns(newEndsPaused: true),
       work = work ?? BackgroundWork.instance,
       readingFetches = readingFetches ?? ReadingFetches.instance,
       _directory = directory ?? _defaultDirectory;

  static BackgroundSearches instance = BackgroundSearches();

  /// 暫停中的那件不擋新的一件：再把一次搜尋放到背景時它就結束（同修書源）。
  final RepairRuns runs;
  final BackgroundWork work;
  final ReadingFetches readingFetches;
  final Future<Directory> Function() _directory;

  /// 向書源搜尋的那一步（測試從記憶體回傳）。
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

  /// 開 App 時讀回上次那一件做完時完成：開 App 後馬上打開的搜尋頁等它，讀回
  /// 了再接回（[restore]）。
  Future<void> get restored => _restored.future;
  final Completer<void> _restored = Completer<void>();

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
  /// 還沒看過的照舊留著）。結果檔在背景 isolate 讀與解析，壞掉的尾巴截掉；
  /// 合併成卡等搜尋頁打開、進場播完才做（ADR 0018）。最新的讀不出來時用
  /// 前一份，用到的那份以外都刪掉。
  Future<void> restore() async {
    try {
      await _restore();
    } catch (error) {
      AppLog.w('BackgroundSearches: 讀不回上次的搜尋：$error');
    } finally {
      if (!_restored.isCompleted) _restored.complete();
    }
  }

  Future<void> _restore() async {
    final dir = await _directory();
    if (!await dir.exists()) return;
    final files = [
      for (final entry in await dir.list().toList())
        if (entry is File && entry.path.endsWith('.jsonl')) entry,
    ]..sort((a, b) => b.path.compareTo(a.path));
    _Restored? restored;
    File? kept;
    for (final file in files) {
      if (runs.current != null) return;
      final path = file.path;
      restored = await Isolate.run(() => _readResults(path));
      if (restored != null) {
        kept = file;
        break;
      }
    }
    for (final file in files) {
      if (!identical(file, kept)) {
        await file.delete().catchError((Object _) => file);
      }
    }
    if (restored == null || kept == null || runs.current != null) return;
    final read = restored;
    final file = kept;
    final finished =
        read.ended ||
        (read.sourceUrls.isNotEmpty &&
            read.sourceUrls.every(
              (url) =>
                  read.searched.containsKey(url) ||
                  read.failed.containsKey(url),
            ));
    final run = BackgroundSearchRun.restored(
      SearchRun.restored(
        loader: loader,
        readingFetches: readingFetches,
        key: read.key,
        conditions: read.conditions,
        sourceUrls: read.sourceUrls,
        searched: read.searched,
        failed: read.failed,
      ),
      file: SearchResultsFile(() async => file),
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
/// 寫入與刪除排成一列；刪了之後不再寫。寫到一半被收掉時，讀回時把壞掉的
/// 尾巴截掉，接著寫的才不會黏在半行後面（[_readResults]）。
class SearchResultsFile {
  SearchResultsFile(this._file);

  final Future<File> Function() _file;
  Future<void> _queue = Future<void>.value();
  bool _deleted = false;

  /// 附加 [text]；[replace] 時整份換成它。傳回寫完的時候。
  Future<void> write(String text, {bool replace = false}) {
    if (_deleted) return _queue;
    return _queue = _queue.then((_) async {
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

  /// 排著的都寫完時完成。
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
  Map<String, SearchFailureNote> failed,
  bool ended,
});

/// 讀結果檔（在背景 isolate 跑）：一行一行照位元組切開、各自解碼，讀到第一
/// 行壞的（寫到一半被收掉，可能切在中文字中間）就停，檔案截到最後一行好的
/// 結尾。版本不對、第一行讀不出來是 null。
_Restored? _readResults(String path) {
  final file = File(path);
  final bytes = file.readAsBytesSync();
  final lines = <Object?>[];
  var start = 0;
  var validEnd = 0;
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] != 0x0A) continue;
    try {
      lines.add(jsonDecode(utf8.decode(bytes.sublist(start, i))));
    } on FormatException {
      break;
    }
    start = i + 1;
    validEnd = start;
  }
  if (lines.isEmpty) return null;
  final header = lines.first;
  if (header case {
    'version': _resultsVersion,
    'key': final String key,
    'kind': final String kind,
    'byKind': final bool byKind,
    'scope': final String scope,
    'precision': final bool precision,
    'sources': final List<Object?> sources,
  }) {
    if (validEnd < bytes.length) {
      final raf = file.openSync(mode: FileMode.append);
      try {
        raf.truncateSync(validEnd);
      } finally {
        raf.closeSync();
      }
    }
    final searched = <String, List<SearchBook>>{};
    final failed = <String, SearchFailureNote>{};
    var ended = false;
    for (final json in lines.skip(1)) {
      switch (json) {
        case {'end': true}:
          ended = true;
        case {'url': final String url, 'books': final List<Object?> books}:
          searched[url] = [
            for (final book in books)
              if (book is Map<String, dynamic>) SearchBook.fromJson(book),
          ];
          failed.remove(url);
        case {
          'url': final String url,
          'name': final String name,
          'failure': final String failure,
        }:
          failed[url] = (name: name, message: failure);
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

/// 按了暫停或結束、還沒停好：結束蓋過暫停（正在暫停時按結束，就是結束）。
enum _Settling { none, pausing, ending }

/// 一件放到背景的搜尋（ADR 0070，ADR 0058 的第五件背景工作）：搜尋頁關了照跑，
/// 通知欄標題「搜尋書籍 · 關鍵字」、內文同搜尋頁的進度那一列。暫停是不再送
/// 新的書源、正在搜的取消，按繼續只搜沒搜完的；結束是結果留著、不再續搜。
class BackgroundSearchRun extends RepairRun implements SearchRecorder {
  BackgroundSearchRun(this.search, {required this._file, super.work})
    : _headerWritten = false {
    _adopt();
  }

  /// 開 App 時讀回的那一件：暫停中，或做完還沒看過。
  BackgroundSearchRun.restored(
    this.search, {
    required this._file,
    required super.finished,
    super.work,
  }) : _headerWritten = true,
       super(paused: !finished) {
    _adopt();
  }

  final SearchRun search;
  final SearchResultsFile _file;

  /// 結果檔的第一行寫了（讀回的那件本來就有）。
  bool _headerWritten;

  _Settling _settling = _Settling.none;
  bool _pausedWork = false;
  bool _disposed = false;

  /// 接著搜時要搜的書源；`null` 是照條件重新搜（還沒選好書源就暫停的）。
  List<BookSource>? _remaining;
  bool _resuming = false;

  /// 接回它的搜尋頁開始了別的搜尋：結束、做完、頁面都關了就收掉，不再接回。
  bool get abandoned => _abandoned;
  bool _abandoned = false;

  /// 已經放掉了：還開著的搜尋頁照舊顯示，但不再對它做任何事。
  bool get isDisposed => _disposed;

  void _adopt() {
    search
      ..background = true
      ..recorder = this
      ..addListener(changed)
      ..progressUpdates.addListener(changed);
  }

  @override
  bool get isDone =>
      super.isDone || (_abandoned && isFinished && openPages == 0);

  @override
  bool get canPause => true;

  @override
  bool get workPaused => _pausedWork;

  /// 按了暫停或結束、還沒停好。
  bool get isPausing => _settling == _Settling.pausing;
  bool get isStopping => _settling == _Settling.ending;

  @override
  BackgroundWorkStatus get status {
    final title = '搜尋書籍 · ${search.key}';
    final progress = search.total > 0 ? search.completed / search.total : 0.0;
    if (_settling != _Settling.none) {
      return BackgroundWorkStatus.settling(
        title,
        pausing: isPausing,
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

  @override
  Future<void> run() async {
    _settling = _Settling.none;
    _pausedWork = false;
    if (_resuming) {
      _resuming = false;
      final remaining = _remaining;
      _remaining = null;
      await search.continueWith(remaining);
    } else {
      await _writeStart();
      await (search.running ?? Future<void>.value());
    }
    final settling = _settling;
    _settling = _Settling.none;
    if (settling == _Settling.pausing) {
      // 停好了才算暫停：每個搜完的書源都已經寫進結果檔。
      await _file.flush();
      _pausedWork = true;
      search.markPaused();
      return;
    }
    await _file.write('${jsonEncode({'end': true})}\n');
  }

  /// 放到背景的那一刻：條件、要搜的書源與已經搜完的書源一次寫下。書源還沒
  /// 選好時等選好（[sourcesChosen]）。
  Future<void> _writeStart() {
    if (_headerWritten || search.sourceUrls.isEmpty) return Future.value();
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
    for (final MapEntry(key: url, value: note) in search.failedNotes.entries) {
      text.writeln(_line(url, null, note));
    }
    return _file.write(text.toString(), replace: true);
  }

  static String _line(
    String url,
    List<SearchBook>? books,
    SearchFailureNote? failure,
  ) => jsonEncode({
    'url': url,
    if (books != null) 'books': [for (final book in books) book.toJson()],
    if (failure != null) ...{'name': failure.name, 'failure': failure.message},
  });

  @override
  void sourcesChosen() {
    if (isRunning) unawaited(_writeStart());
  }

  @override
  void sourceDone(
    String url,
    List<SearchBook>? books,
    SearchFailureNote? failure,
  ) {
    if (!_headerWritten) return;
    unawaited(_file.write('${_line(url, books, failure)}\n'));
  }

  @override
  void stop() {
    _settling = _Settling.ending;
    search.stop();
  }

  @override
  void pause() {
    if (_settling != _Settling.none) return;
    _settling = _Settling.pausing;
    search.halt();
  }

  @override
  Future<void> endPaused() => _file.write('${jsonEncode({'end': true})}\n');

  @override
  Future<bool> prepareResume() async {
    await search.mergeRestored();
    if (search.sourceUrls.isEmpty) {
      _remaining = null;
    } else {
      final done = {...search.searched.keys, ...search.failedNotes.keys};
      final enabled = {
        for (final source in await getIt<BookSourceDao>().getEnabled())
          if (source.isSearchEnabledByRuntime) source.bookSourceUrl: source,
      };
      _remaining = [
        for (final url in search.sourceUrls)
          if (!done.contains(url)) ?enabled[url],
      ];
    }
    _resuming = true;
    return true;
  }

  @override
  void discardResume() {
    _remaining = null;
    _resuming = false;
  }

  /// 接回它的搜尋頁開始了別的搜尋：正在跑或暫停中的結束，結果不留。
  void abandon() {
    if (_abandoned || _disposed) return;
    _abandoned = true;
    if (isFinished) {
      scheduleMicrotask(() {
        if (!_disposed) notifyListeners();
      });
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
      ..recorder = null;
    // 還開著、接回它的搜尋頁照舊讀這一份：等下一個微任務、頁面都換掉監聽
    // 之後再放。
    scheduleMicrotask(search.dispose);
    unawaited(_file.delete());
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
