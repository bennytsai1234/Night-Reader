import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/isolate.dart';
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/network/request_log.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/chapter_content_kind.dart';
import 'package:night_reader/core/services/source_debug_service.dart';

/// 一次試抓：照書源除錯從搜尋一路抓到正文（[SourceDebugService]），記下除錯
/// 紀錄與每個請求、網站回了什麼（每個回應留開頭 [responsePreview] 字），給
/// AI 看網頁現在長怎樣（ADR 0054）。
class SourceProbeReport {
  const SourceProbeReport({
    required this.logs,
    required this.requests,
    this.pages = const [],
    this.timedOut = false,
    this.contentUsable,
  });

  /// 除錯紀錄，`(狀態, 訊息)`；狀態同 [DebugLog.state]。
  final List<(int, String)> logs;

  /// 請求與網站的回應，照送出的順序（[RequestLog.lines]）。
  final List<String> requests;

  /// 同 [requests]，但每個回應是整頁原文（[RequestLog.pages]）：只寫進 AI
  /// 修復的完整紀錄，不送給 AI。
  final List<LoggedPage> pages;

  /// 不帶整頁原文的同一份：寫進完整紀錄之後留著給 AI 的只要這份。
  SourceProbeReport get withoutPages => SourceProbeReport(
    logs: logs,
    requests: requests,
    timedOut: timedOut,
    contentUsable: contentUsable,
  );

  /// 整段試抓超過時間被停下。
  final bool timedOut;

  /// 每個回應記的字數。
  static const int responsePreview = 6000;

  /// 送給 AI 的請求與回應最多幾個字；超過的後半段截掉。
  static const int requestBudget = 30000;

  /// 抓到的正文照書源校驗的判斷算不算抓到了（[sourceContentUsable]）：
  /// 只有一行提示、只有佔位圖的不算。沒走到正文是 null。
  final bool? contentUsable;

  /// 一路抓到正文了，而且照書源校驗的判斷算抓到了（[contentUsable]）。
  bool get succeeded =>
      !timedOut &&
      logs.any((log) => log.$1 == 1000) &&
      !logs.any((log) => log.$1 == -1) &&
      contentUsable == true;

  /// 抓到的正文有幾個字；沒走到正文是 null。
  int? get contentLength {
    for (final (_, message) in logs.reversed) {
      final length = RegExp(r'內容長度: (\d+)').firstMatch(message)?.group(1);
      if (length != null) return int.parse(length);
    }
    return null;
  }

  /// 抓到了哪幾段，例如「搜尋、詳情、目錄、正文」。
  String get stagesReached {
    const names = {10: '搜尋', 20: '詳情', 30: '目錄', 40: '正文'};
    final reached = {for (final (state, _) in logs) ?names[state]};
    return reached.join('、');
  }

  /// 回了幾頁網頁。
  int get pageCount => requests.where((line) => line.startsWith('  ← ')).length;

  /// 一句結果：抓到的正文多長，或停在哪裡。
  String get summary {
    if (timedOut) return '試抓超過時間';
    for (final (state, message) in logs.reversed) {
      if (state == -1) return _clean(message);
    }
    if (contentLength case final length?) {
      return contentUsable == false
          ? '正文 $length 字，書源校驗不算抓到（去掉圖片與網址後字太少，或沒有圖、網址）'
          : '正文 $length 字';
    }
    return '沒有抓到正文';
  }

  /// 給 AI 看的全文：除錯紀錄，與截到 [requestBudget] 字的請求與回應。
  String get fullText {
    final buffer = StringBuffer()..writeln('## 除錯紀錄');
    for (final (_, message) in logs) {
      buffer.writeln(message);
    }
    if (timedOut) buffer.writeln('（試抓超過時間，停在這裡）');
    buffer
      ..writeln()
      ..writeln('## 請求與網站的回應（網頁拿掉 <head>、程式與樣式，每個只留開頭 $responsePreview 字）');
    var used = 0;
    for (final (i, line) in requests.indexed) {
      if (used + line.length > requestBudget) {
        buffer.writeln(
          '（後面還有 ${requests.length - i} 行請求與回應沒列出：共 '
          '${requests.length} 行，這裡給前 $i 行；每個回應的整頁都有頁碼，用 read 讀）',
        );
        break;
      }
      buffer.writeln(line);
      used += line.length;
    }
    return buffer.toString().trimRight();
  }

  static String _clean(String message) =>
      message.replaceFirst(RegExp(r'^[\s❌︽≡]+'), '').trim();

