import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/ai_repair/agent_loop.dart';
import 'package:night_reader/core/ai_repair/ai_chat_client.dart';
import 'package:night_reader/core/ai_repair/ai_repair_log.dart';
import 'package:night_reader/core/ai_repair/ai_repair_secrets.dart';
import 'package:night_reader/core/ai_repair/ai_repair_settings.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart'
    show AiRepairStep, AiRepairStepState;
import 'package:night_reader/core/models/ai_find_record.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/core/utils/string_utils.dart';
import 'package:pool/pool.dart';
import 'package:uuid/uuid.dart';

import 'ai_find_library.dart';
import 'ai_find_prompt.dart';

/// 完整紀錄裡統計那一行的開頭，後面接 JSON（同 AI 修復的評估表）。
const String aiFindStatsMarker = 'NR-AI-FIND-STATS ';

/// 暫停的找書存檔的格式版本（[AiFindSession.restore]）：改了存什麼就加一，
/// 舊版存的接不下去，照沒找完收尾。
const int aiFindProgressVersion = 1;

/// 一次 AI 找書（ADR 0060）：使用者的描述與深度交給和任務無關的迴圈
/// （[runAgent]），工具的實際抓取在 [AiFindLibrary]。頁面看 [rounds]、
/// [tokens] 與結果；返回或離開夜讀照跑（背景工作）。
class AiFindSession extends ChangeNotifier {
  AiFindSession({
    required this.description,
    required this.depth,
    required this._library,
    required this._ask,
    this.serviceLabel = '',
    this.scope = '',
    AiRepairLog? log,
    String? id,
    DateTime? startedAt,
  }) : log = log ?? AiRepairLog.find(description: description),
       id = id ?? const Uuid().v4(),
       startedAt = startedAt ?? DateTime.now();

  /// 讀回暫停時存的 [progress]（每一輪開頭存的那份），還沒開始；[start] 從
  /// 存的那一輪接著問（背景工作接著做，ADR 0058）。[log] 是同一次開 App 裡
  /// 暫停前的紀錄；App 重開後沒有，接著寫同一個檔。格式不對時丟
  /// [FormatException]。
  factory AiFindSession.restore(
    String progress, {
    required AiFindLibrary library,
    required AgentAsk ask,
    String serviceLabel = '',
    AiRepairLog? log,
  }) {
    final json = switch (jsonDecode(progress)) {
      final Map<String, Object?> map
          when map['version'] == aiFindProgressVersion =>
        map,
      _ => throw const FormatException('不是這一版存的找書'),
    };
    T read<T>(String key) => switch (json[key]) {
      final T value => value,
      _ => throw FormatException('找書的存檔少了 $key'),
    };
    final description = read<String>('description');
    final session = AiFindSession(
      description: description,
      depth: AiFindDepth.fromName(read<String>('depth')),
      library: library,
      ask: ask,
      serviceLabel: serviceLabel,
      scope: read<String>('scope'),
      log:
          log ??
          AiRepairLog.find(
            description: description,
            fileName: read<String>('log'),
          ),
      id: read<String>('id'),
      startedAt: DateTime.fromMillisecondsSinceEpoch(read<int>('startedAt')),
    );
    session
      ..tokens = read<int>('tokens')
      ..rounds.addAll([
        for (final round in read<List<Object?>>('rounds'))
          AiRepairStep.fromJson(round),
      ])
      .._resume = AgentCheckpoint.fromJson(read<Map<String, Object?>>('loop'))
      .._agentState = read<Map<String, Object?>>('agent');
    return session;
  }

  /// 存檔裡的搜尋範圍；讀不出來是 null。
  static String? scopeOf(String progress) => _field(progress, 'scope');

  /// 存檔裡的「主機名 · 模型」；讀不出來是 null。
  static String? serviceLabelOf(String progress) =>
      _field(progress, 'serviceLabel');

  static String? _field(String progress, String key) {
    try {
      final json = jsonDecode(progress);
      return json is Map<String, Object?> && json[key] is String
          ? json[key]! as String
          : null;
    } on FormatException {
      return null;
    }
  }

  /// 存檔裡看得出來的那幾項（描述、深度、開始的時刻），接不下去時用來
  /// 照沒找完收尾；連這些都讀不出來是 null。
  static AiFindRecord? brokenRecord(String progress, String why) {
    try {
      final json = jsonDecode(progress);
      if (json case {
        'id': final String id,
        'description': final String description,
        'depth': final String depth,
        'startedAt': final int startedAt,
      }) {
        return AiFindRecord(
          id: id,
          description: description,
          depth: depth,
          createdAt: startedAt,
          outcome: AiFindOutcome.unfinished,
          failure: why,
          rounds: switch (json['rounds']) {
            final List<Object?> rounds => rounds.length,
            _ => 0,
          },
          tokens: switch (json['tokens']) {
            final int tokens => tokens,
            _ => 0,
          },
        );
      }
    } on FormatException {
      // 讀不出來就不留。
    }
    return null;
  }

