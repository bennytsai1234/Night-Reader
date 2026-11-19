import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/core/background_work/work_phase.dart';
import 'package:night_reader/core/ai_find/ai_find_library.dart';
import 'package:night_reader/core/ai_find/ai_find_session.dart';
import 'package:night_reader/core/ai_repair/ai_chat_client.dart';
import 'package:night_reader/core/ai_repair/ai_repair_log.dart';
import 'package:night_reader/core/ai_repair/ai_repair_settings.dart';
import 'package:night_reader/core/database/dao/ai_find_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/search/ai_find_record.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/search/search_book.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/background_work/background_work.dart';
import 'package:night_reader/core/background_work/paused_work_file.dart';
import 'package:night_reader/features/search/models/search_scope.dart';
import 'package:night_reader/features/source_manager/ai_repair/repair_runs.dart';

import 'ai_find_page.dart';
import 'app_ai_find_library.dart';

/// 正在跑、暫停中，或做完還沒看過結果的那一次找書：搜尋頁的 ✦ 照它決定推回
/// 同一次還是開新的（docs/design/screens.md「AI 找書」）。和修書源分開放：
/// 找書的結果存成「過去的找書」，沒看過也不擋修書源；一次一件由背景工作的
/// 位置管（ADR 0058）。
final RepairRuns aiFindRuns = RepairRuns();

/// 暫停的找書存在哪個檔（[PausedWorkFile.name]）。
const String aiFindProgressName = 'ai_find';

/// 讀回暫停的找書，接著做：照存檔建一個新的找書，用現在的 AI 服務設定。
/// [log] 是同一次開 App 裡暫停前的紀錄。沒有 AI 服務時是 null。
typedef AiFindReopen = Future<AiFindSession?> Function(
  String progress,
  AiRepairLog? log,
);

/// 一次 AI 找書的背景工作（ADR 0058 的第四件）：頁面關了照跑，通知欄標題
/// 「AI 找書」、內文是最新一輪的副標，點了回那一頁。每一輪開頭存一次進度：
/// 暫停（按暫停、從最近使用滑掉、被系統收掉）後按繼續從那一輪接著問；結束
/// （按結束、找完、沒找完）就存成「過去的找書」的一筆。
class AiFindRun extends RepairRun {
  AiFindRun(
    this._session, {
    Future<void> Function(AiFindRecord record)? save,
    PausedWorkFile? progress,
    AiFindReopen? reopen,
    super.work,
    super.navigator,
  }) : _save = save ?? _saveRecord,
       _file = progress ?? PausedWorkFile(aiFindProgressName),
       _reopen = reopen ?? _reopenWithService {
    _adopt(_session);
  }

  /// 開 App 時讀回的暫停中的那一次：[_session] 照存檔顯示，還沒開始；按
  /// 繼續時照 [progress] 的存檔接著做。
  AiFindRun.paused(
    this._session, {
    required String this._progress,
    required this._file,
    Future<void> Function(AiFindRecord record)? save,
    AiFindReopen? reopen,
    super.work,
    super.navigator,
  }) : _save = save ?? _saveRecord,
       _reopen = reopen ?? _reopenWithService,
       super(paused: true) {
    _adopt(_session);
  }

  AiFindSession _session;

  /// 現在這一次：暫停後接著做時換成照存檔建的新的一個。
  AiFindSession get session => _session;

  /// 存成「過去的找書」；沒給時存進資料庫（測試換掉它）。
  final Future<void> Function(AiFindRecord record) _save;
  final PausedWorkFile _file;
  final AiFindReopen _reopen;

  /// 最後存的那一輪開頭（[AiFindSession.restore] 讀的那份）。
  String? _progress;

  /// 這次 [run] 是暫停好才回來的。
  bool _pausedWork = false;

  static Future<void> _saveRecord(AiFindRecord record) =>
      getIt<AiFindDao>().upsert(record);

  static Future<AiFindSession?> _reopenWithService(
    String progress,
    AiRepairLog? log,
  ) async {
    final service = await AiRepairSettings().findService();
    if (service == null) return null;
    return AiFindSession.restore(
      progress,
      library: AppAiFindLibrary(scope: SearchScope(_scopeOf(progress))),
      ask: AiFindSession.askService(service),
      serviceLabel: aiFindServiceLabel(service),
      log: log,
    );
  }

  static String _scopeOf(String progress) =>
      AiFindSession.scopeOf(progress) ?? '';

  void _adopt(AiFindSession session) {
    _session = session
      ..onCheckpoint = _checkpoint
      ..addListener(_sessionChanged);
  }

  void _checkpoint(String progress) {
    _progress = progress;
    _file.save(progress);
  }

  /// 每一輪的進度從找書本身來：更新通知，也讓頁面重畫。
  void _sessionChanged() {
    changed();
    notifyListeners();
  }

  @override
  bool get canPause => true;

  @override
  bool get workPaused => _pausedWork;

  @override
  BackgroundWorkStatus get status {
    if (_session.phase.settling) {
      return BackgroundWorkStatus.settling(
        'AI 找書',
        pausing: _session.phase == WorkPhase.pausing,
      );
    }
    return BackgroundWorkStatus(
      title: 'AI 找書',
      text: _session.now,
      pausable: true,
    );
  }

  @override
  Future<void> run() async {
    _pausedWork = false;
    await _session.start();
    if (_session.isPaused) {
      _pausedWork = true;
      // 暫停好了：頁面顯示的換成存檔的樣子，和 App 重開後看到的一樣（做到
      // 一半的那一輪不留）。
      final progress = _progress;
      if (progress != null) _replace(_display(progress, _session.log));
      return;
    }
    await _finishWith(_session.record);
  }

