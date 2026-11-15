import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/background_work/background_work.dart';
import 'package:night_reader/core/services/background_work/paused_work_file.dart';
import 'package:night_reader/core/services/check_source_service.dart';
import 'package:night_reader/shared/navigation/root_navigator.dart';

import 'source_manager_page.dart';

/// 暫停的校驗存在哪個檔（[PausedWorkFile.name]）。
const String sourceCheckProgressName = 'check_sources';

/// 一次校驗要校驗哪些書源、做完了哪些（ADR 0058）：暫停後照它只校驗剩下的，
/// 報告接在做完的那些後面。
class SourceCheckPlan {
  SourceCheckPlan(
    this.urls, {
    Set<String>? finished,
    List<SourceCheckEntry>? entries,
  }) : finished = finished ?? {},
       entries = entries ?? [];

  /// 這次要校驗的書源，照順序。
  final List<String> urls;

  /// 校驗完的書源（書源不在了的也算）。
  final Set<String> finished;

  /// 校驗完的結果，照完成的順序。
  final List<SourceCheckEntry> entries;

  List<String> get remaining => [
    for (final url in urls)
      if (!finished.contains(url)) url,
  ];

  /// 存檔的格式版本：改了存什麼就加一，舊版的讀不回來。
  static const int version = 1;

  String encode() => jsonEncode({
    'version': version,
    'urls': urls,
    'finished': [...finished],
    'entries': [for (final entry in entries) entry.toJson()],
  });

  /// 讀回 [encode] 存的；格式不對是 null。
  static SourceCheckPlan? decode(String text) {
    try {
      if (jsonDecode(text) case {
        'version': version,
        'urls': final List<Object?> urls,
        'finished': final List<Object?> finished,
        'entries': final List<Object?> entries,
      }) {
        return SourceCheckPlan(
          [for (final url in urls) '$url'],
          finished: {for (final url in finished) '$url'},
          entries: [...entries.map(SourceCheckEntry.fromJson).nonNulls],
        );
      }
    } on FormatException {
      // 讀不出來就當沒有。
    }
    return null;
  }
}

/// 暫停中的校驗：書源管理頁首下的膠囊照它寫「已暫停，校驗了 N／M 個」，
/// 按繼續校驗剩下的，按結束把做完的寫成上次校驗摘要（ADR 0058）。被系統收掉、
/// 從最近使用滑掉的校驗，下次開 App 讀回來也在這裡。
class PausedSourceCheck extends ChangeNotifier {
  PausedSourceCheck({PausedWorkFile Function()? file})
    : _newFile = file ?? (() => PausedWorkFile(sourceCheckProgressName));

  static final PausedSourceCheck instance = PausedSourceCheck();

  final PausedWorkFile Function() _newFile;

  SourceCheckPlan? _plan;
  PausedWorkFile? _file;

  /// 暫停中的那次；沒有是 null。
  SourceCheckPlan? get plan => _plan;

  bool get isPaused => _plan != null;

  /// 新的一次校驗用的存檔。
  PausedWorkFile open() => _newFile();

  /// 校驗暫停好了：留著它與它的存檔，等繼續或結束。
  void hold(SourceCheckPlan plan, PausedWorkFile file) {
    _plan = plan;
    _file = file;
    notifyListeners();
  }

  /// 按了繼續：交出暫停的那次與它的存檔，接著存進同一個檔。
  (SourceCheckPlan, PausedWorkFile)? take() {
    final plan = _plan;
    final file = _file;
    if (plan == null || file == null) return null;
    _plan = null;
    _file = null;
    notifyListeners();
    return (plan, file);
  }

  /// 暫停中按了結束，或開始了新的一次校驗：存檔刪掉；[service] 給了時把做完
  /// 的那些寫成上次校驗摘要。
  Future<void> end({CheckSourceService? service}) async {
    final taken = take();
    if (taken == null) return;
    final (plan, file) = taken;
    service?.showStoppedReport(plan.entries, plan.urls.length);
    await file.close();
  }

  /// 開 App 時讀回上次暫停（或被收掉）的校驗。
  Future<void> restore() async {
    // 使用者在讀回之前就開始了新的一次：存檔是那一次的，不讀。
    if (_plan != null || SourceCheckJob.current != null) return;
    final file = _newFile();
    final text = await file.read();
    if (text == null) return;
    final plan = SourceCheckPlan.decode(text);
    if (plan == null || plan.remaining.isEmpty) {
      AppLog.w('PausedSourceCheck: 存的校驗讀不出來或已經做完，刪掉');
      await file.close();
      return;
    }
    hold(plan, file);
  }
}