  /// 這次找書的編號：存成「過去的找書」那一筆時用（兩台不會撞號）。
  final String id;

  /// 問使用者的 AI 服務，帶著找書的工具。
  static AgentAsk askService(AiService service) {
    final client = AiChatClient(service);
    return (messages, cancelToken) =>
        client.complete(messages, tools: aiFindTools, cancelToken: cancelToken);
  }

  final String description;
  final AiFindDepth depth;

  /// 「送到 主機名 · 模型」那行。
  final String serviceLabel;

  /// 搜尋範圍（`SearchScope` 的文字）：存進暫停的存檔，接著做時照同一個範圍。
  final String scope;
  final AiRepairLog log;
  final AiFindLibrary _library;
  final AgentAsk _ask;
  final CancelToken _cancelToken = CancelToken();
  final DateTime startedAt;

  /// 每一輪開頭存下的那份（JSON 文字），給背景工作寫進檔案。
  void Function(String progress)? onCheckpoint;

  /// 接著做時迴圈與工具的狀態（[restore] 讀回來的）。
  AgentCheckpoint? _resume;
  Map<String, Object?>? _agentState;

  /// 一輪一列（頁面上的「第 N 輪」）。
  final List<AiRepairStep> rounds = [];

  /// 這次找書用了多少 token（服務回報的送出加回覆，含打中快取的）。
  int tokens = 0;

  List<AiFindPick> picks = const [];

  /// AI 交出時寫的說明。
  String summary = '';

  AiFindOutcome? outcome;

  /// 沒找完時的原因。
  String? failure;

  AgentStats? stats;

  bool _started = false;
  bool _stopped = false;
  bool _pausing = false;
  bool _paused = false;
  bool _disposed = false;

  bool get isRunning => _started && outcome == null && !_paused;
  bool get isFinished => outcome != null;

  /// 按了結束、還沒停好或已經停好。
  bool get isStopped => _stopped;

  /// 按了暫停、正在等進行中的搜尋停下。
  bool get isPausing => _pausing && !_paused;

  /// 停在一輪開頭，等使用者按繼續或結束。
  bool get isPaused => _paused;

  /// 接著做時從第幾輪問起（頁面上「從第 N 輪接著問」）。
  int get nextRound => rounds.length + 1;

