import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:night_reader/core/constant/app_pattern.dart';
import 'package:night_reader/core/engine/reader/chinese_text_converter.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/services/chinese_utils.dart';

import 'reader_v2_processed_chapter.dart';

class ReaderV2ContentTransformer {
  const ReaderV2ContentTransformer();

  static final Map<String, RegExp> _regexCache = {};
  static const String _duplicateTitleBoundary = r'(?=\s|\p{P}|$)';

  static RegExp _getOrCreateRegex(String pattern, {bool unicode = false}) {
    final key = '$pattern|$unicode';
    if (_regexCache.length > 500) {
      _regexCache.clear();
    }
    return _regexCache.putIfAbsent(
      key,
      () => RegExp(pattern, unicode: unicode),
    );
  }

  Future<ReaderV2ProcessedChapter> process({
    required Book book,
    required BookChapter chapter,
    required String rawContent,
    required List<ReplaceRule> enabledRules,
    required int chineseConvertType,
  }) async {
    final args = <String, Object?>{
      'bookName': book.name,
      'bookOrigin': book.origin,
      'chapterTitle': chapter.title,
      'rawContent': rawContent,
      'rulesJson': enabledRules.map((rule) => rule.toJson()).toList(),
      'useReplaceRules': book.getUseReplaceRule(),
      'reSegmentEnabled': book.getReSegment(),
      'chineseConvertType': chineseConvertType,
    };

    // 首選：常駐 worker isolate。免去每章 compute spawn，且簡繁轉換也在
    // worker 內完成（字典由主 isolate 送入初始化一次），主執行緒只剩訊息
    // 收發——fling 減速期間的內容預載不再佔用幀預算。
    final workerResult = await ReaderV2ContentTransformWorker.instance.process(
      args,
    );
    if (workerResult != null) {
      return _decodeProcessed(workerResult);
    }

    // 退回路徑（worker 不可用）：行為與舊版完全相同——compute 一次性
    // isolate 做替換/重分段，簡繁轉換因字典只在主 isolate 而留在主執行緒。
    final result = await compute(_processInBackground, args);
    final processed = _decodeProcessed(result);
    if (chineseConvertType == 0) return processed;
    const converter = ChineseTextConverter();
    return ReaderV2ProcessedChapter(
      displayTitle: converter.convert(
        processed.displayTitle,
        convertType: chineseConvertType,
      ),
      content: converter.convert(
        processed.content,
        convertType: chineseConvertType,
      ),
      effectiveReplaceRules: processed.effectiveReplaceRules,
      sameTitleRemoved: processed.sameTitleRemoved,
    );
  }

  static ReaderV2ProcessedChapter _decodeProcessed(
    Map<String, Object?> result,
  ) {
    final effectiveRules = (result['effectiveRules'] as List<dynamic>)
        .map(
          (rule) =>
              ReplaceRule.fromJson(Map<String, dynamic>.from(rule as Map)),
        )
        .toList(growable: false);
    return ReaderV2ProcessedChapter(
      displayTitle: result['displayTitle'] as String? ?? '',
      content: result['content'] as String? ?? '',
      effectiveReplaceRules: List<ReplaceRule>.unmodifiable(effectiveRules),
      sameTitleRemoved: result['sameTitleRemoved'] as bool? ?? false,
    );
  }

