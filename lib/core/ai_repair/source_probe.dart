import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/isolate.dart';
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/network/error_text.dart';
import 'package:night_reader/core/network/request_log.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/source/chapter_content_kind.dart';
import 'package:night_reader/core/source/content_next_page.dart';
import 'package:night_reader/core/source/source_debug_service.dart';
import 'package:night_reader/core/utils/network_utils.dart';
import 'package:night_reader/core/source/source_progress.dart';

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
    this.unjoinedNextPage,
    this.contentAmount,
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
    unjoinedNextPage: unjoinedNextPage,
    contentAmount: contentAmount,
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

  /// 抓到的正文只抓了第一頁時，同一章下一頁的網址；沒有、或沒走到正文是
  /// null。和書源校驗同一個判斷（[chapterCutAtFirstPage]）。
  final String? unjoinedNextPage;

  /// 漫畫、有聲的正文抓到多少（「54 張圖」「3 個音訊網址」，照書源校驗判斷
  /// 的類別）；小說或沒走到正文是 null，照字數寫（[contentLength]）。
  final String? contentAmount;

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
      final amount = contentAmount ?? '$length 字';
      return contentUsable == false
          ? '正文 $amount，書源校驗不算抓到（去掉圖片與網址後字太少，或沒有圖、網址）'
          : '正文 $amount';
    }
    return '沒有抓到正文';
  }

  /// 給 AI 看的全文：除錯紀錄，與截到 [requestBudget] 字的請求與回應。
  String get fullText => _text(excerpts: true);

  /// 開場用的：同 [fullText]，但每個回應只寫頁碼、網址與大小，不附網頁開頭，
  /// 內容讓 AI 用讀頁、找字自己看（`agent-harness` 技能：開場只給位置）。
  /// 2026-11-12 比過：话本、涨姿势兩種都修好，要付全價的送出量少一半。
  String get indexText => _text(excerpts: false);

  String _text({required bool excerpts}) {
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
      final shown = excerpts ? line : _withoutExcerpt(line);
      buffer.writeln(shown);
      used += shown.length;
    }
    return buffer.toString().trimRight();
  }

  static String _clean(String message) =>
      message.replaceFirst(RegExp(r'^[\s❌︽≡]+'), '').trim();
}

/// 開一個書源 worker 試抓 [source]（同書源校驗，ADR 0033）：用 [keyword]
/// 搜尋，從第一本書一路抓到第一章正文。[keyword] 照書源除錯的寫法也可以
/// 從中間開始：`::發現頁網址`、詳情頁網址、`++目錄頁網址`、`--正文頁網址`（[probeStart]）。到了 [timeout] 還沒抓完就結束
/// worker，傳回 [SourceProbeReport.timedOut]；[cancelToken] 取消時也是。
Future<SourceProbeReport> probeSource(
  BookSource source, {
  required String keyword,
  required Duration timeout,
  CancelToken? cancelToken,
  Set<String> secrets = const {},
  @visibleForTesting Future<DriftIsolate>? database,
  @visibleForTesting Duration workerGrace = _workerGrace,
}) async {
  final SourceWorker worker;
  try {
    worker = await SourceWorker.spawn(
      debugName: 'SourceProbe',
      withDictionaries: false,
      database: database,
      cancelToken: cancelToken,
    );
  } catch (error, stack) {
    // 等 worker 名額時被停下的不是開不起來。
    if (cancelToken?.isCancelled ?? false) {
      return const SourceProbeReport(logs: [], requests: [], timedOut: true);
    }
    AppLog.e('試抓的 worker 開不起來: $error', error: error, stackTrace: stack);
    return SourceProbeReport(logs: [(-1, '試抓開不起來：$error')], requests: const []);
  }
  final completer = Completer<SourceProbeReport>();
  void finish(SourceProbeReport report) {
    if (completer.isCompleted) return;
    worker.kill(StateError('試抓已結束'));
    completer.complete(report);
  }

  // 除錯紀錄與請求一邊跑一邊交回來（[reportSourceProgress]），外層結束
  // worker 時交回已經走到的這些（2026-11-13 肉肉屋⑥試抓四次超過時間，每次
  // 紀錄都是空的，AI 不知道停在哪一步）。
  final logs = <(int, String)>[];
  final requests = <String>[];
  final pages = <LoggedPage>[];
  void collect(Object entry) {
    switch (entry) {
      case DebugLog(:final state, :final message):
        logs.add((state, message));
      case LoggedRequestLine(:final line, :final body):
        requests.add(line);
        pages.add((line: line, body: body));
    }
  }

  SourceProbeReport walked({
    required bool timedOut,
    (int, String)? failure,
    bool? contentUsable,
    String? unjoinedNextPage,
    String? contentAmount,
  }) => SourceProbeReport(
    logs: [...logs, ?failure],
    requests: [...requests],
    pages: [...pages],
    timedOut: timedOut,
    contentUsable: contentUsable,
    contentAmount: contentAmount,
    unjoinedNextPage: unjoinedNextPage,
  );

  // worker 自己到 [timeout] 就停；規則 JS 同步等網路時 worker 的計時器要等
  // 那個請求結束，外層多等一個請求的時限，還沒交回就結束它。
  final timer = Timer(
    timeout + workerGrace,
    () => finish(walked(timedOut: true)),
  );
  unawaited(
    cancelToken?.whenCancel.then((_) => finish(walked(timedOut: true))),
  );
  unawaited(
    worker
        .run(
          _probeTask(source.toJson(), keyword, timeout, secrets),
          onProgress: collect,
        )
        .then(
          (outcome) => finish(
            walked(
              timedOut: outcome.timedOut,
              contentUsable: outcome.contentUsable,
              unjoinedNextPage: outcome.unjoinedNextPage,
              contentAmount: outcome.contentAmount,
            ),
          ),
          onError: (Object error, StackTrace stack) {
            if (completer.isCompleted) return;
            finish(walked(timedOut: false, failure: (-1, '試抓失敗：$error')));
          },
        ),
  );
  final report = await completer.future;
  timer.cancel();
  return report;
}