  /// 開始找，或從存的那一輪接著找；回傳找完（結束、出錯也算）或暫停好的
  /// 時刻。
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _notify();
    final resume = _resume;
    _resume = null;
    log.redact = (text) => redactAiRepairSecrets(text, _library.secrets);
    if (resume == null) {
      log
        ..header(
          '$serviceLabel · 深度 ${depth.label}',
          prompt: aiFindPromptVersion,
        )
        ..full('（迴圈的設定：${AiAgentKnobs.summary}）')
        ..tools(
          const JsonEncoder.withIndent('  ').convert(aiToolsJson(aiFindTools)),
        );
    } else {
      log
        ..section('接著做')
        ..both('從第 $nextRound 輪接著問（$serviceLabel）');
    }
    final agent = _FindAgent(this);
    if (resume != null) agent.restore(_agentState ?? const {}, resume);
    _agentState = null;
    final AgentEnd end;
    try {
      end = await runAgent(
        agent,
        ask: _ask,
        cancelToken: _cancelToken,
        resume: resume,
      );
    } catch (error, stack) {
      // 迴圈本身不該丟；丟了也要有結果，不讓頁面停在進行中。
      log.both('找書中斷：$error\n$stack');
      _end(AiFindOutcome.unfinished, '找書中斷：$error');
      return;
    }
    stats = end.stats;
    if (end.kind == AgentEndKind.cancelled && _pausing && !_stopped) {
      // 暫停：結果不寫、紀錄不收尾；接著做的是最後存的那一輪開頭。
      _paused = true;
      log
        ..section('暫停')
        ..both('暫停了，存的是第 ${stats!.rounds} 輪問完之後的樣子');
      _notify();
      return;
    }
    switch (end.kind) {
      case AgentEndKind.completed:
        _end(AiFindOutcome.found, null);
      case AgentEndKind.cancelled:
        _end(AiFindOutcome.stopped, '已結束');
      case AgentEndKind.unconfirmed || AgentEndKind.failed:
        _end(AiFindOutcome.unfinished, end.reason);
    }
    _logStats(end);
  }

  /// 這次找書的報告（「過去的找書」的一筆）；還沒結束時是 null。停止與沒
  /// 找完的也留著（ADR 0060：每一次找書都留著）。
  AiFindRecord? get record {
    final value = outcome;
    if (value == null) return null;
    return AiFindRecord(
      id: id,
      description: description,
      depth: depth.name,
      createdAt: startedAt.millisecondsSinceEpoch,
      outcome: value,
      failure: failure ?? '',
      summary: summary,
      picks: picks,
      rounds: rounds.length,
      tokens: tokens,
    );
  }

  /// 結束：正在跑的搜尋與抓取跟著取消，結果照「已結束」收尾。暫停中（或
  /// 還沒開始接著做）的直接收尾。
  void stop() {
    if (_stopped || isFinished) return;
    _stopped = true;
    if (!_started || _paused) {
      _end(AiFindOutcome.stopped, '已結束');
      return;
    }
    if (!_cancelToken.isCancelled) _cancelToken.cancel('已結束');
    final last = rounds.lastOrNull;
    if (last != null && last.state == AiRepairStepState.running) {
      last
        ..state = AiRepairStepState.failed
        ..detail = '已結束';
    }
    _notify();
  }

  /// 暫停：正在跑的搜尋與抓取跟著取消；接著做時從最後存的那一輪開頭問起，
  /// 這一輪做到一半的不留。
  void pause() {
    if (!isRunning || _pausing || _stopped) return;
    _pausing = true;
    if (!_cancelToken.isCancelled) _cancelToken.cancel('已暫停');
    _notify();
  }

  /// 存一份「這一輪開頭」的樣子（[AgentTask.checkpoint] 叫的）：同步編成
  /// 文字，之後的工具改了狀態也不影響存下的這份。
  void _checkpoint(AgentCheckpoint state, Map<String, Object?> agent) {
    final save = onCheckpoint;
    if (save == null) return;
    save(
      jsonEncode({
        'version': aiFindProgressVersion,
        'prompt': aiFindPromptVersion,
        'id': id,
        'description': description,
        'depth': depth.name,
        'scope': scope,
        'serviceLabel': serviceLabel,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'log': log.fileName,
        'tokens': tokens,
        // 存的時候上一輪的每個呼叫都有結果了：還在轉的那一列存成做完。
        'rounds': [
          for (final round in rounds)
            if (round.state == AiRepairStepState.running)
              (AiRepairStep(
                round.title,
                detail: round.detail,
              )..state = AiRepairStepState.done).toJson()
            else
              round.toJson(),
        ],
        'loop': state.toJson(),
        'agent': agent,
      }),
    );
  }

  void _end(AiFindOutcome value, String? reason) {
    outcome = value;
    failure = reason;
    final last = rounds.lastOrNull;
    if (last != null && last.state == AiRepairStepState.running) {
      last.state = value == AiFindOutcome.found
          ? AiRepairStepState.done
          : AiRepairStepState.failed;
    }
    log
      ..section('結果')
      ..both(switch (value) {
        AiFindOutcome.found =>
          '推薦 ${picks.length} 本：'
              '${picks.map((p) => p.book.name).join('、')}\n$summary',
        AiFindOutcome.stopped => '已結束',
        AiFindOutcome.unfinished => '沒有找完：$reason',
      })
      ..finish();
    _notify();
  }

  void _logStats(AgentEnd end) {
    final s = end.stats;
    log.full(
      '$aiFindStatsMarker${jsonEncode({'description': description, 'depth': depth.name, 'end': end.kind.name, 'reason': end.reason, 'picks': picks.length, 'promptVersion': aiFindPromptVersion, ...s.toMap()})}',
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (!_cancelToken.isCancelled) _cancelToken.cancel('已關閉');
    super.dispose();
  }
}

/// 工具找到的一本書與 AI 查過它什麼。
class _Found {
  _Found(this.id, this.book);
  final String id;
  SearchBook book;
  Book? detail;
  bool detailTried = false;
  bool readTried = false;
}

/// 找書這件事（[AgentTask]）：開場是描述與深度，指令是 [AiFindCommand]，
/// 交出由這裡照深度驗收。
final class _FindAgent implements AgentTask<AiFindCommand> {
  _FindAgent(this.s);

  final AiFindSession s;

  final Map<String, _Found> _books = {};
  final Map<String, String> _idByIdentity = {};

  /// 搜過的關鍵字：結果與那次搜尋實際的情況（送了幾個書源、花多久），接著
  /// 拿下一批時不再搜一次。編號在給 AI 看到時才給：一次搜尋常有上萬本，
  /// 全部編號的話後面的書編到 b15226（2026-11-15 實跑）。
  final Map<String, Future<_Search>> _searches = {};
  List<AiFindExploreSource>? _exploreSources;

  /// 同時跑幾個搜尋：一個搜尋就同時問 thread_count 個書源（預設 8），每個搜尋
  /// 50 秒到就停（書庫的 `aiFindSearchLimit`）。一起送的越多，書源互搶書源 isolate、
  /// 50 秒內回來的越少（2026-11-15 量的：單獨搜 396 個書源有 91 個沒回來，兩個
  /// 一起搜 192 到 218 個）。使用者 2026-11-15 選兩個，其餘排隊。
  final Pool _searchSlots = Pool(2);
  final Map<String, List<String>> _categories = {};
  AiRepairStep? _round;
  int _logged = 0;

  AiFindLibrary get _library => s._library;
  CancelToken get _cancel => s._cancelToken;

