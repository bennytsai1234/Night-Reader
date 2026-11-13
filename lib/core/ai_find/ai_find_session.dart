import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/ai_repair/agent_loop.dart';
import 'package:night_reader/core/ai_repair/ai_chat_client.dart';
import 'package:night_reader/core/ai_repair/ai_repair_log.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart'
    show AiRepairStep, AiRepairStepState;
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';

import 'ai_find_library.dart';
import 'ai_find_prompt.dart';

/// 推薦的一本：[book] 是工具找到的那張卡（點了照它的來源進書籍詳情），
/// [reason] 是 AI 寫的推薦理由。
typedef AiFindPick = ({SearchBook book, String reason});

/// 一次找書怎麼結束的。
enum AiFindOutcome {
  /// AI 交出了推薦（可能是零本）。
  found,

  /// 使用者按了停止。
  stopped,

  /// 沒找完：輪數用完、卡住、失控，或服務出了錯。
  unfinished,
}

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
  }) : log = log ?? AiRepairLog.find(description: description);

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
  final Map<String, List<String>> _searches = {};
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
  String redact(String text) => text;

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
    s.log.both('讀不懂工具呼叫：${read.fact}');
    return AgentBadCommand(read.fact);
  }

  @override
  String noToolCall(AiReply reply) {
    _finishRound('沒有呼叫工具', failed: true);
    s.log.both('沒有呼叫工具');
    return '# 這一輪沒有呼叫工具';
  }

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
    var ids = _searches[cacheKey];
    if (ids == null) {
      final books = await _library.search(
        command.keyword,
        command.kind,
        _cancel,
      );
      ids = [for (final book in books) _register(book).id];
      _searches[cacheKey] = ids;
    }
    _say('$label，找到 ${ids.length} 本');
    final text = _bookPage(
      '# 搜尋「${command.keyword}」（${_kindLabel(command.kind)}）',
      ids,
      command.page,
      empty: '沒有搜到書',
    );
    s.log.note(_head(text));
    return AgentToolResult(text);
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
        '${e.name}｜${e.author.isEmpty ? '作者不明' : e.author}｜'
            '${_kindLabel(e.kind)}${e.local ? '（手機上的檔案）' : ''}',
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
    List<String> ids,
    int page, {
    required String empty,
  }) {
    if (ids.isEmpty) return '$heading：$empty';
    final from = (page - 1) * aiFindSearchPageSize;
    if (from >= ids.length) {
      return '$heading：共 ${ids.length} 本，沒有第 $page 批';
    }
    final to = (from + aiFindSearchPageSize).clamp(0, ids.length);
    final more = to < ids.length ? '，還有，用 page ${page + 1} 接著拿' : '';
    return '$heading：共 ${ids.length} 本，這是第 ${from + 1} 到 $to 本$more\n'
        '${ids.sublist(from, to).map((id) => _bookLine(_books[id]!)).join('\n')}';
  }

  static String _bookLine(_Found found) {
    final b = found.book;
    String? clean(String? value) =>
        (value ?? '').trim().isEmpty ? null : value!.trim();
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
  void _say(String text) {
    final round = _round;
    if (round == null) return;
    final done = round.detail ?? '';
    final parts = done.isEmpty ? <String>[] : done.split('；');
    // 同一個工具的進行中那句（結尾「…」）換成做完的那句。
    if (parts.isNotEmpty && parts.last.endsWith('…')) parts.removeLast();
    parts.add(text);
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