/// worker 到時限沒交回時，外層再多等多久才結束它：一個請求的時限（規則 JS
/// 同步等網路時，worker 的計時器要等那個請求結束才跑得到）。
const Duration _workerGrace = Duration(seconds: 16);

/// [_probeTask] 跑完交回的；紀錄在跑的途中已經交回（[probeSource]）。
typedef _ProbeOutcome = ({
  bool timedOut,
  bool? contentUsable,
  String? unjoinedNextPage,
  String? contentAmount,
});

/// 在 worker 裡跑的試抓；只捕捉書源與關鍵字的資料（`CODING_STANDARDS.md`）。
/// 除錯紀錄（[DebugLog]）與請求（[LoggedRequestLine]）一邊跑一邊交回；到
/// [timeout] 還沒抓完就停下。
Future<_ProbeOutcome> Function(CancelToken) _probeTask(
  Map<String, dynamic> sourceJson,
  String keyword,
  Duration timeout,
  Set<String> secrets,
) => (_) async {
  final debug = SourceDebugService();
  final progress = currentSourceProgress;
  final requests = RequestLog(
    responsePreview: SourceProbeReport.responsePreview,
    digestPages: true,
    keepPages: true,
    sentHeaders: true,
    live: true,
    secrets: secrets,
  );
  var timedOut = false;
  try {
    await requests
        .run(
          () => debug.startDebug(
            BookSource.fromJson(sourceJson),
            keyword,
            onLog: progress,
          ),
        )
        .timeout(timeout);
  } on TimeoutException {
    timedOut = true;
  }
  final content = timedOut ? null : debug.lastContent;
  return (
    timedOut: timedOut,
    contentUsable: content == null
        ? null
        : sourceContentUsable(content.source, content.book, content.content),
    contentAmount: content == null
        ? null
        : contentAmountText(content.source, content.book, content.content),
    unjoinedNextPage: content == null
        ? null
        : chapterCutAtFirstPage(
            content.source,
            content.book,
            content.content,
            content.pages,
            toc: content.toc,
          ),
  );
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
  Set<String> secrets = const {},
  @visibleForTesting Future<DriftIsolate>? database,
}) async {
  final SourceWorker worker;
  try {
    worker = await SourceWorker.spawn(
      debugName: 'SourceFetch',
      withDictionaries: false,
      database: database,
      cancelToken: cancelToken,
    );
  } catch (error) {
    if (cancelToken?.isCancelled ?? false) {
      return (lines: const ['已停止'], pages: const <LoggedPage>[]);
    }
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
          _fetchTask(source.toJson(), url, keyword, pageLength, secrets),
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
  Set<String> secrets,
) => (_) async {
  final requests = RequestLog(
    responsePreview: pageLength,
    digestPages: true,
    keepPages: true,
    sentHeaders: true,
    secrets: secrets,
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
    requests.lines.add('錯誤：${errorText(error)}');
    requests.pages.add((line: '錯誤：${errorText(error)}', body: null));
  }
  return {
    'lines': requests.lines,
    'pages': [for (final page in requests.pages) loggedPageToJson(page)],
  };
};

/// 試抓從哪一段開始時傳給 [probeSource] 的 keyword：`search` 用 [keyword]
/// 搜尋，`explore`、`info`、`toc`、`content` 從 [url] 那一頁開始（書源除錯的
/// 寫法；發現頁照 exploreUrl 的寫法原樣交給除錯解析）。
/// [url] 是相對網址時照 [baseUrl]（書源網址）補成完整的：書源除錯同 Legado，
/// 不是 http 開頭的會當成搜尋關鍵字（2026-11-12 AI 給 `/551874.html` 從詳情頁
/// 試抓，結果拿它去搜尋）。不認得的段或少了網址是 null。
String? probeStart(
  String from, {
  required String keyword,
  String? url,
  String? baseUrl,
}) {
  if (from == 'search') return keyword;
  if (url == null || url.trim().isEmpty) return null;
  // 發現頁照 exploreUrl 的寫法（可以是相對網址、帶 {{page}}），由除錯照書源
  // 解析（同 Legado `Debug` 的 `::網址`）。
  if (from == 'explore') return '::${url.trim()}';
  final page = NetworkUtils.getAbsoluteURL(baseUrl, url);
  return switch (from) {
    'info' => page,
    'toc' => '++$page',
    'content' => '--$page',
    _ => null,
  };
}

/// 試抓從搜尋走進詳情時，搜尋結果第一本的書名、作者和詳情頁抓到的不一樣：
/// 寫成一句告訴 AI 的事實；一樣或沒走到詳情是 null。書名加作者是夜讀認一本
/// 書的依據（搜尋結果合併、換源、書籤）。2026-11-13 肉肉屋#3 的搜尋書名規則
/// 抓到每一列的「目录」連結，20 本都叫「目录」，詳情頁卻是「《救命！…》」。
String? searchInfoMismatch(SourceProbeReport probe) {
  String? searchName, searchAuthor, infoName, infoAuthor;
  var listed = false;
  for (final (_, message) in probe.logs) {
    if (message.startsWith('︽搜尋頁解析完成') || message.startsWith('︽發現頁解析完成')) {
      listed = true;
      continue;
    }
    if (listed && searchName == null) {
      final first = RegExp(r'^\s*\[0\] (.*) - (.*)$').firstMatch(message);
      if (first != null) {
        searchName = first.group(1)!.trim();
        searchAuthor = first.group(2)!.trim();
      }
    }
    final info = RegExp(r'^︽詳情頁解析完成: (.*)$').firstMatch(message);
    if (info != null) infoName = info.group(1)!.trim();
    final author = RegExp(r'^\s*作者: (.*), 目錄: ').firstMatch(message);
    if (author != null) infoAuthor = author.group(1)!.trim();
  }
  if (searchName == null || infoName == null) return null;
  final parts = [
    if (searchName != infoName) '書名搜尋是「$searchName」、詳情頁是「$infoName」',
    if (infoAuthor != null &&
        searchAuthor != '未知' &&
        searchAuthor != infoAuthor)
      '作者搜尋是「$searchAuthor」、詳情頁是「$infoAuthor」',
  ];
  return parts.isEmpty ? null : '搜尋結果第一本進了詳情頁，${parts.join('；')}';
}

/// 回應那一行只留到大小為止：「  ← 頁 2｜網址 200 text/html，41940 位元組，
/// 精簡後 15479 字」。
String _withoutExcerpt(String line) {
  if (!line.trimLeft().startsWith('←')) return line;
  final colon = line.indexOf('：', line.indexOf('←'));
  return colon < 0 ? line : '${line.substring(0, colon)}（內容沒放進開場）';
}

/// 漫畫、有聲的正文抓到多少，照書源校驗判斷的類別（[chapterKindShownBy]）：
/// 「54 張圖」「3 個音訊網址」；小說是 null（照字數寫）。
String? contentAmountText(BookSource source, Book book, String content) {
  final shape = ChapterContentShape.of(content);
  return switch (chapterKindShownBy(source, book, content)) {
    BookSourceKind.comic => '${shape.images} 張圖',
    BookSourceKind.audio => '${shape.urls} 個音訊網址',
    _ => null,
  };
}
