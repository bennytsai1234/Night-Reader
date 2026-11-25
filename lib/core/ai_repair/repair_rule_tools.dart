import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/isolate.dart';
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/ai_repair/ai_repair_secrets.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/engine/web_book/book_info_parser.dart';
import 'package:night_reader/core/engine/web_book/book_list_parser.dart';
import 'package:night_reader/core/engine/web_book/chapter_list_parser.dart';
import 'package:night_reader/core/engine/web_book/content_parser.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/network/request_log.dart';
import 'package:night_reader/core/source/chapter_content_kind.dart';

/// AI 修復的「解析」與「跑程式」（ADR 0054）：在書源 worker 裡跑，規則 JS
/// 和書源一樣執行（可以用 `java.*`，要等的請求照常送）。
///
/// 解析：用 [source] 的規則、夜讀的解析程式把已經抓到的一頁 [body]（網址
/// [url]）當成 [stage]（`search`、`explore`、`info`、`toc`、`content`）
/// 解析，不重抓那一頁。傳回給 AI 的一段：幾筆、前 [_shownItems] 筆的每個
/// 欄位；正文給字數、類型與開頭。[secrets] 在截短前遮掉（ADR 0054）：截在
/// 一段秘密中間時，留下的半段認不出來。
Future<String> parseRepairPage(
  BookSource source, {
  required String stage,
  required String body,
  required String url,
  required Duration timeout,
  CancelToken? cancelToken,
  Set<String> secrets = const {},
  @visibleForTesting Future<DriftIsolate>? database,
}) => _inWorker(
  'RepairParse',
  _parseTask(source.toJson(), stage, body, url, secrets),
  timeout: timeout,
  cancelToken: cancelToken,
  database: database,
);

/// 跑程式：在 [source] 的規則 JS 環境跑 [code]，`page(頁碼)` 傳回 [pages]
/// 裡那一頁的原文。傳回值寫成文字（不是字串的轉成 JSON），最多
/// [_jsResultLength] 字；出錯時是錯誤訊息。程式送出的請求接在後面：實際送出
/// 的標頭與回應的開頭（2026-11-13 酷匠阅读的 AI 兩次把標頭包在 `headers`
/// 裡傳給 `java.connect`，看不到送出了什麼，以為整套介面失效）。
///
/// 請求一邊跑一邊交回來（[RequestLog.live]）：規則 JS 同步等網路、超過時間
/// 時，已經送出的請求和網站回了什麼照樣附上（2026-11-14 Codex 審查用本機
/// 伺服器重現：超時就只剩「超過時間，沒做完」）。
///
/// 傳回值與請求在截短前先遮掉 [secrets]（同 [parseRepairPage]）。
Future<String> runRepairJs(
  BookSource source, {
  required String code,
  required Map<int, String> pages,
  required Duration timeout,
  CancelToken? cancelToken,
  Set<String> secrets = const {},
  @visibleForTesting Future<DriftIsolate>? database,
}) async {
  // 只留要附上的那麼多字：送了很多請求的程式不在這裡越積越多。
  final sent = StringBuffer();
  var cut = false;
  final result = await _inWorker(
    'RepairJs',
    _jsTask(source.toJson(), code, pages, secrets),
    timeout: timeout,
    cancelToken: cancelToken,
    database: database,
    onProgress: (entry) {
      if (entry is! LoggedRequestLine || cut) return;
      final logged = redactAiRepairSecrets(entry.line, secrets);
      final line = sent.isEmpty ? logged : '\n$logged';
      final room = _jsRequestsLength - sent.length;
      cut = line.length > room;
      sent.write(cut ? line.substring(0, room) : line);
    },
  );
  final note = callsAjaxWithSecondArgument(code)
      ? '\n# $aiRepairAjaxSecondArgument'
      : '';
  if (sent.isEmpty) return '$result$note';
  return '$result$note\n# 這段程式送出的請求\n$sent${cut ? '…（後面省略）' : ''}';
}

/// 跑程式的結果後面附的一句：程式給 `java.ajax` 傳了第二個參數。同 Legado，
/// `java.ajax` 只收網址一個參數，第二個參數沒有送出；AI 看不到時會以為網站
/// 不認它給的標頭（酷匠阅读把標頭當第二個參數，判成網站要登入）。
const String aiRepairAjaxSecondArgument =
    'java.ajax 只收網址一個參數，這段程式給的第二個參數沒有送出：方法、內文、'
    '標頭寫在網址後面（網址,{"headers":{"名稱":"值"}}），或改用 '
    'java.get(網址, 標頭物件)、java.connect(網址, 標頭物件)';