  static Map<String, Object?> _processInBackground(Map<String, Object?> args) {
    final bookName = args['bookName'] as String? ?? '';
    final bookOrigin = args['bookOrigin'] as String? ?? '';
    final chapterTitle = args['chapterTitle'] as String? ?? '';
    final rawContent = args['rawContent'] as String? ?? '';
    final rulesJson =
        (args['rulesJson'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
    final useReplaceRules = args['useReplaceRules'] as bool? ?? true;
    final reSegmentEnabled = args['reSegmentEnabled'] as bool? ?? true;
    final rules =
        rulesJson
            .map(ReplaceRule.fromJson)
            .where((rule) => rule.isEnabled)
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));

    final titleRules = rules
        .where(
          (rule) =>
              rule.appliesToTitle(bookName: bookName, bookOrigin: bookOrigin),
        )
        .toList(growable: false);
    final contentResult = _processContent(
      bookName: bookName,
      bookOrigin: bookOrigin,
      chapterTitle: chapterTitle,
      rawContent: rawContent,
      rules: rules,
      titleRules: titleRules,
      useReplaceRules: useReplaceRules,
      reSegmentEnabled: reSegmentEnabled,
    );
    final displayTitle = _processTitle(
      chapterTitle: chapterTitle,
      rules: titleRules,
      useReplaceRules: useReplaceRules,
    );

    return <String, Object?>{
      'displayTitle': displayTitle,
      'content': contentResult.content,
      'effectiveRules': contentResult.effectiveReplaceRules
          .map((rule) => rule.toJson())
          .toList(growable: false),
      'sameTitleRemoved': contentResult.sameTitleRemoved,
    };
  }

  static ReaderV2ProcessedChapter _processContent({
    required String bookName,
    required String bookOrigin,
    required String chapterTitle,
    required String rawContent,
    required List<ReplaceRule> rules,
    required List<ReplaceRule> titleRules,
    required bool useReplaceRules,
    required bool reSegmentEnabled,
  }) {
    if (rawContent.isEmpty) {
      return const ReaderV2ProcessedChapter(displayTitle: '', content: '');
    }

    var content = rawContent;
    var sameTitleRemoved = false;
    final effectiveRules = <ReplaceRule>[];

    final nameRegex = RegExp.escape(bookName);
    final titleRegex = RegExp.escape(
      chapterTitle,
    ).replaceAll(AppPattern.spaceRegex, r'\s*');
    final duplicateTitlePattern = _getOrCreateRegex(
      '^(\\s|\\p{P}|$nameRegex)*$titleRegex'
      '$_duplicateTitleBoundary(\\s)*',
      unicode: true,
    );
    final duplicateTitleMatch = duplicateTitlePattern.firstMatch(content);
    if (duplicateTitleMatch != null) {
      content = content.substring(duplicateTitleMatch.end);
      sameTitleRemoved = true;
    } else if (useReplaceRules && titleRules.isNotEmpty) {
      final displayTitle = _processTitle(
        chapterTitle: chapterTitle,
        rules: titleRules,
        useReplaceRules: true,
      );
      if (displayTitle.trim().isNotEmpty && displayTitle != chapterTitle) {
        final displayTitleRegex = RegExp.escape(
          displayTitle,
        ).replaceAll(AppPattern.spaceRegex, r'\s*');
        final displayDuplicateTitlePattern = _getOrCreateRegex(
          '^(\\s|\\p{P}|$nameRegex)*$displayTitleRegex'
          '$_duplicateTitleBoundary(\\s)*',
          unicode: true,
        );
        final displayDuplicateTitleMatch = displayDuplicateTitlePattern
            .firstMatch(content);
        if (displayDuplicateTitleMatch != null) {
          content = content.substring(displayDuplicateTitleMatch.end);
          sameTitleRemoved = true;
        }
      }
    }

    if (reSegmentEnabled) {
      content = _reSegment(content);
    }

    if (useReplaceRules) {
      final buffer = StringBuffer();
      final lines = content.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (i > 0) buffer.write('\n');
        buffer.write(lines[i].trim());
      }
      content = buffer.toString();
      for (final rule in rules) {
        if (!rule.appliesToContent(
          bookName: bookName,
          bookOrigin: bookOrigin,
        )) {
          continue;
        }

        try {
          final previous = content;
          content = rule.apply(content);
          if (content != previous) {
            effectiveRules.add(rule);
          }
        } catch (_) {}
      }
    }

    final paragraphs = <String>[];
    const indent = '　　';
    for (final line in content.split('\n')) {
      final paragraph = line.trim().replaceAll('\u00A0', ' ');
      if (paragraph.isNotEmpty) {
        paragraphs.add('$indent$paragraph');
      }
    }