  Map<String, Object?> toMap() => {
    'logs': [
      for (final (state, message) in logs) [state, message],
    ],
    'requests': requests,
    'pages': [for (final page in pages) loggedPageToJson(page)],
    'timedOut': timedOut,
    'contentUsable': contentUsable,
  };

  factory SourceProbeReport.fromMap(Map<Object?, Object?> map) =>
      SourceProbeReport(
        logs: [
          for (final entry in map['logs']! as List)
            ((entry as List)[0] as int, entry[1] as String),
        ],
        requests: List<String>.from(map['requests']! as List),
        pages: [
          for (final page in map['pages'] as List? ?? const [])
            loggedPageFromJson(page),
        ],
        timedOut: map['timedOut'] as bool? ?? false,
        contentUsable: map['contentUsable'] as bool?,
      );
}

/// 開一個書源 worker 試抓 [source]（同書源校驗，ADR 0033）：用 [keyword]
/// 搜尋，從第一本書一路抓到第一章正文。[keyword] 照書源除錯的寫法也可以
/// 從中間開始：詳情頁網址、`++目錄頁網址`、`--正文頁網址`（[probeStart]）。到了 [timeout] 還沒抓完就結束
/// worker，傳回 [SourceProbeReport.timedOut]；[cancelToken] 取消時也是。
Future<SourceProbeReport> probeSource(
  BookSource source, {
  required String keyword,
  required Duration timeout,
  CancelToken? cancelToken,
  @visibleForTesting Future<DriftIsolate>? database,
}) async {
  final SourceWorker worker;
  try {
    worker = await SourceWorker.spawn(
      debugName: 'SourceProbe',
      withDictionaries: false,
      database: database,
    );
  } catch (error, stack) {
    AppLog.e('試抓的 worker 開不起來: $error', error: error, stackTrace: stack);
    return SourceProbeReport(logs: [(-1, '試抓開不起來：$error')], requests: const []);
  }
  final completer = Completer<SourceProbeReport>();
  void finish(SourceProbeReport report) {
    if (completer.isCompleted) return;
    worker.kill(StateError('試抓已結束'));
    completer.complete(report);
  }

  const stopped = SourceProbeReport(logs: [], requests: [], timedOut: true);
  final timer = Timer(timeout, () => finish(stopped));
  unawaited(cancelToken?.whenCancel.then((_) => finish(stopped)));
  unawaited(
    worker
        .run(_probeTask(source.toJson(), keyword))
        .then(
          (map) => finish(SourceProbeReport.fromMap(map)),
          onError: (Object error, StackTrace stack) {
            if (completer.isCompleted) return;
            finish(
              SourceProbeReport(
                logs: [(-1, '試抓失敗：$error')],
                requests: const [],
              ),
            );
          },
        ),
  );
  final report = await completer.future;
  timer.cancel();
  return report;
}

/// 在 worker 裡跑的試抓；只捕捉書源與關鍵字的資料（`CODING_STANDARDS.md`）。
Future<Map<String, Object?>> Function(CancelToken) _probeTask(
  Map<String, dynamic> sourceJson,
  String keyword,
) => (_) async {
  final debug = SourceDebugService();
  final logs = <(int, String)>[];
  final subscription = debug.logStream.listen(
    (log) => logs.add((log.state, log.message)),
  );
  final requests = RequestLog(
    responsePreview: SourceProbeReport.responsePreview,
    digestPages: true,
    keepPages: true,
  );
  try {
    await requests.run(
      () => debug.startDebug(BookSource.fromJson(sourceJson), keyword),
    );
    // 紀錄經過 broadcast stream，讓最後幾筆送到。
    await Future<void>.delayed(Duration.zero);
  } finally {
    await subscription.cancel();
  }
  final content = debug.lastContent;
  return SourceProbeReport(
    logs: logs,
    requests: requests.lines,
    pages: requests.pages,
    contentUsable: content == null
        ? null
        : sourceContentUsable(content.source, content.book, content.content),
  ).toMap();
};

/// AI 看的一頁：給 AI 的 [lines]（請求與精簡過的回應）與一筆對一筆、帶整頁
/// 原文的 [pages]（[RequestLog.pages]）。
typedef AiPage = ({List<String> lines, List<LoggedPage> pages});

