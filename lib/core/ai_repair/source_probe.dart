import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/isolate.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/network/request_log.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/chapter_content_kind.dart';
import 'package:night_reader/core/services/source_debug_service.dart';
import 'package:night_reader/core/utils/network_utils.dart';

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
    sentHeaders: true,
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
    sentHeaders: true,
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

/// 用網站自己發現頁上確實有的一本書搜一次的結果（[searchKnownTitle]）：
/// [limited] 是搜那本書時網站限流說的話（請求紀錄的「網站限流」），沒被擋
/// 是 null。
typedef KnownTitleSearch = ({
  String title,
  String from,
  bool found,
  String? limited,
});

/// 原本的關鍵字搜不到書時，從網站自己的發現頁拿第一本書的書名，用 [source]
/// 的搜尋規則搜它：搜不到，表示網站上有的書這個搜尋規則找不到（規則錯，或
/// 網站的搜尋本身不理關鍵字）；搜得到，表示規則與網站都正常。2026-11-13
/// 蜘蛛小說網的 AI 每次要花 5 到 10 輪自己做這個比對。在書源 worker 裡做、
/// 記下請求：開場已經搜了好幾次，限流的網站這次可能被擋，被擋的寫成限流，
/// 不寫成規則找不到。沒有發現頁、發現頁沒有書、出錯或逾時是 null。
Future<KnownTitleSearch?> searchKnownTitle(
  BookSource source, {
  required Duration timeout,
  CancelToken? cancelToken,
  @visibleForTesting Future<DriftIsolate>? database,
}) async {
  if ((source.searchUrl ?? '').trim().isEmpty) return null;
  final SourceWorker worker;
  try {
    worker = await SourceWorker.spawn(
      debugName: 'KnownTitle',
      withDictionaries: false,
      database: database,
    );
  } catch (error) {
    AppLog.d('用發現頁的書名搜尋開不起來: $error');
    return null;
  }
  try {
    if (cancelToken?.isCancelled ?? false) return null;
    unawaited(
      cancelToken?.whenCancel.then((_) => worker.kill(StateError('已停止'))),
    );
    final map = await worker
        .run(_knownTitleTask(source.toJson(), timeout))
        .timeout(timeout * 3, onTimeout: () => const {});
    final title = map['title'] as String?;
    if (title == null) return null;
    return (
      title: title,
      from: map['from'] as String? ?? '',
      found: map['found'] == true,
      limited: map['limited'] as String?,
    );
  } catch (error) {
    AppLog.d('用發現頁的書名搜尋沒做成: $error');
    return null;
  } finally {
    worker.kill(StateError('用發現頁的書名搜尋已結束'));
  }
}

/// 只捕捉資料（`CODING_STANDARDS.md` 背景執行）。
Future<Map<String, Object?>> Function(CancelToken) _knownTitleTask(
  Map<String, dynamic> sourceJson,
  Duration timeout,
) => (cancelToken) async {
  final source = BookSource.fromJson(sourceJson);
  final service = BookSourceService();
  final kinds = await service
      .exploreKinds(source.exploreUrl, source: source)
      .timeout(timeout);
  for (final kind in kinds) {
    final url = kind.url?.trim() ?? '';
    if (url.isEmpty) continue;
    final books = await service
        .exploreBooks(source, url, cancelToken: cancelToken)
        .timeout(timeout);
    final title = books.firstOrNull?.name.trim() ?? '';
    if (title.isEmpty) continue;
    final requests = RequestLog(
      responsePreview: SourceProbeReport.responsePreview,
    );
    final found = await requests.run(
      () => service
          .searchBooks(source, title, cancelToken: cancelToken)
          .timeout(timeout),
    );
    final limited = [
      for (final line in requests.lines)
        ?RegExp(r'網站限流：([^）]*)').firstMatch(line)?.group(1),
    ].firstOrNull;
    return {
      'title': title,
      'from': kind.title,
      'found': found.any((book) => book.name.trim() == title),
      'limited': limited,
    };
  }
  return const {};
};

/// 不可能搜到書的詞。
const String nonsenseKeyword = '夜讀查無此書ㄅㄆㄇㄈ';

/// 試抓從哪一段開始時傳給 [probeSource] 的 keyword：`search` 用 [keyword]
/// 搜尋，`info`、`toc`、`content` 從 [url] 那一頁開始（書源除錯的寫法）。
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
  final page = NetworkUtils.getAbsoluteURL(baseUrl, url);
  return switch (from) {
    'info' => page,
    'toc' => '++$page',
    'content' => '--$page',
    _ => null,
  };
}