    return ReaderV2ProcessedChapter(
      displayTitle: '',
      content: paragraphs.join('\n'),
      effectiveReplaceRules: List<ReplaceRule>.unmodifiable(effectiveRules),
      sameTitleRemoved: sameTitleRemoved,
    );
  }

  static String _reSegment(String content) {
    final normalized = content
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n');
    final nonEmptyLines =
        normalized.split('\n').where((line) => line.trim().isNotEmpty).length;
    if (nonEmptyLines > 1 || normalized.trim().length < 180) {
      return normalized;
    }
    return _splitSingleLineByPunctuation(normalized);
  }

  static String _splitSingleLineByPunctuation(String content) {
    final buffer = StringBuffer();
    for (var index = 0; index < content.length; index++) {
      final char = content[index];
      buffer.write(char);
      if (!_sentenceEndChars.contains(char)) continue;

      while (index + 1 < content.length &&
          _sentenceCloseChars.contains(content[index + 1])) {
        index += 1;
        buffer.write(content[index]);
      }

      if (index + 1 < content.length && content[index + 1].trim().isNotEmpty) {
        buffer.write('\n');
      }
    }
    return buffer.toString();
  }

  static const String _sentenceEndChars = '。！？!?；;';
  static const String _sentenceCloseChars = '」』”’））》〉】]';

  static String _processTitle({
    required String chapterTitle,
    required List<ReplaceRule> rules,
    required bool useReplaceRules,
  }) {
    var displayTitle = chapterTitle.replaceAll(RegExp(r'[\r\n]'), '');
    if (useReplaceRules) {
      for (final rule in rules) {
        if (rule.pattern.isEmpty) continue;
        try {
          final next = rule.apply(displayTitle);
          if (next.trim().isNotEmpty) {
            displayTitle = next;
          }
        } catch (_) {}
      }
    }
    return displayTitle;
  }
}

/// 常駐內容轉換 worker isolate。
///
/// 為什麼不用 compute：fling 放開瞬間會連續預載最多 3 章，compute 每章現場
/// spawn/銷毀一個 isolate；且簡繁字典只存在主 isolate 靜態區，轉換被迫留在
/// 主執行緒對整章正文執行，成本正好落在減速動畫期間。常駐 worker 只 spawn
/// 一次、字典初始化一次，之後替換規則＋重分段＋簡繁轉換全部離開主執行緒。
///
/// worker 不可用（spawn 失敗、isolate 死亡）時 [process] 回傳 null，呼叫端
/// 退回既有的 compute 路徑，行為不變。
class ReaderV2ContentTransformWorker {
  ReaderV2ContentTransformWorker._();

  static final ReaderV2ContentTransformWorker instance =
      ReaderV2ContentTransformWorker._();

  /// 測試鉤子：字典原文提供者。預設從 rootBundle 取（啟動時已載入快取）。
  @visibleForTesting
  static Future<List<String>?> Function() dictionaryDataLoader =
      loadDictionaryDataFromBundle;

  /// 測試鉤子：強制停用 worker，讓 process 走 compute 退回路徑。
  @visibleForTesting
  static bool debugDisableWorker = false;

  Future<SendPort?>? _starting;
  ReceivePort? _responses;
  Isolate? _isolate;
  bool _broken = false;
  int _nextRequestId = 0;
  final Map<int, Completer<Map<String, Object?>?>> _pending =
      <int, Completer<Map<String, Object?>?>>{};

  @visibleForTesting
  static Future<List<String>?> loadDictionaryDataFromBundle() async {
    try {
      return await Future.wait(
        ChineseUtils.dictionaryAssetPaths.map(rootBundle.loadString),
      );
    } catch (_) {
      // 測試環境或 asset 缺失：worker 內簡繁轉換退化為直通（與主 isolate
      // 字典未初始化時的行為一致）。
      return null;
    }
  }