  /// 結束了：先讓存檔失效（按了結束的不會再活回來），再存成過去的找書。
  Future<void> _finishWith(AiFindRecord? record) async {
    await _file.close();
    if (record == null) return;
    try {
      await _save(record);
    } catch (error, stack) {
      // 存不進去只少一筆「過去的找書」，頁面上的結果照樣看得到。
      AppLog.e('存找書紀錄失敗', error: error, stackTrace: stack);
    }
  }

  @override
  void stop() {
    // 不等刪檔：之後晚到的存檔已經不會寫。
    unawaited(_file.close());
    _session.stop();
  }

  @override
  void pause() => _session.pause();

  @override
  Future<void> endPaused() async {
    _session.stop();
    await _finishWith(_session.record);
  }

  @override
  Future<bool> prepareResume() async {
    final progress = _progress ?? await _file.read();
    if (progress == null) return false;
    final AiFindSession? next;
    try {
      next = await _reopen(progress, _session.log);
    } on FormatException catch (error) {
      AppLog.w('AiFindRun: 接不下去：$error');
      return false;
    }
    _next = next;
    return next != null;
  }

  /// [prepareResume] 建好、還沒換上的那一次。
  AiFindSession? _next;

  @override
  void commitResume() {
    final next = _next;
    if (next == null) return;
    _next = null;
    _replace(next);
    notifyListeners();
  }

  @override
  void discardResume() {
    _next?.dispose();
    _next = null;
  }

  void _replace(AiFindSession next) {
    final previous = _session;
    previous
      ..removeListener(_sessionChanged)
      ..onCheckpoint = null;
    _adopt(next);
    // 頁面可能還在這一幀用著舊的：下一個微任務再放掉。
    scheduleMicrotask(previous.dispose);
  }

  @override
  Widget page() => AiFindPage(run: this);

  @override
  void disposeWork() {
    _session
      ..removeListener(_sessionChanged)
      ..onCheckpoint = null
      ..dispose();
  }
}

/// 「主機名 · 模型」：頁面上「送到…」那行與紀錄的開頭。
String aiFindServiceLabel(AiService service) =>
    '${Uri.tryParse(service.baseUrl)?.host ?? service.baseUrl} · '
    '${service.model}';

/// 只用來顯示的找書（暫停中，還沒按繼續）：不連書源與 AI 服務。
AiFindSession _display(String progress, AiRepairLog? log) =>
    AiFindSession.restore(
      progress,
      library: const _NoLibrary(),
      ask: _noAsk,
      serviceLabel: AiFindSession.serviceLabelOf(progress) ?? '',
      log: log,
    );

/// 暫停中只顯示、不跑：工具一個都不會被叫到。
class _NoLibrary implements AiFindLibrary {
  const _NoLibrary();

  @override
  Set<String> get secrets => const {};

  static Never _paused() => throw StateError('暫停中的找書不抓書源');

  @override
  Future<AiFindSearchResult> search(
    String keyword,
    BookSourceKind kind,
    CancelToken cancelToken,
  ) => _paused();

  @override
  Future<Book> detail(SearchBook book, CancelToken cancelToken) => _paused();

  @override
  Future<AiFindChapter> chapter(
    SearchBook book,
    int number,
    CancelToken cancelToken,
  ) => _paused();

  @override
  Future<List<AiFindExploreSource>> exploreSources() => _paused();

  @override
  Future<List<String>> exploreCategories(
    AiFindExploreSource source,
    CancelToken cancelToken,
  ) => _paused();

  @override
  Future<List<SearchBook>> exploreBooks(
    AiFindExploreSource source,
    int category,
    int page,
    CancelToken cancelToken,
  ) => _paused();

  @override
  Future<List<AiFindShelfEntry>> shelf() => _paused();

  @override
  Future<AiFindWorkNames?> workNames(String name, CancelToken cancelToken) =>
      _paused();
}

Future<AiReply> _noAsk(List<AiMessage> messages, CancelToken cancelToken) =>
    throw StateError('暫停中的找書不問 AI');

/// 開 App 時讀回暫停的那一次找書（被系統收掉、從最近使用滑掉都算暫停，
/// ADR 0058）：搜尋頁的 ✦ 推回它，頁面顯示已暫停。存檔是舊版的、讀不出來
/// 時照沒找完存成過去的找書。
Future<void> restorePausedAiFind({
  PausedWorkFile? file,
  Future<void> Function(AiFindRecord record)? save,
  AiFindReopen? reopen,
  BackgroundWork? work,
}) async {
  final store = file ?? PausedWorkFile(aiFindProgressName);
  final progress = await store.read();
  if (progress == null || aiFindRuns.current != null) return;
  final AiFindSession session;
  try {
    session = _display(progress, null);
  } on FormatException catch (error) {
    AppLog.w('AiFindRun: 暫停的找書讀不出來：$error');
    await store.close();
    final record = AiFindSession.brokenRecord(progress, '夜讀更新了，這次找書接不下去');
    if (record != null) {
      try {
        await (save ?? AiFindRun._saveRecord)(record);
      } catch (error, stack) {
        AppLog.e('存找書紀錄失敗', error: error, stackTrace: stack);
      }
    }
    return;
  }
  final run = AiFindRun.paused(
    session,
    progress: progress,
    file: store,
    save: save,
    reopen: reopen,
    work: work,
  );
  if (!aiFindRuns.adopt(run)) {
    run
      ..disposeWork()
      ..dispose();
  }
}