  @override
  List<AiMessage> opening() =>
      aiFindOpening(description: s.description, depth: s.depth);

  @override
  String redact(String text) => redactAiRepairSecrets(text, _library.secrets);

  /// 每一輪開頭存下工具的狀態：書的編號（對話裡用編號指書）、看過詳情與
  /// 正文沒有、發現頁的書源與分類（編號照順序）。搜過的結果不存：書多，
  /// 接著做時要下一批會重搜一次。
  @override
  void checkpoint(AgentCheckpoint state) {
    s._checkpoint(state, {
      'books': [
        for (final found in _books.values)
          {
            'id': found.id,
            'book': found.book.toJson(),
            'origins': [
              for (final (i, origin) in found.book.origins.indexed)
                [origin, found.book.sourceLabels[i]],
            ],
            'detailTried': found.detailTried,
            'readTried': found.readTried,
            if (found.detail case final detail?)
              'detail': {
                'coverUrl': detail.coverUrl,
                'intro': detail.intro,
                'wordCount': detail.wordCount,
                'kind': detail.kind,
              },
          },
      ],
      if (_exploreSources case final sources?)
        'exploreSources': [
          for (final source in sources)
            {'url': source.url, 'name': source.name, 'kind': source.kind.name},
        ],
      'categories': _categories,
    });
  }

  /// 讀回 [checkpoint] 存的工具狀態；[resume] 的對話已經寫進紀錄。
  void restore(Map<String, Object?> json, AgentCheckpoint resume) {
    _logged = resume.messages.length;
    for (final item in switch (json['books']) {
      final List<Object?> list => list,
      _ => const <Object?>[],
    }) {
      if (item case {
        'id': final String id,
        'book': final Map<String, Object?> data,
      }) {
        final book = SearchBook.fromJson(data);
        if (item['origins'] case final List<Object?> origins) {
          for (final origin in origins) {
            if (origin case [final String url, final String name]) {
              book.addOrigin(url, name: name == url ? null : name);
            }
          }
        }
        final found = _Found(id, book)
          ..detailTried = item['detailTried'] == true
          ..readTried = item['readTried'] == true;
        if (item['detail'] case final Map<String, Object?> detail) {
          String? text(String key) => switch (detail[key]) {
            final String value => value,
            _ => null,
          };
          found.detail = Book(
            name: book.name,
            author: book.author ?? '',
            coverUrl: text('coverUrl'),
            intro: text('intro'),
            wordCount: text('wordCount'),
            kind: text('kind'),
          );
        }
        _books[id] = found;
        _idByIdentity[_identity(book)] = id;
      }
    }
    if (json['exploreSources'] case final List<Object?> sources) {
      _exploreSources = [
        for (final source in sources)
          if (source case {
            'url': final String url,
            'name': final String name,
            'kind': final String kind,
          })
            (
              url: url,
              name: name,
              kind: BookSourceKind.values.firstWhere(
                (value) => value.name == kind,
                orElse: () => BookSourceKind.novel,
              ),
            ),
      ];
    }
    if (json['categories'] case final Map<String, Object?> categories) {
      for (final MapEntry(:key, :value) in categories.entries) {
        if (value case final List<Object?> names) {
          _categories[key] = [for (final name in names) '$name'];
        }
      }
    }
  }

  @override
  void restart(int attempt, String why) {
    _books.clear();
    _idByIdentity.clear();
    _searches.clear();
    _exploreSources = null;
    _categories.clear();
    _logged = 0;
    s.log
      ..section('重新開始（第 $attempt 次）')
      ..both('上一次沒跑完：$why；換一段新的對話，從開場重來');
  }

  @override
  void roundStarted(int attempt, int round, List<AiMessage> messages) {
    final previous = _round;
    if (previous != null && previous.state == AiRepairStepState.running) {
      previous.state = AiRepairStepState.done;
    }
    final title = attempt == 1 ? '第 $round 輪' : '第 $attempt 次 · 第 $round 輪';
    _round = AiRepairStep(title, detail: '想下一步…');
    s.rounds.add(_round!);
    s._notify();
    s.log.section(title, round: true);
    for (final message in messages.skip(_logged)) {
      s.log.message(message.role, message.content);
    }
    _logged = messages.length;
  }

  @override
  void roundEnded(AgentRoundRecord record) {
    if (record.usage case final usage?) {
      s.tokens += usage.prompt + usage.completion;
    }
    s.log.both(agentRoundText(record));
    final reply = record.reply;
    if (reply == null) {
      if (!s._stopped) {
        _finishRound((record.error ?? '沒有回覆').split('\n').first, failed: true);
      }
      s.log.full(record.error ?? '沒有回覆');
      s._notify();
      return;
    }
    if (reply.reasoning.isNotEmpty) s.log.thinking(reply.reasoning);
    if (reply.content.trim().isNotEmpty) s.log.reply(reply.content);
    for (final call in reply.toolCalls) {
      s.log.toolCall(call.name, call.arguments);
    }
    if (reply.toolCalls.isNotEmpty) _round?.detail = '';
    _logged = record.sentMessages + 1;
    s._notify();
  }