  /// 轉換一章；回傳 null 代表 worker 不可用，呼叫端應退回 compute 路徑。
  Future<Map<String, Object?>?> process(Map<String, Object?> args) async {
    if (debugDisableWorker || _broken) return null;
    SendPort? commands;
    try {
      commands = await (_starting ??= _start());
    } catch (_) {
      commands = null;
    }
    if (commands == null) {
      _markBroken();
      return null;
    }
    final id = _nextRequestId++;
    final completer = Completer<Map<String, Object?>?>();
    _pending[id] = completer;
    try {
      commands.send(<String, Object?>{
        'type': 'process',
        'id': id,
        'args': args,
      });
    } catch (_) {
      _pending.remove(id);
      _markBroken();
      return null;
    }
    return completer.future;
  }

  Future<SendPort?> _start() async {
    final responses = ReceivePort();
    final handshake = Completer<SendPort?>();
    responses.listen((Object? message) {
      if (message is SendPort) {
        if (!handshake.isCompleted) handshake.complete(message);
        return;
      }
      if (message is Map) {
        final id = message['id'] as int?;
        final completer = id == null ? null : _pending.remove(id);
        if (completer == null || completer.isCompleted) return;
        final result = message['result'];
        completer.complete(
          message['ok'] == true && result is Map
              ? Map<String, Object?>.from(result)
              : null,
        );
        return;
      }
      // onError（List）或 onExit（null）：worker 已不可信，讓所有等待者
      // 退回 compute 路徑。
      if (!handshake.isCompleted) handshake.complete(null);
      _markBroken();
    });
    _responses = responses;
    try {
      _isolate = await Isolate.spawn(
        _workerMain,
        responses.sendPort,
        onError: responses.sendPort,
        onExit: responses.sendPort,
        debugName: 'reader-v2-content-transform',
      );
    } catch (_) {
      responses.close();
      _responses = null;
      return null;
    }
    final commands = await handshake.future;
    if (commands == null) return null;
    // 字典訊息先於任何 process 訊息送出（同一 port 依序送達），worker 收到
    // 第一章之前必已完成初始化。
    final dictionaryData = await dictionaryDataLoader();
    if (dictionaryData != null && dictionaryData.length == 4) {
      commands.send(<String, Object?>{'type': 'dict', 'data': dictionaryData});
    }
    return commands;
  }

  void _markBroken() {
    _broken = true;
    final waiters = _pending.values.toList(growable: false);
    _pending.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete(null);
    }
    _responses?.close();
    _responses = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  /// 測試鉤子：關掉現有 worker 並重設狀態，讓下一次 process 重新 spawn。
  @visibleForTesting
  void debugReset() {
    _markBroken();
    _broken = false;
    _starting = null;
  }

  static void _workerMain(SendPort replyPort) {
    final commands = ReceivePort();
    replyPort.send(commands.sendPort);
    commands.listen((Object? message) {
      if (message is! Map) return;
      switch (message['type']) {
        case 'dict':
          final data = message['data'];
          if (data is List) {
            ChineseUtils.initializeFromDictionaryData(data.cast<String>());
          }
        case 'process':
          final id = message['id'] as int?;
          final rawArgs = message['args'];
          if (id == null || rawArgs is! Map) return;
          try {
            final args = Map<String, Object?>.from(rawArgs);
            final result = ReaderV2ContentTransformer._processInBackground(
              args,
            );
            final convertType = args['chineseConvertType'] as int? ?? 0;
            if (convertType != 0) {
              const converter = ChineseTextConverter();
              result['displayTitle'] = converter.convert(
                result['displayTitle'] as String? ?? '',
                convertType: convertType,
              );
              result['content'] = converter.convert(
                result['content'] as String? ?? '',
                convertType: convertType,
              );
            }
            replyPort.send(<String, Object?>{
              'id': id,
              'ok': true,
              'result': result,
            });
          } catch (e) {
            replyPort.send(<String, Object?>{
              'id': id,
              'ok': false,
              'error': '$e',
            });
          }
      }
    });
  }
}