/// [code] 裡有沒有呼叫 `java.ajax(…)` 時傳了不只一個參數：從括號後面往下
/// 走，跳過字串與巢狀的括號，同一層先碰到逗號就是。
@visibleForTesting
bool callsAjaxWithSecondArgument(String code) {
  for (final match in _ajaxCall.allMatches(code)) {
    var depth = 0;
    String? quote;
    for (var i = match.end; i < code.length; i++) {
      final char = code[i];
      if (quote != null) {
        if (char == r'\') {
          i++;
        } else if (char == quote) {
          quote = null;
        }
        continue;
      }
      if (char == '"' || char == "'" || char == '`') {
        quote = char;
      } else if (char == '(' || char == '[' || char == '{') {
        depth++;
      } else if (char == ')' || char == ']' || char == '}') {
        if (depth == 0) break;
        depth--;
      } else if (char == ',' && depth == 0) {
        return true;
      }
    }
  }
  return false;
}

final RegExp _ajaxCall = RegExp(r'\bjava\.ajax\s*\(');

/// [onProgress] 收 [task] 一邊跑一邊交回的紀錄；傳回之後（含超過時間）到的
/// 不收。
Future<String> _inWorker(
  String name,
  Future<String> Function(CancelToken) task, {
  required Duration timeout,
  CancelToken? cancelToken,
  Future<DriftIsolate>? database,
  void Function(Object entry)? onProgress,
}) async {
  final SourceWorker worker;
  try {
    worker = await SourceWorker.spawn(
      debugName: name,
      withDictionaries: false,
      database: database,
      cancelToken: cancelToken,
    );
  } catch (error) {
    if (cancelToken?.isCancelled ?? false) return '已停止';
    return '做不了：$error';
  }
  try {
    if (cancelToken?.isCancelled ?? false) return '已停止';
    unawaited(
      cancelToken?.whenCancel.then((_) => worker.kill(StateError('已停止'))),
    );
    return await worker
        .run(task, cancelToken: cancelToken, onProgress: onProgress)
        .timeout(timeout, onTimeout: () => '超過時間，沒做完');
  } catch (error) {
    return '出錯：$error';
  } finally {
    worker.kill(StateError('$name 已結束'));
  }
}

/// 只捕捉資料（`CODING_STANDARDS.md` 背景執行）。
Future<String> Function(CancelToken) _parseTask(
  Map<String, dynamic> sourceJson,
  String stage,
  String body,
  String url,
  Set<String> secrets,
) => (_) async {
  final source = BookSource.fromJson(sourceJson);
  String clip(String text, int length) =>
      _clip(redactAiRepairSecrets(text, secrets), length);
  try {
    return switch (stage) {
      'search' || 'explore' => await _books(source, stage, body, url, clip),
      'info' => await _info(source, body, url, clip),
      'toc' => await _toc(source, body, url),
      'content' => await _content(source, body, url, clip),
      _ => '不認得的段：$stage（要 search、explore、info、toc 或 content）',
    };
  } catch (error) {
    return '解析出錯：$error';
  }
};

/// 截短一段要給 AI 看的值（先遮秘密再截，[_clip]）。
typedef _Clip = String Function(String text, int length);

Future<String> _books(
  BookSource source,
  String stage,
  String body,
  String url,
  _Clip clip,
) async {
  final books = await BookListParser.parse(
    source: source,
    body: body,
    baseUrl: url,
    isSearch: stage == 'search',
  );
  return [
    '解析成${stage == 'search' ? '搜尋' : '發現'}頁：${books.length} 本',
    for (final (i, book) in books.take(_shownItems).indexed)
      '${i + 1}. ${_fields({'書名': book.name, '作者': book.author, '分類': book.kind, '最新章節': book.latestChapterTitle, '簡介': book.intro, '封面': book.coverUrl, '網址': book.bookUrl, '目錄': book.tocUrl}, clip)}',
  ].join('\n');
}

Future<String> _info(
  BookSource source,
  String body,
  String url,
  _Clip clip,
) async {
  final book = await BookInfoParser.parse(
    source: source,
    book: Book(bookUrl: url, origin: source.bookSourceUrl),
    body: body,
    baseUrl: url,
  );
  return '解析成詳情頁：${_fields({'書名': book.name, '作者': book.author, '分類': book.kind, '最新章節': book.latestChapterTitle, '簡介': book.intro, '封面': book.coverUrl, '目錄': book.tocUrl}, clip)}';
}

