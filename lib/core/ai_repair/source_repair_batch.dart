import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/check_source_service.dart';
import 'package:night_reader/core/services/source_check_isolate.dart';
import 'package:night_reader/core/utils/public_suffix.dart';

import 'ai_repair_backups.dart';
import 'ai_repair_prompt.dart';
import 'ai_repair_session.dart';
import 'ai_repair_settings.dart';
import 'site_check.dart';

/// 整批修復做到哪一段。
enum RepairStage {
  /// 重新校驗：標記可能過時了，先用現在的版本校驗一次。
  checking,

  /// 檢查每個網站：不在了、搬家、還是規則壞了。
  checkingSites,

  /// 搬家的網站換成新網址再校驗。
  moving,

  /// 每個網站挑一個書源交給 AI。
  repairing,

  /// AI 修好的規則套到同網站的其他書源。
  sharing,

  done,
}

/// 一個書源修完的結果。
enum RepairOutcome {
  /// 重新校驗就沒問題了。
  healthy,

  /// 換成網站的新網址就好了。
  moved,

  /// AI 修好了。
  aiFixed,

  /// 套用同網站 AI 修好的規則就好了。
  shared,

  /// 網站不在了：網域查不到、停放或出售、只剩空殼。
  siteGone,

  /// 試過了沒修好。
  notFixed,

  /// 不修：需要登入、在網頁驗證、只能下載、夜讀不支援的類型。
  skipped,

  /// 沒輪到：花費到了上限，或按了停止。
  notTried,
}

/// 整批修復裡的一個書源。
class RepairItem {
  RepairItem(this.source);

  /// 這個書源；修好存進去後換成存的那份（網址可能換了開頭）。
  BookSource source;

  RepairOutcome? outcome;

  /// 結果的一句說明：校驗的結論、網站的狀況或 AI 最後說的話。
  String? detail;

  /// 網站檢查的結果（同網站的書源共用一份）。
  SiteCheck? site;

  /// 交給 AI 修時的那段修復，看得到每一步。
  AiRepairSession? session;

  /// 這個書源用了多少 token。
  int tokens = 0;

  bool get isFinished => outcome != null;
}

/// 修復異常書源（ADR 0054）：一批書源先重新校驗、檢查網站，網站不在了的
/// 標「網站失效」，搬家的換網址；剩下的每個網站挑一個交給 AI，同時修
/// [aiConcurrency] 個，修好的規則再套到同網站的其他書源。每一步存進去的
/// 都是校驗通過的，留改前版本可以還原。
class SourceRepairBatch extends ChangeNotifier {
  SourceRepairBatch({
    required List<BookSource> sources,
    required this.service,
    this.tokenBudget,
    this.siteTokenBudget = defaultSiteTokenBudget,
    Future<List<SourceCheckEntry>> Function(List<String> urls)? recheck,
    Future<SiteCheck> Function(BookSource source)? checkSite,
    AiRepairChecker? check,
    Future<void> Function(BookSource repaired, BookSource original)? save,
    Future<void> Function(BookSource source, SiteCheck site)? markGone,
    AiRepairSession Function(BookSource source, RepairItem item)? session,
  }) : items = [for (final source in sources) RepairItem(source)],
       _recheck = recheck ?? _defaultRecheck,
       _checkSite = checkSite ?? _defaultCheckSite,
       _check = check ?? _defaultCheck,
       _save = save ?? _defaultSave,
       _markGone = markGone ?? _defaultMarkGone {
    _session = session ?? _defaultSession;
  }

  /// 每個網站的 AI 花費上限（token，含打中快取的）：實測修好的網站多半在
  /// 15 萬以內，超過的多半修不好。
  static const int defaultSiteTokenBudget = 300000;

  /// 同時交給 AI 修幾個網站。
  static const int aiConcurrency = 3;

  /// 同時檢查幾個網站。
  static const int siteConcurrency = 8;

  final AiService service;

  /// 整批的 AI 花費上限（token）；null 是不限。
  final int? tokenBudget;

  /// 每個網站的 AI 花費上限（token）。
  final int siteTokenBudget;