  @override
  void factAdded(String fact) {}

  @override
  AgentParse<AiFindCommand> parse(AiToolCall call) {
    final read = readAiFindCall(call);
    if (read.command case final command?) {
      return AgentCommand(command, read.key);
    }
    _say('讀不懂工具呼叫');
    s.log.both(
      '讀不懂工具呼叫：${read.fact}'
      '${read.malformed ? '（這則回覆不接進對話，同一段對話重送）' : ''}',
    );
    return AgentBadCommand(read.fact, malformed: read.malformed);
  }

  @override
  String noToolCall(AiReply reply) {
    _finishRound('沒有呼叫工具', failed: true);
    s.log.both('沒有呼叫工具');
    return '# 這一輪沒有呼叫工具';
  }

  /// 交出以外都是只讀的查詢：同一則回覆的幾個搜尋一起送（一次搜尋要等
  /// 全部書源，約 70 到 90 秒）。交出要看前面查過哪幾本，照順序。
  @override
  bool runsAlongside(AiFindCommand command) => command is! AiFindSubmit;

  @override
  Future<AgentResult> execute(AiFindCommand command) async {
    try {
      return switch (command) {
        AiFindSearch() => await _search(command),
        AiFindDetail() => await _detail(command),
        AiFindRead() => await _read(command),
        AiFindExplore() => await _explore(command),
        AiFindNames() => await _names(command),
        AiFindShelf() => await _shelf(),
        AiFindSubmit() => _submit(command),
      };
    } catch (error) {
      if (_cancel.isCancelled) return const AgentToolResult('已停止');
      final message = error is DioException
          ? (error.message ?? '$error')
          : '$error';
      s.log.both('工具出錯：$message');
      return AgentToolResult('# 出錯：$message');
    }
  }

  // ---------- 工具 ----------

  Future<AgentResult> _search(AiFindSearch command) async {
    final label = '搜尋「${command.keyword}」${_kindLabel(command.kind)}';
    _say('$label…');
    final cacheKey = '${command.kind.name}\u0000${command.keyword}';
    // 存的是搜尋本身：同一則回覆裡同樣的搜尋一起開始時，第二個等第一個。
    final pending = _searches.putIfAbsent(cacheKey, () => _runSearch(command));
    final _Search search;
    try {
      search = await pending;
    } catch (_) {
      // 出錯的不留著：下次同樣的搜尋重搜。
      _searches.remove(cacheKey)?.ignore();
      rethrow;
    }
    final books = search.books;
    _say('$label，找到 ${books.length} 本', replacing: '$label…');
    final text = _bookPage(
      '# 搜尋「${command.keyword}」（${_kindLabel(command.kind)}，${search.facts}）',
      books,
      command.page,
      empty: '沒有搜到書',
      tiers: search.tiers,
    );
    s.log.note(_head(text));
    return AgentToolResult(text);
  }

  Future<_Search> _runSearch(AiFindSearch command) =>
      // 計時從輪到它開始：排隊等的時間不算這次搜尋花的。
      _searchSlots.withResource(() async {
        final watch = Stopwatch()..start();
        final result = await _library.search(
          command.keyword,
          command.kind,
          _cancel,
        );
        // 只給完全相符與部分相符（使用者 2026-11-15）：其他結果多半是不理
        // 關鍵字、回固定書單的書源給的，「咒術迴戰」682 本裡有 458 本。
        final books = <SearchBook>[];
        final tiers = <int>[];
        for (final (i, book) in result.books.indexed) {
          final tier = i < result.tiers.length ? result.tiers[i] : 2;
          if (tier > 1) continue;
          books.add(book);
          tiers.add(tier);
        }
        final dropped = result.books.length - books.length;
        return (
          books: books,
          tiers: tiers,
          facts:
              '送了 ${result.sources} 個書源'
              '${result.failed > 0 ? '，${result.failed} 個出錯或逾時' : ''}'
              '${result.pending > 0 ? '，${result.pending} 個到時限還沒回來、不等了' : ''}，'
              '花 ${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} 秒'
              '${dropped > 0 ? '；另有 $dropped 本書名與作者都不含這個詞，沒列出' : ''}',
        );
      });

