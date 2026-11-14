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
import 'package:uuid/uuid.dart';

import 'ai_find_library.dart';
import 'ai_find_prompt.dart';

/// 完整紀錄裡統計那一行的開頭，後面接 JSON（同 AI 修復的評估表）。
const String aiFindStatsMarker = 'NR-AI-FIND-STATS ';

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
    AiRepairLog? log,
    String? id,
  }) : log = log ?? AiRepairLog.find(description: description),
       id = id ?? const Uuid().v4();

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
  final AiRepairLog log;
  final AiFindLibrary _library;
  final AgentAsk _ask;
  final CancelToken _cancelToken = CancelToken();
  final DateTime startedAt = DateTime.now();

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
  bool _disposed = false;

  bool get isRunning => _started && outcome == null;
  bool get isFinished => outcome != null;
  bool get isStopped => _stopped;

  /// 開始找；回傳找完（停下、出錯也算）的時刻。
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _notify();
    log
      ..redact = ((text) => redactAiRepairSecrets(text, _library.secrets))
      ..header('$serviceLabel · 深度 ${depth.label}', prompt: aiFindPromptVersion)
      ..full('（迴圈的設定：${AiAgentKnobs.summary}）')
      ..tools(
        const JsonEncoder.withIndent('  ').convert(aiToolsJson(aiFindTools)),
      );
    final agent = _FindAgent(this);
    final AgentEnd end;
    try {
      end = await runAgent(agent, ask: _ask, cancelToken: _cancelToken);
    } catch (error, stack) {
      // 迴圈本身不該丟；丟了也要有結果，不讓頁面停在進行中。
      log.both('找書中斷：$error\n$stack');
      _end(AiFindOutcome.unfinished, '找書中斷：$error');
      return;
    }
    stats = end.stats;
    switch (end.kind) {
      case AgentEndKind.completed:
        _end(AiFindOutcome.found, null);
      case AgentEndKind.cancelled:
        _end(AiFindOutcome.stopped, '已停止');
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

  /// 停下：正在跑的搜尋與抓取跟著取消。
  void stop() {
    if (_stopped || isFinished) return;
    _stopped = true;
    if (!_cancelToken.isCancelled) _cancelToken.cancel('已停止');
    final last = rounds.lastOrNull;
    if (last != null && last.state == AiRepairStepState.running) {
      last
        ..state = AiRepairStepState.failed
        ..detail = '已停止';
    }
    _notify();
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
        AiFindOutcome.stopped => '已停止',
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
  final Map<String, Future<({List<SearchBook> books, String facts})>>
  _searches = {};
  List<AiFindExploreSource>? _exploreSources;
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
    final ({List<SearchBook> books, String facts}) search;
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
    );
    s.log.note(_head(text));
    return AgentToolResult(text);
  }

  Future<({List<SearchBook> books, String facts})> _runSearch(
    AiFindSearch command,
  ) async {
    final watch = Stopwatch()..start();
    final result = await _library.search(
      command.keyword,
      command.kind,
      _cancel,
    );
    return (
      books: result.books,
      facts:
          '送了 ${result.sources} 個書源'
          '${result.failed > 0 ? '，${result.failed} 個出錯或逾時' : ''}，'
          '花 ${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} 秒',
    );
  }

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
    String field(String label, String? value) =>
        (value ?? '').trim().isEmpty ? '' : '$label：${value!.trim()}\n';
    final intro = (book.customIntro ?? book.intro ?? found.book.intro ?? '')
        .trim();
    final text =
        '# ${found.id} 的詳情\n'
        '書名：${book.name.isEmpty ? found.book.name : book.name}\n'
        '${field('作者', book.author.isEmpty ? found.book.author : book.author)}'
        '${field('分類與標籤', book.kind ?? found.book.kind)}'
        '${field('字數', book.wordCount ?? found.book.wordCount)}'
        '${field('最新章節', book.latestChapterTitle ?? found.book.latestChapterTitle)}'
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
    final identity =
        '${book.bookKind.name}\u0000${book.name.trim()}\u0000${(book.author ?? '').trim()}';
    final existing = _idByIdentity[identity];
    if (existing != null) return _books[existing]!;
    final id = 'b${_books.length + 1}';
    final found = _Found(id, book);
    _books[id] = found;
    _idByIdentity[identity] = id;
    return found;
  }

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

  String _bookPage(
    String heading,
    List<SearchBook> books,
    int page, {
    required String empty,
  }) {
    if (books.isEmpty) return '$heading：$empty';
    final from = (page - 1) * aiFindSearchPageSize;
    if (from >= books.length) {
      return '$heading：共 ${books.length} 本，沒有第 $page 批';
    }
    final to = (from + aiFindSearchPageSize).clamp(0, books.length);
    final more = to < books.length ? '，還有，用 page ${page + 1} 接著拿' : '';
    return '$heading：共 ${books.length} 本，這是第 ${from + 1} 到 $to 本$more\n'
        '${books.sublist(from, to).map((book) => _bookLine(_register(book))).join('\n')}';
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
    ].join('｜');
  }

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
