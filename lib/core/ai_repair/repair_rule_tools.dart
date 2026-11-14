import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/isolate.dart';
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/engine/web_book/book_info_parser.dart';
import 'package:night_reader/core/engine/web_book/book_list_parser.dart';
import 'package:night_reader/core/engine/web_book/chapter_list_parser.dart';
import 'package:night_reader/core/engine/web_book/content_parser.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/network/request_log.dart';
import 'package:night_reader/core/services/chapter_content_kind.dart';

/// AI 修復的「解析」與「跑程式」（ADR 0054）：在書源 worker 裡跑，規則 JS
/// 和書源一樣執行（可以用 `java.*`，要等的請求照常送）。
///
/// 解析：用 [source] 的規則、夜讀的解析程式把已經抓到的一頁 [body]（網址
/// [url]）當成 [stage]（`search`、`explore`、`info`、`toc`、`content`）
/// 解析，不重抓那一頁。傳回給 AI 的一段：幾筆、前 [_shownItems] 筆的每個
/// 欄位；正文給字數、類型與開頭。
Future<String> parseRepairPage(
  BookSource source, {
  required String stage,
  required String body,
  required String url,
  required Duration timeout,
  CancelToken? cancelToken,
  @visibleForTesting Future<DriftIsolate>? database,
}) => _inWorker(
  'RepairParse',
  _parseTask(source.toJson(), stage, body, url),
  timeout: timeout,
  cancelToken: cancelToken,
  database: database,
);

/// 跑程式：在 [source] 的規則 JS 環境跑 [code]，`page(頁碼)` 傳回 [pages]
/// 裡那一頁的原文。傳回值寫成文字（不是字串的轉成 JSON），最多
/// [_jsResultLength] 字；出錯時是錯誤訊息。程式送出的請求接在後面：實際送出
/// 的標頭與回應的開頭（2026-11-13 酷匠阅读的 AI 兩次把標頭包在 `headers`
/// 裡傳給 `java.connect`，看不到送出了什麼，以為整套介面失效）。
Future<String> runRepairJs(
  BookSource source, {
  required String code,
  required Map<int, String> pages,
  required Duration timeout,
  CancelToken? cancelToken,
  @visibleForTesting Future<DriftIsolate>? database,
}) => _inWorker(
  'RepairJs',
  _jsTask(source.toJson(), code, pages),
  timeout: timeout,
  cancelToken: cancelToken,
  database: database,
);

Future<String> _inWorker(
  String name,
  Future<String> Function(CancelToken) task, {
  required Duration timeout,
  CancelToken? cancelToken,
  Future<DriftIsolate>? database,
}) async {
  final SourceWorker worker;
  try {
    worker = await SourceWorker.spawn(
      debugName: name,
      withDictionaries: false,
      database: database,
    );
  } catch (error) {
    return '做不了：$error';
  }
  try {
    if (cancelToken?.isCancelled ?? false) return '已停止';
    unawaited(
      cancelToken?.whenCancel.then((_) => worker.kill(StateError('已停止'))),
    );
    return await worker
        .run(task, cancelToken: cancelToken)
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
) => (_) async {
  final source = BookSource.fromJson(sourceJson);
  try {
    return switch (stage) {
      'search' || 'explore' => await _books(source, stage, body, url),
      'info' => await _info(source, body, url),
      'toc' => await _toc(source, body, url),
      'content' => await _content(source, body, url),
      _ => '不認得的段：$stage（要 search、explore、info、toc 或 content）',
    };
  } catch (error) {
    return '解析出錯：$error';
  }
};

Future<String> _books(
  BookSource source,
  String stage,
  String body,
  String url,
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
      '${i + 1}. ${_fields({'書名': book.name, '作者': book.author, '分類': book.kind, '最新章節': book.latestChapterTitle, '簡介': book.intro, '封面': book.coverUrl, '網址': book.bookUrl, '目錄': book.tocUrl})}',
  ].join('\n');
}

Future<String> _info(BookSource source, String body, String url) async {
  final book = await BookInfoParser.parse(
    source: source,
    book: Book(bookUrl: url, origin: source.bookSourceUrl),
    body: body,
    baseUrl: url,
  );
  return '解析成詳情頁：${_fields({'書名': book.name, '作者': book.author, '分類': book.kind, '最新章節': book.latestChapterTitle, '簡介': book.intro, '封面': book.coverUrl, '目錄': book.tocUrl})}';
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

Future<String> _content(BookSource source, String body, String url) async {
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
    _clip(content, 300),
    if (result.nextUrls.isNotEmpty) '下一頁：${result.nextUrls.join('、')}',
    if (_usesBook(source.ruleContent?.toJson())) _noBook,
  ].join('\n');
}

/// 有值的欄位，`名稱：值` 用「｜」接起來；太長的值只留開頭。
String _fields(Map<String, String?> fields) => [
  for (final MapEntry(:key, :value) in fields.entries)
    if (value != null && value.trim().isNotEmpty) '$key：${_clip(value, 80)}',
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
) => (_) async {
  final source = BookSource.fromJson(sourceJson);
  final prelude =
      'var __nrPages = ${jsonEncode({for (final MapEntry(:key, :value) in pages.entries) '$key': value})};'
      'function page(n) { return __nrPages[String(n)]; }\n';
  final requests = RequestLog(
    responsePreview: RequestLog.diagnosisPreview,
    sentHeaders: true,
  );
  final result = await requests.run(() async {
    try {
      final value = AnalyzeRule(source: source).evalJS(prelude + code, null);
      final text = switch (value) {
        null => 'null',
        final String string => string,
        _ => _encode(value),
      };
      return text.length <= _jsResultLength
          ? '傳回：$text'
          : '傳回（共 ${text.length} 字，只給前 $_jsResultLength 字）：'
                '${text.substring(0, _jsResultLength)}';
    } catch (error) {
      return '出錯：$error';
    }
  });
  if (requests.lines.isEmpty) return result;
  var sent = requests.lines.join('\n');
  if (sent.length > _jsRequestsLength) {
    sent = '${sent.substring(0, _jsRequestsLength)}…（後面省略）';
  }
  return '$result\n# 這段程式送出的請求\n$sent';
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