  final List<RepairItem> items;
  final Future<List<SourceCheckEntry>> Function(List<String> urls) _recheck;
  final Future<SiteCheck> Function(BookSource source) _checkSite;
  final AiRepairChecker _check;
  final Future<void> Function(BookSource repaired, BookSource original) _save;
  final Future<void> Function(BookSource source, SiteCheck site) _markGone;
  late final AiRepairSession Function(BookSource source, RepairItem item)
  _session;

  RepairStage stage = RepairStage.checking;

  /// 這一段做完幾件、共幾件。
  int stageDone = 0;
  int stageTotal = 0;

  /// AI 一共用了多少 token。
  int tokensUsed = 0;

  final CancelToken _cancelToken = CancelToken();
  bool _running = false;
  bool _stopped = false;
  bool _disposed = false;
  final List<AiRepairSession> _sessions = [];

  bool get isRunning => _running;
  bool get isStopped => _stopped;
  bool get isFinished => stage == RepairStage.done;

  int count(RepairOutcome outcome) =>
      items.where((item) => item.outcome == outcome).length;

  bool get _hasBudget => tokenBudget == null || tokensUsed < tokenBudget!;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _notify();
    try {
      await _recheckAll();
      if (!_stopped) await _checkSites();
      if (!_stopped) await _moveSites();
      if (!_stopped) await _repairWithAi();
    } catch (error, stack) {
      AppLog.e('修復異常書源失敗', error: error, stackTrace: stack);
    } finally {
      for (final item in items) {
        if (item.outcome == null) {
          item
            ..outcome = RepairOutcome.notTried
            ..detail = _stopped ? '已停止' : '沒輪到';
        }
      }
      stage = RepairStage.done;
      _running = false;
      _notify();
    }
  }

  /// 停下：做著的那一個 AI 修復停下、書源不改，還沒輪到的不做。
  void stop() {
    if (_stopped || isFinished) return;
    _stopped = true;
    if (!_cancelToken.isCancelled) _cancelToken.cancel('已停止');
    for (final session in _sessions) {
      session.stop();
    }
    if (stage == RepairStage.checking) getIt<CheckSourceService>().cancel();
    _notify();
  }

  // ── 1. 重新校驗 ────────────────────────────────────────────────────────

  Future<void> _recheckAll() async {
    _enter(RepairStage.checking, items.length);
    final entries = {
      for (final entry in await _recheck([
        for (final item in items) item.source.bookSourceUrl,
      ]))
        entry.sourceUrl: entry,
    };
    for (final item in items) {
      final entry = entries[item.source.bookSourceUrl];
      if (entry == null) continue;
      if (entry.isHealthy) {
        _finish(item, RepairOutcome.healthy, '重新校驗就沒問題了');
      } else if (_notRepairable.contains(entry.health.category)) {
        _finish(item, RepairOutcome.skipped, '${entry.health.label}：不修');
      } else {
        item.detail = '${entry.health.label}：${entry.message}';
      }
    }
    stageDone = items.length;
    _notify();
  }

  // ── 2. 檢查網站 ────────────────────────────────────────────────────────

  Future<void> _checkSites() async {
    final bySite = _pendingBySite();
    _enter(RepairStage.checkingSites, bySite.length);
    await _pool(bySite.entries.toList(), siteConcurrency, (entry) async {
      final site = await _checkSite(entry.value.first.source);
      for (final item in entry.value) {
        item.site = site;
        if (site.verdict == SiteVerdict.gone) {
          await _markGone(item.source, site);
          _finish(item, RepairOutcome.siteGone, site.detail);
        }
      }
      stageDone++;
      _notify();
    });
  }

  // ── 3. 搬家的網站換網址 ────────────────────────────────────────────────

  Future<void> _moveSites() async {
    final moving = [
      for (final item in _pending())
        if (item.site?.verdict == SiteVerdict.moved &&
            item.site?.movedTo != null)
          item,
    ];
    _enter(RepairStage.moving, moving.length);
    await _pool(moving, siteConcurrency, (item) async {
      final candidate = movedSource(item.source, item.site!.movedTo!);
      if (await _passes(item, candidate)) {
        _finish(item, RepairOutcome.moved, '換成 ${candidate.bookSourceUrl}');
      }
      stageDone++;
      _notify();
    });
  }

  // ── 4. AI 修，每個網站一個；5. 套用到同網站的其他書源 ──────────────────

  Future<void> _repairWithAi() async {
    final bySite = _pendingBySite().values.toList()
      ..sort((a, b) => _aiOrder(a.first).compareTo(_aiOrder(b.first)));
    _enter(RepairStage.repairing, bySite.length);
    await _pool(bySite, aiConcurrency, (group) async {
      if (_stopped) return;
      final lead = group.first;
      if (!_hasBudget) {
        stageDone++;
        _notify();
        return;
      }
      final others = group.skip(1).toList();
      final session = _session(lead.source, lead);
      lead.session = session;
      _sessions.add(session);
      session.addListener(_notify);
      await session.start();
      final job = session.job;
      final fixed = job.repairedSource;
      if (job.outcome == AiRepairOutcome.repaired && fixed != null) {
        _finish(lead, RepairOutcome.aiFixed, job.explanation ?? 'AI 修好了');
        lead.source = fixed;
        await _share(lead, others, fixed);
      } else if (!_stopped && _hasBudget) {
        _finish(lead, RepairOutcome.notFixed, job.explanation ?? '沒修好');
        for (final item in others) {
          _finish(
            item,
            RepairOutcome.notFixed,
            '同網站的「${lead.source.bookSourceName}」沒修好',
          );
        }
      }
      stageDone++;
      _notify();
    });
  }

  /// [fixed] 的規則套到同網站的其他書源 [siblings]，各自校驗，通過才存。
  Future<void> _share(
    RepairItem lead,
    List<RepairItem> siblings,
    BookSource fixed,
  ) async {
    for (final item in siblings) {
      if (_stopped) return;
      final candidate = sharedSource(item.source, fixed);
      if (await _passes(item, candidate)) {
        _finish(
          item,
          RepairOutcome.shared,
          '套用「${lead.source.bookSourceName}」修好的規則',
        );
      } else if (!_stopped) {
        _finish(
          item,
          RepairOutcome.notFixed,
          '套用「${lead.source.bookSourceName}」修好的規則也沒過校驗，可以單獨修',
        );
      }
    }
  }

  /// 校驗 [candidate]，通過（或只剩原本就壞的發現頁）就存進去，傳回存了沒。
  Future<bool> _passes(RepairItem item, BookSource candidate) async {
    final checked = await _check(candidate, _cancelToken);
    if (checked == null ||
        !AiRepairSession.usableFix(checked, item.source, candidate)) {
      return false;
    }
    final saved = BookSource.fromJson(checked.updatedSourceJson);
    try {
      await _save(saved, item.source);
    } catch (error) {
      item.detail = '$error';
      return false;
    }
    item.source = saved;
    return true;
  }

  // ── 工具 ──────────────────────────────────────────────────────────────

  Iterable<RepairItem> _pending() => items.where((item) => !item.isFinished);

  /// 還沒結果的書源照網站（可註冊網域）分組，照原本的順序。
  Map<String, List<RepairItem>> _pendingBySite() {
    final groups = <String, List<RepairItem>>{};
    for (final item in _pending()) {
      groups.putIfAbsent(siteKey(item.source), () => []).add(item);
    }
    return groups;
  }

  /// AI 先修網站正常的：連不上、被擋的修好的機會小一些。
  static int _aiOrder(RepairItem item) => switch (item.site?.verdict) {
    SiteVerdict.alive || null => 0,
    SiteVerdict.moved => 1,
    SiteVerdict.blocked => 2,
    SiteVerdict.unreachable => 3,
    SiteVerdict.gone => 4,
  };

  void _enter(RepairStage next, int total) {
    stage = next;
    stageDone = 0;
    stageTotal = total;
    _notify();
  }

  void _finish(RepairItem item, RepairOutcome outcome, String detail) {
    item
      ..outcome = outcome
      ..detail = detail;
    _notify();
  }

  /// [count] 個工人輪流做 [work]；停下時還沒開始的不做。
  Future<void> _pool<T>(
    List<T> list,
    int count,
    Future<void> Function(T value) work,
  ) async {
    var next = 0;
    Future<void> worker() async {
      while (next < list.length && !_stopped) {
        await work(list[next++]);
      }
    }

    await Future.wait([for (var i = 0; i < count; i++) worker()]);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    stop();
    _disposed = true;
    for (final session in _sessions) {
      session
        ..removeListener(_notify)
        ..dispose();
    }
    super.dispose();
  }

  static const Set<SourceHealthCategory> _notRepairable = {
    SourceHealthCategory.loginRequired,
    SourceHealthCategory.verificationRequired,
    SourceHealthCategory.downloadOnly,
    SourceHealthCategory.nonNovel,
  };

  // ── 預設的實作 ────────────────────────────────────────────────────────

  static Future<List<SourceCheckEntry>> _defaultRecheck(
    List<String> urls,
  ) async => (await getIt<CheckSourceService>().check(urls)).entries;

  static Future<SiteCheck> _defaultCheckSite(BookSource source) =>
      checkSite(source);

  static Future<SourceCheckIsolateResult?> _defaultCheck(
    BookSource source,
    CancelToken cancelToken,
  ) => AiRepairSession.defaultCheck(source, cancelToken);

  static Future<void> _defaultSave(BookSource repaired, BookSource original) =>
      saveRepairedSource(repaired, original, backups: AiRepairBackups.instance);

  /// 網站不在了：標「網站失效」，原因寫進錯誤註解。
  static Future<void> _defaultMarkGone(BookSource source, SiteCheck site) =>
      markSiteGone(source, site.detail);

  AiRepairSession _defaultSession(BookSource source, RepairItem item) =>
      AiRepairSession(
        source: source,
        service: service,
        hasBudget: () => _hasBudget && item.tokens < siteTokenBudget,
        onUsage: (usage) {
          final used = usage.prompt + usage.completion;
          item.tokens += used;
          tokensUsed += used;
          _notify();
        },
      );
}