  Future<AgentResult> _detail(AiFindDetail command) async {
    final found = _books[command.book];
    if (found == null) return _unknownBook(command.book);
    _say('看詳情：${found.book.name}');
    found.detailTried = true;
    final Book book;
    try {
      book = await _library.detail(found.book, _cancel);
    } catch (error) {
      if (_cancel.isCancelled) rethrow;
      return AgentToolResult('# ${found.id} 的詳情抓不到：$error');
    }
    found.detail = book;
    // 書源規則抓到的欄位常帶 HTML 標籤與換行（2026-11-15 實跑：簡介是
    // `<div class=…>`、分類跨好幾行），照正文一樣清成純文字。
    String field(String label, String? value) {
      final text = aiFindPlainText(value ?? '').replaceAll('\n', ' ');
      return text.isEmpty ? '' : '$label：$text\n';
    }

    final intro = aiFindPlainText(
      book.customIntro ?? book.intro ?? found.book.intro ?? '',
    );
    final text =
        '# ${found.id} 的詳情\n'
        '書名：${book.name.isEmpty ? found.book.name : book.name}\n'
        '${field('作者', book.author.isEmpty ? found.book.author : book.author)}'
        '${field('分類與標籤', book.kind ?? found.book.kind)}'
        '${field('字數', book.wordCount ?? found.book.wordCount)}'
        '${field('最新章節', book.latestChapterTitle ?? found.book.latestChapterTitle)}'
        // ADR 0060 的詳情有章數；詳情頁多半沒寫，要讀目錄才知道，不知道就說。
        '章數：${book.totalChapterNum > 0 ? '${book.totalChapterNum} 章' : '詳情頁沒寫（讀章節時會知道）'}\n'
        '簡介：${intro.isEmpty ? '（沒有）' : intro}';
    s.log.note(_head(text));
    return AgentToolResult(text);
  }

  Future<AgentResult> _read(AiFindRead command) async {
    final found = _books[command.book];
    if (found == null) return _unknownBook(command.book);
    if (found.book.bookKind != BookSourceKind.novel) {
      return AgentToolResult(
        '# ${found.id} 是${_kindLabel(found.book.bookKind)}，讀不了正文；看詳情就好',
      );
    }
    _say('讀《${found.book.name}》第 ${command.chapter} 章');
    found.readTried = true;
    final AiFindChapter chapter;
    try {
      chapter = await _library.chapter(found.book, command.chapter, _cancel);
    } on AiFindUnreadable catch (error) {
      return AgentToolResult(
        '# ${found.id} 第 ${command.chapter} 章讀不到：${error.message}',
      );
    }
    final text = chapter.text;
    final from = command.from.clamp(0, text.length);
    final to = (from + aiFindReadLength).clamp(0, text.length);
    final next = to < text.length ? '，下一段從 $to 讀' : '，這章讀完了';
    final reply =
        '# ${found.id}《${found.book.name}》第 ${command.chapter}／'
        '${chapter.total} 章 ${chapter.title}（這章共 ${text.length} 字，'
        '這是 $from 到 $to$next）\n${text.substring(from, to)}';
    s.log.note(_head(reply));
    return AgentToolResult(reply);
  }

  Future<AgentResult> _explore(AiFindExplore command) async {
    final sources = _exploreSources ??= await _library.exploreSources();
    final sourceId = command.source;
    if (sourceId == null) {
      _say('看發現頁');
      final text = sources.isEmpty
          ? '# 搜尋範圍裡沒有書源有發現頁'
          : '# 有發現頁的書源\n${[for (final (i, source) in sources.indexed) 's${i + 1}｜${source.name}｜${_kindLabel(source.kind)}'].join('\n')}';
      s.log.note(_head(text));
      return AgentToolResult(text);
    }
    final index = int.tryParse(sourceId.substring(1)) ?? 0;
    if (!sourceId.startsWith('s') || index < 1 || index > sources.length) {
      return AgentToolResult('# 沒有編號 $sourceId 的書源：先不帶參數呼叫 explore 列出書源');
    }
    final source = sources[index - 1];
    final categories = _categories[source.url] ??= await _library
        .exploreCategories(source, _cancel);
    final category = command.category;
    if (category == null) {
      _say('看發現頁：${source.name}');
      final text = categories.isEmpty
          ? '# $sourceId ${source.name} 的發現頁沒有分類'
          : '# $sourceId ${source.name} 的分類\n${[for (final (i, name) in categories.indexed) '$i｜$name'].join('\n')}';
      s.log.note(_head(text));
      return AgentToolResult(text);
    }
    if (category >= categories.length) {
      return AgentToolResult(
        '# $sourceId 沒有第 $category 個分類，共 ${categories.length} 個（從 0 數）',
      );
    }
    _say('看發現頁：${source.name} ${categories[category]}');
    final books = await _library.exploreBooks(
      source,
      category,
      command.page,
      _cancel,
    );
    final ids = [for (final book in books) _register(book).id];
    final text = ids.isEmpty
        ? '# $sourceId ${source.name}「${categories[category]}」第 ${command.page} 頁沒有書'
        : '# $sourceId ${source.name}「${categories[category]}」第 ${command.page} 頁\n'
              '${ids.map((id) => _bookLine(_books[id]!)).join('\n')}';
    s.log.note(_head(text));
    return AgentToolResult(text);
  }