Future<String> _toc(BookSource source, String body, String url) async {
  final result = await ChapterListParser.parse(
    source: source,
    book: Book(bookUrl: url, tocUrl: url, origin: source.bookSourceUrl),
    body: body,
    baseUrl: url,
  );
  final chapters = result.chapters;
  return [
    '解析成目錄頁：${chapters.length} 章',
    for (final (i, chapter) in chapters.take(_shownItems).indexed)
      '${i + 1}. ${chapter.title} → ${chapter.url}',
    if (chapters.length > _shownItems)
      '末章：${chapters.last.title} → ${chapters.last.url}',
    if (result.nextUrls.isNotEmpty) '下一頁：${result.nextUrls.join('、')}',
    if (_usesBook(source.ruleToc?.toJson())) _noBook,
  ].join('\n');
}

/// 規則用到書的變數（`book.name`、`{{book.…}}` 這類）。
bool _usesBook(Map<String, dynamic>? rule) =>
    rule != null &&
    rule.values.any((value) => value is String && value.contains('book.'));

/// 解析只拿一頁、沒有書：規則用到書的變數時寫明，不然 AI 看到 0 章會以為規則
/// 錯了（2026-11-12 涨姿势的章名是 `{{book.name}}`，解析成 0 章，AI 改了兩輪
/// 規則才想到）。
const String _noBook =
    '（規則用到 book 的變數：解析只拿這一頁，沒有書，book.name 這類都是空的，'
    '章名空的章節會被丟掉；要照真的書跑用 test）';

Future<String> _content(
  BookSource source,
  String body,
  String url,
  _Clip clip,
) async {
  final result = await ContentParser.parse(
    source: source,
    chapter: BookChapter(title: '第一章', url: url, bookUrl: url),
    body: body,
    baseUrl: url,
  );
  final content = result.content;
  final kind = switch (ChapterContentKind.of(content)) {
    ChapterContentKind.text => '成段文字',
    ChapterContentKind.images => '圖片（漫畫）',
    ChapterContentKind.audio => '音訊網址',
    ChapterContentKind.unclear => '看不出來',
  };
  return [
    '解析成正文頁：${content.length} 字，看起來是$kind',
    clip(content, 300),
    if (result.nextUrls.isNotEmpty) '下一頁：${result.nextUrls.join('、')}',
    if (_usesBook(source.ruleContent?.toJson())) _noBook,
  ].join('\n');
}

/// 有值的欄位，`名稱：值` 用「｜」接起來；太長的值只留開頭。
String _fields(Map<String, String?> fields, _Clip clip) => [
  for (final MapEntry(:key, :value) in fields.entries)
    if (value != null && value.trim().isNotEmpty) '$key：${clip(value, 80)}',
].join('｜');

String _clip(String text, int length) {
  final line = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return line.length <= length ? line : '${line.substring(0, length)}…';
}

const int _shownItems = 5;

Future<String> Function(CancelToken) _jsTask(
  Map<String, dynamic> sourceJson,
  String code,
  Map<int, String> pages,
  Set<String> secrets,
) => (_) async {
  final source = BookSource.fromJson(sourceJson);
  final prelude =
      'var __nrPages = ${jsonEncode({for (final MapEntry(:key, :value) in pages.entries) '$key': value})};'
      'function page(n) { return __nrPages[String(n)]; }\n';
  final requests = RequestLog(
    responsePreview: RequestLog.diagnosisPreview,
    sentHeaders: true,
    live: true,
    secrets: secrets,
  );
  return requests.run(() async {
    try {
      final value = AnalyzeRule(source: source).evalJS(prelude + code, null);
      final text = redactAiRepairSecrets(switch (value) {
        null => 'null',
        final String string => string,
        _ => _encode(value),
      }, secrets);
      return text.length <= _jsResultLength
          ? '傳回：$text'
          : '傳回（共 ${text.length} 字，只給前 $_jsResultLength 字）：'
                '${text.substring(0, _jsResultLength)}';
    } catch (error) {
      return '出錯：$error';
    }
  });
};

/// 程式送出的請求最多附幾個字。
const int _jsRequestsLength = 6000;

String _encode(Object value) {
  try {
    return jsonEncode(value);
  } catch (_) {
    return '$value';
  }
}

const int _jsResultLength = 10000;