/// AI 要看的一頁（ADR 0054）：照書源的標頭與 Cookie 抓 [url]，傳回請求與網站
/// 的回應（精簡過的網頁，最多 [pageLength] 字），與整頁原文。[url] 照書源網址規則的寫法
/// 解析：可以接 `,{"method":"POST","body":…}`，`{{key}}` 是 [keyword]，所以
/// 拿書源的搜尋網址來看，看到的就是書源搜尋實際拿到的那一頁。
Future<AiPage> fetchPageForAi(
  BookSource source,
  String url, {
  required String keyword,
  required Duration timeout,
  CancelToken? cancelToken,
  int pageLength = 12000,
}) async {
  final SourceWorker worker;
  try {
    worker = await SourceWorker.spawn(
      debugName: 'SourceFetch',
      withDictionaries: false,
    );
  } catch (error) {
    return (lines: ['抓不了：$error'], pages: const <LoggedPage>[]);
  }
  try {
    if (cancelToken?.isCancelled ?? false) {
      return (lines: const ['已停止'], pages: const <LoggedPage>[]);
    }
    unawaited(
      cancelToken?.whenCancel.then((_) => worker.kill(StateError('抓網頁已停止'))),
    );
    final map = await worker
        .run(
          _fetchTask(source.toJson(), url, keyword, pageLength),
          cancelToken: cancelToken,
        )
        .timeout(
          timeout,
          onTimeout: () => const {
            'lines': ['（超過時間，沒抓到）'],
            'pages': <Object?>[],
          },
        );
    return (
      lines: List<String>.from(map['lines']! as List),
      pages: [
        for (final page in map['pages']! as List) loggedPageFromJson(page),
      ],
    );
  } catch (error) {
    return (lines: ['抓不了：$error'], pages: const <LoggedPage>[]);
  } finally {
    worker.kill(StateError('抓網頁已結束'));
  }
}

Future<Map<String, Object?>> Function(CancelToken) _fetchTask(
  Map<String, dynamic> sourceJson,
  String url,
  String keyword,
  int pageLength,
) => (_) async {
  final requests = RequestLog(
    responsePreview: pageLength,
    digestPages: true,
    keepPages: true,
  );
  try {
    await requests.run(
      () => AnalyzeUrl(
        url,
        key: keyword,
        page: 1,
        source: BookSource.fromJson(sourceJson),
        baseUrl: sourceJson['bookSourceUrl'] as String? ?? '',
      ).getStrResponse(),
    );
  } catch (error) {
    requests.lines.add('錯誤：$error');
    requests.pages.add((line: '錯誤：$error', body: null));
  }
  return {
    'lines': requests.lines,
    'pages': [for (final page in requests.pages) loggedPageToJson(page)],
  };
};

/// 搜尋結果跟關鍵字有沒有關係：用 [keyword] 與一個不可能有的詞各搜一次，
/// 不可能的詞也搜出書、而且前幾本和 [keyword] 的一模一樣，是 false——規則
/// 抓到的是頁面上固定的推薦書，不是搜尋結果（實測 AI 這樣「修好」過）。
/// 搜不到、出錯或逾時都當成有關係，交給書源校驗判斷。
Future<bool> searchFollowsKeyword(
  BookSource source, {
  required String keyword,
  required Duration timeout,
  CancelToken? cancelToken,
}) async {
  final service = BookSourceService();
  try {
    final real = await service
        .searchBooks(source, keyword, cancelToken: cancelToken)
        .timeout(timeout);
    if (real.isEmpty) return true;
    final nonsense = await service
        .searchBooks(source, nonsenseKeyword, cancelToken: cancelToken)
        .timeout(timeout);
    String names(List<SearchBook> books) =>
        books.take(5).map((book) => book.name).join('|');
    return nonsense.isEmpty || names(real) != names(nonsense);
  } catch (error) {
    AppLog.d('搜尋與關鍵字的檢查沒做成: $error');
    return true;
  }
}

/// 不可能搜到書的詞。
const String nonsenseKeyword = '夜讀查無此書ㄅㄆㄇㄈ';

/// 試抓從哪一段開始時傳給 [probeSource] 的 keyword：`search` 用 [keyword]
/// 搜尋，`info`、`toc`、`content` 從 [url] 那一頁開始（書源除錯的寫法）。
/// 不認得的段或少了網址是 null。
String? probeStart(String from, {required String keyword, String? url}) {
  if (from == 'search') return keyword;
  if (url == null || url.trim().isEmpty) return null;
  return switch (from) {
    'info' => url,
    'toc' => '++$url',
    'content' => '--$url',
    _ => null,
  };
}