  Future<AgentResult> _names(AiFindNames command) async {
    _say('查「${command.name}」的別名');
    final AiFindWorkNames? found;
    try {
      found = await _library.workNames(command.name, _cancel);
    } on AiFindUnreadable catch (error) {
      return AgentToolResult('# 查不到「${command.name}」的別名：${error.message}');
    }
    if (found == null) {
      return AgentToolResult('# 中文維基百科沒有「${command.name}」的條目');
    }
    final intro = found.intro.replaceAll(RegExp(r'\s+'), ' ');
    final text = [
      '# 「${command.name}」在中文維基百科：條目《${found.title}》',
      for (final MapEntry(:key, :value) in found.names.entries) '$key：$value',
      if (found.aliases.isNotEmpty) '別名（轉到這個條目的名稱）：${found.aliases.join('、')}',
      if (intro.isNotEmpty)
        '開頭：${intro.length <= _wikiIntroLength ? intro : '${intro.substring(0, _wikiIntroLength)}…'}',
      if (found.others.isNotEmpty)
        '同一個詞搜到的其他條目：${found.others.join('、')}（不是要找的作品時，用條目名再查一次）',
    ].join('\n');
    s.log.note(_head(text));
    return AgentToolResult(text);
  }

  /// 維基百科條目開頭給幾字：夠看出是不是那部作品、有沒有寫其他譯名。
  static const int _wikiIntroLength = 300;

  Future<AgentResult> _shelf() async {
    _say('看書架與閱讀紀錄');
    final entries = await _library.shelf();
    String line(AiFindShelfEntry e) {
      final parts = [
        [
          e.name,
          e.author.isEmpty ? '作者不明' : e.author,
          if (e.kind case final kind?)
            '${_kindLabel(kind)}${e.local ? '（手機上的檔案）' : ''}',
        ].join('｜'),
        if (e.readSeconds > 0) '讀了 ${_duration(e.readSeconds)}',
        if (e.chapterIndex != null && e.chapterTotal != null)
          '讀到第 ${e.chapterIndex}／${e.chapterTotal} 章'
        else if (e.chapter != null)
          '讀到 ${e.chapter}',
      ];
      return parts.join('｜');
    }

    final shelf = [
      for (final e in entries)
        if (e.onShelf) line(e),
    ];
    final records = [
      for (final e in entries)
        if (!e.onShelf) line(e),
    ];
    final text = [
      '# 書架（${shelf.length} 本）',
      if (shelf.isEmpty) '（空的）' else ...shelf,
      '',
      '# 已經移出書架、但讀過的（${records.length} 本）',
      if (records.isEmpty) '（沒有）' else ...records,
    ].join('\n');
    s.log.note(_head(text));
    return AgentToolResult(text);
  }

  AgentResult _submit(AiFindSubmit command) {
    _say('交出 ${command.books.length} 本');
    final problems = <String>[];
    final seen = <String>{};
    for (final pick in command.books) {
      final found = _books[pick.book];
      if (found == null) {
        problems.add('${pick.book}：沒有這個編號，只能交出工具回過的書');
        continue;
      }
      if (!seen.add(pick.book)) {
        problems.add('${pick.book}：重複了');
        continue;
      }
      if (s.depth != AiFindDepth.quick && !found.detailTried) {
        problems.add(
          '${pick.book}《${found.book.name}》：還沒看過詳情（深度 ${s.depth.label}）',
        );
        continue;
      }
      if (s.depth == AiFindDepth.deep &&
          found.book.bookKind == BookSourceKind.novel &&
          !found.readTried) {
        problems.add('${pick.book}《${found.book.name}》：還沒讀過正文（深度 深入）');
      }
    }
    if (problems.isNotEmpty) {
      _finishRound('交出被退回：${problems.length} 本不合', failed: true);
      final text = '# 交出被退回，這幾本不合：\n${problems.join('\n')}';
      s.log.both(text);
      return AgentRejected(text);
    }
    s.picks = [
      for (final pick in command.books)
        (book: _withDetail(_books[pick.book]!), reason: pick.reason),
    ];
    s.summary = command.summary;
    _finishRound('交出 ${command.books.length} 本');
    return const AgentAccepted();
  }

  // ---------- 輔助 ----------

  /// 同一本（同類、同名、同作者）拿同一個編號，之後看過的詳情也算數。
  _Found _register(SearchBook book) {
    // 書名、作者照搜尋頁合併同一本的寫法正規化（繁簡、全半形、空白、大小寫）：
    // 不同搜尋各挑的代表來源寫法不一樣時，同一本才不會拿兩個編號、被推薦兩次
    // （Codex 審查）。
    final identity = _identity(book);
    final existing = _idByIdentity[identity];
    if (existing != null) return _books[existing]!;
    final id = 'b${_books.length + 1}';
    final found = _Found(id, book);
    _books[id] = found;
    _idByIdentity[identity] = id;
    return found;
  }

  static String _identity(SearchBook book) =>
      '${book.bookKind.name}\u0000${_identityText(book.name)}'
      '\u0000${_identityText(book.author ?? '')}';

  static String _identityText(String text) => ChineseUtils.t2s(
    StringUtils.fullToHalf(text).replaceAll(RegExp(r'\s+'), '').toLowerCase(),
  );