/// 照 [CheckSourceService.check] 校驗：測試換掉它。
typedef SourceChecker = Future<void> Function(
  List<String> urls, {
  required int doneBefore,
  required List<SourceCheckEntry> earlier,
  required SourceCheckFinished onFinished,
});

/// 從書源管理按下去的校驗（「校驗所有書源」「校驗選中」）：離開夜讀也繼續，
/// 通知欄顯示進度（ADR 0058）。每校驗完一個書源存一次進度：暫停（按暫停、
/// 從最近使用滑掉、被系統收掉）後按繼續只校驗剩下的。登入完自動校驗一個、
/// 整批修復裡的重新校驗不經過這裡。
class SourceCheckJob implements BackgroundJob {
  SourceCheckJob({
    required this.plan,
    required this._changes,
    required this._done,
    required this._total,
    required this._cancel,
    required this._check,
    PausedWorkFile? file,
    PausedSourceCheck? paused,
    BackgroundWork? work,
    NavigatorState? Function()? navigator,
  }) : _paused = paused ?? PausedSourceCheck.instance,
       _work = work ?? BackgroundWork.instance,
       _navigator = navigator ?? (() => rootNavigatorKey.currentState) {
    _file = file ?? _paused.open();
  }

  /// 照 [CheckSourceService] 校驗 [plan]。
  SourceCheckJob.of(
    CheckSourceService service,
    SourceCheckPlan plan, {
    PausedWorkFile? file,
  }) : this(
         plan: plan,
         changes: service,
         done: () => service.currentCount,
         total: () => service.totalCount,
         cancel: service.cancel,
         check:
             (
               urls, {
               required doneBefore,
               required earlier,
               required onFinished,
             }) => service.check(
               urls,
               doneBefore: doneBefore,
               earlier: earlier,
               onFinished: onFinished,
             ),
         file: file,
       );

  final SourceCheckPlan plan;
  final Listenable _changes;
  final int Function() _done;
  final int Function() _total;
  final VoidCallback _cancel;
  final SourceChecker _check;
  final PausedSourceCheck _paused;
  final BackgroundWork _work;
  final NavigatorState? Function() _navigator;
  late final PausedWorkFile _file;
  bool _pausing = false;
  bool _ending = false;

  /// 正在跑的那一次：書源管理的「暫停」「結束」交給它。
  static SourceCheckJob? current;

  bool get isPausing => _pausing && !_ending;
  bool get isEnding => _ending;

  BackgroundWorkStatus get status {
    final total = _total();
    final done = _done();
    final progress = total > 0 ? done / total : 0.0;
    if (_pausing || _ending) {
      return BackgroundWorkStatus.settling(
        '校驗書源',
        pausing: !_ending,
        progress: progress,
      );
    }
    return BackgroundWorkStatus(
      title: '校驗書源',
      text: '第 $done／$total 個',
      progress: progress,
      pausable: true,
    );
  }

  /// 校驗 [plan] 還沒做完的，跑的時候佔著背景工作的位置、更新通知；回傳
  /// 做完、結束或暫停好的時刻。
  Future<void> run() async {
    // 一次一件（ADR 0058）：入口已經擋住，這裡是最後一道。
    if (!_work.begin(this, status)) return;
    current = this;
    void update() => _work.update(this, status);
    _changes.addListener(update);
    _file.saveLater(plan.encode);
    try {
      await _check(
        plan.remaining,
        doneBefore: plan.finished.length,
        earlier: [...plan.entries],
        onFinished: (url, entry) {
          plan.finished.add(url);
          if (entry != null) plan.entries.add(entry);
          if (!_ending) _file.saveLater(plan.encode);
        },
      );
    } finally {
      _changes.removeListener(update);
      if (identical(current, this)) current = null;
      _work.end(this);
      if (_pausing && !_ending && plan.remaining.isNotEmpty) {
        _paused.hold(plan, _file);
      } else {
        await _file.close();
      }
    }
  }

  /// 暫停：正在校驗的那幾個停下，接著做時重校；做完的結果留著。
  @override
  void pauseFromSystem() {
    if (_pausing || _ending) return;
    _pausing = true;
    _work.update(this, status);
    _cancel();
  }

  /// 結束：做完的結果留著，寫成上次校驗摘要。
  @override
  void endFromSystem() {
    if (_ending) return;
    _ending = true;
    _work.update(this, status);
    unawaited(_file.close());
    _cancel();
  }

  /// 回到書源管理：校驗的結果在那裡（頁首下的狀態列與校驗標記）。
  @override
  void openFromNotification() {
    if (SourceManagerPage.isShowing) return;
    final navigator = _navigator();
    if (navigator == null) return;
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const SourceManagerPage()),
      ),
    );
  }
}