/// 試抓到的正文頁有同一章的下一頁、試抓卻沒抓那一頁時，下一頁的網址；
/// 沒有是 null。2026-11-12 下書網的 AI 交出的規則只抓到每章的前半頁
/// （95393.html，後半在 95393_2.html），校驗照樣通過；11-13 另一次寫了
/// `nextContentUrl`，選擇器卻抓不到連結，同樣只有前半頁，所以看的是請求
/// 紀錄裡有沒有那一頁，不是規則有沒有寫。正文規則自己抓網頁（`java.ajax`
/// 這類）的不看。
String? unjoinedContentPage(SourceProbeReport probe, BookSource source) {
  final rule = source.ruleContent;
  if (_fetchesItself.hasMatch(rule?.content ?? '')) return null;
  String? chapterUrl;
  for (final (_, message) in probe.logs) {
    final url = RegExp(r'^\s*正文 URL: (\S+)').firstMatch(message)?.group(1);
    if (url != null) chapterUrl = url;
  }
  final chapter = chapterUrl == null ? null : Uri.tryParse(chapterUrl);
  if (chapter == null) return null;
  final body = [
    for (final page in probe.pages)
      if (page.body != null &&
          page.line.trimLeft().startsWith('← ${chapter.removeFragment()} '))
        page.body!,
  ].lastOrNull;
  if (body == null) return null;
  for (final link in html_parser.parse(body).querySelectorAll('a[href]')) {
    final href = link.attributes['href']!.trim();
    if (href.isEmpty || href.startsWith('javascript:')) continue;
    final Uri target;
    try {
      target = chapter.resolve(href);
    } on FormatException {
      continue;
    }
    if (isNextPageOfChapter(chapter, target)) {
      final next = '${target.removeFragment()}';
      final fetched = [
        ...probe.requests,
        for (final page in probe.pages) page.line,
      ].map(_requestedUrl).contains(next);
      return fetched ? null : next;
    }
  }
  return null;
}

/// 請求紀錄裡請求那一行（`GET` 不寫方法、其他寫在前面，轉址到的標「（轉址）」）
/// 送出的網址；回應那一行（`←` 開頭，內容裡可能正好有下一頁的連結）是 null。
String? _requestedUrl(String line) {
  final words = line.trim().split(' ');
  if (words.first.startsWith('←')) return null;
  final url = RegExp(r'^[A-Z]+$').hasMatch(words.first) && words.length > 1
      ? words[1]
      : words.first;
  return url.replaceAll('（轉址）', '');
}

final RegExp _fetchesItself = RegExp(
  r'java\.(ajax|ajaxAll|get|post|connect)\(',
);

/// [link] 是不是 [chapter] 這一章的下一頁：同一個網站，檔名是這一頁的接
/// `_2`、`-2` 這類（95393.html → 95393_2.html），或同一個路徑換了 page、p
/// 這類頁碼參數。下一章（95394.html）不算。
@visibleForTesting
bool isNextPageOfChapter(Uri chapter, Uri link) {
  if (link.host != chapter.host) return false;
  final parts = RegExp(r'^(.*?)(\.[A-Za-z0-9]+)?$').firstMatch(chapter.path)!;
  final stem = RegExp.escape(parts.group(1)!);
  final extension = RegExp.escape(parts.group(2) ?? '');
  if (RegExp('^$stem[_-]\\d+$extension\$').hasMatch(link.path)) return true;
  if (link.path != chapter.path) return false;
  for (final name in const ['page', 'p', 'pn', 'pg']) {
    final next = int.tryParse(link.queryParameters[name] ?? '');
    final current = int.tryParse(chapter.queryParameters[name] ?? '1') ?? 1;
    if (next != null && next > current) return true;
  }
  return false;
}

/// 回應那一行只留到大小為止：「  ← 頁 2｜網址 200 text/html，41940 位元組，
/// 精簡後 15479 字」。
String _withoutExcerpt(String line) {
  if (!line.trimLeft().startsWith('←')) return line;
  final colon = line.indexOf('：', line.indexOf('←'));
  return colon < 0 ? line : '${line.substring(0, colon)}（內容沒放進開場）';
}