/// 網站不在了：書源標「網站失效」（ADR 0054），原因寫進錯誤註解；書源在這
/// 段時間被刪掉了就不寫。
Future<void> markSiteGone(BookSource source, String detail) async {
  final dao = getIt<BookSourceDao>();
  final current = await dao.getByUrl(source.bookSourceUrl);
  if (current == null) return;
  current
    ..removeInvalidGroups()
    ..removeErrorComment()
    ..addHealthGroups(upstreamHealth(siteBrokenSourceGroupTag))
    ..addErrorComment('網站: $detail')
    ..lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
  await dao.upsert(current);
}

/// 書源屬於哪個網站：網址主機的可註冊網域（`m.site.com` 與 `www.site.com`
/// 是同一個）。
String siteKey(BookSource source) {
  final origin = siteOrigin(source.bookSourceUrl);
  final host = origin == null ? null : Uri.tryParse(origin)?.host;
  if (host == null || host.isEmpty) return source.bookSourceUrl;
  return registrableDomain(host) ?? host;
}

/// 網站搬到 [movedTo]（`https://www.new.com`）：書源網址換開頭，規則裡寫死的
/// 舊網域也換成新的。名稱、分組與註解照舊。
BookSource movedSource(BookSource source, String movedTo) {
  final from = Uri.parse(siteOrigin(source.bookSourceUrl)!).host;
  final to = Uri.parse(movedTo).host;
  final fromSite = registrableDomain(from) ?? from;
  final toSite = registrableDomain(to) ?? to;
  final json = source.toJson();
  final keep = {
    for (final key in const [
      'bookSourceName',
      'bookSourceGroup',
      'bookSourceComment',
    ])
      key: json[key],
  };
  final moved = jsonDecode(
    jsonEncode(json).replaceAll(from, to).replaceAll(fromSite, toSite),
  ) as Map<String, dynamic>..addAll(keep);
  return BookSource.fromJson(moved)
    ..bookSourceUrl = siteMovedUrl(source.bookSourceUrl, movedTo);
}

/// [source] 套用同網站 [fixed] 的規則：規則、標頭、程式庫與類型照 [fixed]，
/// 網址開頭跟著 [fixed] 換；名稱、分組、網址後面的標記與使用者的設定照
/// [source]。
BookSource sharedSource(BookSource source, BookSource fixed) {
  final rules = sourceForAi(fixed)
    ..remove('bookSourceName')
    ..remove('bookSourceGroup')
    ..remove('bookSourceComment');
  return candidateFrom(source, {
    ...rules,
    'bookSourceUrl': siteOrigin(fixed.bookSourceUrl) ?? fixed.bookSourceUrl,
  });
}