  /// 推薦的那張卡補上詳情抓到的封面與簡介（點進去照卡片的來源）。
  SearchBook _withDetail(_Found found) {
    final book = found.book;
    final detail = found.detail;
    if (detail == null) return book;
    if ((book.coverUrl ?? '').isEmpty) book.coverUrl = detail.coverUrl;
    if ((book.intro ?? '').isEmpty) book.intro = detail.intro;
    if ((book.wordCount ?? '').isEmpty) book.wordCount = detail.wordCount;
    if ((book.kind ?? '').isEmpty) book.kind = detail.kind;
    return book;
  }

  /// 搜尋頁的分段（[AiFindSearchResult.tiers]）；其他結果不給 AI。
  static const List<String> _tierLabels = ['完全相符', '部分相符'];

  /// [tiers] 給了時（搜尋），照搜尋頁在每段第一本前面標段名。
  String _bookPage(
    String heading,
    List<SearchBook> books,
    int page, {
    required String empty,
    List<int>? tiers,
  }) {
    if (books.isEmpty) return '$heading：$empty';
    final from = (page - 1) * aiFindSearchPageSize;
    if (from >= books.length) {
      return '$heading：共 ${books.length} 本，沒有第 $page 批';
    }
    final to = (from + aiFindSearchPageSize).clamp(0, books.length);
    final more = to < books.length ? '，還有，用 page ${page + 1} 接著拿' : '';
    final lines = <String>[];
    for (var i = from; i < to; i++) {
      final tier = tiers != null && i < tiers.length ? tiers[i] : null;
      if (tier != null &&
          (i == from || tier != tiers![i - 1]) &&
          tier >= 0 &&
          tier < _tierLabels.length) {
        lines.add('## ${_tierLabels[tier]}');
      }
      lines.add(_bookLine(_register(books[i])));
    }
    return '$heading：共 ${books.length} 本，這是第 ${from + 1} 到 $to 本$more\n'
        '${lines.join('\n')}';
  }

  static String _bookLine(_Found found) {
    final b = found.book;
    // 欄位裡的換行與連續空白合成一個空格：書源規則抓到的字串有時帶換行，
    // 一本一行的格式就斷了（2026-11-15 實跑：「完结\n{{$..shortName」）。
    String? clean(String? value) {
      final text = (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      return text.isEmpty ? null : text;
    }

    return [
      found.id,
      b.name,
      clean(b.author) ?? '作者不明',
      ?clean(b.wordCount),
      ?clean(b.kind),
      if (clean(b.latestChapterTitle) case final latest?) '最新：$latest',
      '${b.origins.length} 個書源',
      if (_introHead(b.intro) case final intro?) '簡介：$intro',
    ].join('｜');
  }

  /// 書卡上簡介的開頭：清成一行純文字，最多 [_introLength] 字。
  static String? _introHead(String? intro) {
    final text = aiFindPlainText(intro ?? '').replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return null;
    return text.length <= _introLength
        ? text
        : '${text.substring(0, _introLength)}…';
  }

  /// 書卡上的簡介給幾字：夠看出故事是什麼，不用每本都點詳情（使用者
  /// 2026-11-15 同意加）。
  static const int _introLength = 60;

  AgentResult _unknownBook(String id) =>
      AgentToolResult('# 沒有編號 $id 的書：編號在搜尋或發現頁的結果裡');

  static String _kindLabel(BookSourceKind kind) => switch (kind) {
    BookSourceKind.comic => '漫畫',
    BookSourceKind.audio => '有聲書',
    _ => '小說',
  };

  static String _duration(int seconds) {
    if (seconds < 3600) return '${(seconds / 60).ceil()} 分鐘';
    return '${(seconds / 3600).toStringAsFixed(1)} 小時';
  }

  static String _head(String text) =>
      text.length <= 400 ? text : '${text.substring(0, 400)}…';

  /// 這一輪在做的事寫進頁面的副標：同一輪的幾個呼叫用「；」接起來。
  ///
  /// [replacing] 是這個工具進行中的那句（結尾「…」）：換成做完的這句。同一輪
  /// 的幾個搜尋一起跑，做完的順序不一定，照那句找、不照位置。
  void _say(String text, {String? replacing}) {
    final round = _round;
    if (round == null) return;
    final done = round.detail ?? '';
    final parts = done.isEmpty ? <String>[] : done.split('；');
    final at = replacing == null ? -1 : parts.indexOf(replacing);
    if (at >= 0) {
      parts[at] = text;
    } else {
      parts.add(text);
    }
    round.detail = parts.join('；');
    s._notify();
  }

  void _finishRound(String text, {bool failed = false}) {
    final round = _round;
    if (round == null) return;
    _say(text);
    round.state = failed ? AiRepairStepState.failed : AiRepairStepState.done;
    s._notify();
  }
}

/// 一次搜尋記下的結果：書、搜尋頁的分段與那次實際的情況。
typedef _Search = ({List<SearchBook> books, List<int> tiers, String facts});
