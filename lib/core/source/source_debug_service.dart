import 'dart:async';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

import 'book_source_service.dart';

import 'package:night_reader/core/exception/user_error.dart';
import 'package:night_reader/core/network/redirects.dart';
import 'package:night_reader/core/network/request_log.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/utils/html_formatter.dart';

class DebugLog {
  final int state; // 1: info, 10: search, 20: detail, 30: toc, 40: content, 1000: success, -1: error
  final String message;
  final DateTime time;

  DebugLog(this.state, this.message, this.time);

  String get formattedTime => DateFormat('[mm:ss.SSS]').format(time);
  @override
  String toString() => '$formattedTime $message';

  Map<String, dynamic> toJson() => {
    'state': state,
    'message': message,
    'time': time.millisecondsSinceEpoch,
    'formattedTime': formattedTime,
  };
}

class SourceDebugService {
  static final SourceDebugService _instance = SourceDebugService._internal();
  factory SourceDebugService() => _instance;
  SourceDebugService._internal();

  final _logController = StreamController<DebugLog>.broadcast();
  Stream<DebugLog> get logStream => _logController.stream;

  final BookSourceService _bookSourceService = BookSourceService();

  /// 目前這一輪除錯的代號；取消或開始新一輪時遞增。每一輪在自己的 Zone 裡
  /// 執行，取消後才回來的請求寫的日誌對不上代號，直接丟掉。
  int _runId = 0;
  bool _runFailed = false;
  static const Symbol _runKey = #sourceDebugRun;
  static const Symbol _onLogKey = #sourceDebugOnLog;

  void log(String msg, {int state = 1, bool isHtml = false}) {
    if (Zone.current[_runKey] != _runId) return;
    if (state == -1) _runFailed = true;

    var printMsg = msg;
    if (isHtml) {
      printMsg = HtmlFormatter.format(msg);
    }

    final debugLog = DebugLog(state, printMsg, DateTime.now());
    (Zone.current[_onLogKey] as void Function(DebugLog log)?)?.call(debugLog);
    _logController.add(debugLog);
  }

  void cancel() {
    _runId++;
  }

  /// 這一輪抓到的正文與它的書源、書；還沒抓到正文是 null。AI 修復的試抓
  /// 照它判斷抓到了沒、是不是只抓了第一頁，和書源校驗同一套
  /// （[sourceContentUsable]、`chapterCutAtFirstPage`）：[pages] 是只抓這一章
  /// 時的請求（在記回應的 [RequestLog] 裡才有），[toc] 是目錄上每一章的
  /// 網址（從正文頁開始的沒有目錄）。
  ({
    BookSource source,
    Book book,
    String content,
    List<LoggedPage> pages,
    List<String> toc,
  })?
  lastContent;

  /// 除錯 [source]。[onLog] 在每一筆紀錄寫下的當下收到它（[logStream] 的
  /// 聽眾要等這段同步的程式跑完才收到）：試抓在書源 worker 裡跑，規則 JS
  /// 同步等網路時也要把紀錄當下送出去。
  Future<void> startDebug(
    BookSource source,
    String key, {
    void Function(DebugLog log)? onLog,
  }) {
    final runId = ++_runId;
    _runFailed = false;
    lastContent = null;
    return runZoned(
      () => withSourceDebugLog(
        onRequest: (url) => log('  實際請求: $url'),
        onNote: log,
        body: () => _runDebug(source, key),
      ),
      zoneValues: {_runKey: runId, _onLogKey: onLog},
    );
  }

  Future<void> _runDebug(BookSource source, String key) async {
    log('⇒開始除錯書源: ${source.bookSourceName}');

    try {
      if (key.startsWith('http')) {
        log('⇒開始訪問詳情頁: $key', state: 20);
        await _infoDebug(source, key);
      } else if (key.contains('::')) {
        final url = key.split('::').last;
        log('⇒開始訪問發現頁: $url', state: 10);
        await _exploreDebug(source, url);
      } else if (key.startsWith('++')) {
        final url = key.substring(2);
        log('⇒開始訪問目錄頁: $url', state: 30);
        await _tocDebug(source, url);
      } else if (key.startsWith('--')) {
        final url = key.substring(2);
        log('⇒開始訪問正文頁: $url', state: 40);
        await _contentDebug(source, url);
      } else {
        log('⇒開始搜尋關鍵字: $key', state: 10);
        await _searchDebug(source, key);
      }
      // 途中已記錄失敗（例如搜尋沒找到書）時，不再接一行成功的「解析完成」。
      if (!_runFailed) log('︽解析完成', state: 1000);
    } on DioException catch (e) {
      log('❌ 發生錯誤: ${userErrorReason(e)}', state: -1);
      // 轉址之後才失敗的，出錯的是轉址到的網址。
      final uri = e.response?.finalUri ?? e.requestOptions.uri;
      log('  出錯的請求: ${uri.removeFragment()}');
    } catch (e) {
      log('❌ 發生錯誤: $e', state: -1);
    }
  }

  Future<void> _searchDebug(BookSource source, String key) async {
    log('︾開始解析搜尋頁', state: 10);
    log('  搜尋 URL: ${source.searchUrl}');

    final books = await _bookSourceService.searchBooks(source, key, page: 1);
    if (books.isNotEmpty) {
      log('︽搜尋頁解析完成，獲取到 ${books.length} 本書籍', state: 10);
      for (var i = 0; i < books.length && i < 5; i++) {
        log('  [$i] ${books[i].name} - ${books[i].author ?? "未知"}');
      }
      final firstBook = Book(
        origin: source.bookSourceUrl,
        bookUrl: books.first.bookUrl,
        name: books.first.name,
      );
      await _infoDebug(source, firstBook.bookUrl, book: firstBook);
    } else {
      log('︽未獲取到書籍', state: -1);
    }
  }

  Future<void> _exploreDebug(BookSource source, String url) async {
    log('︾開始解析發現頁', state: 10);
    log('  發現 URL: $url');

    final books = await _bookSourceService.exploreBooks(source, url, page: 1);
    if (books.isNotEmpty) {
      log('︽發現頁解析完成，獲取到 ${books.length} 本書籍', state: 10);
      for (var i = 0; i < books.length && i < 5; i++) {
        log('  [$i] ${books[i].name} - ${books[i].author ?? "未知"}');
      }
      final firstBook = Book(
        origin: source.bookSourceUrl,
        bookUrl: books.first.bookUrl,
        name: books.first.name,
      );
      await _infoDebug(source, firstBook.bookUrl, book: firstBook);
    } else {
      log('︽未獲取到書籍', state: -1);
    }
  }

  Future<void> _infoDebug(BookSource source, String url, {Book? book}) async {
    final targetBook = book ?? Book(origin: source.bookSourceUrl, bookUrl: url);
    if (targetBook.tocUrl.isNotEmpty) {
      log('≡已獲取目錄連結, 跳過詳情頁', state: 20);
      await _tocDebug(source, targetBook.tocUrl, book: targetBook);
      return;
    }

    log('︾開始解析詳情頁', state: 20);
    log('  詳情 URL: $url');

    final infoBook = await _bookSourceService.getBookInfo(source, targetBook);
    log('︽詳情頁解析完成: ${infoBook.name}', state: 20);
    log('  作者: ${infoBook.author}, 目錄: ${infoBook.tocUrl}');
    if (infoBook.tocUrl.isNotEmpty) {
      await _tocDebug(source, infoBook.tocUrl, book: infoBook);
    }
  }

  Future<void> _tocDebug(BookSource source, String url, {Book? book}) async {
    final targetBook = book ?? Book(origin: source.bookSourceUrl, tocUrl: url);
    log('︾開始解析目錄頁', state: 30);
    log('  目錄 URL: $url');

    final chapters = await _bookSourceService.getChapterList(
      source,
      targetBook,
    );
    log('︽目錄頁解析完成，共 ${chapters.length} 章', state: 30);
    if (chapters.isNotEmpty) {
      log('  首章: ${chapters.first.title}');
      log('  末章: ${chapters.last.title}');
    }

    if (chapters.isNotEmpty) {
      final firstChapter = chapters.first;
      final nextChapterUrl = chapters.length > 1 ? chapters[1].url : null;
      await _contentDebug(
        source,
        firstChapter.url,
        book: targetBook,
        chapter: firstChapter,
        nextUrl: nextChapterUrl,
        toc: [for (final chapter in chapters) chapter.url],
      );
    } else {
      log('≡沒有正文章節', state: -1);
    }
  }

  Future<void> _contentDebug(
    BookSource source,
    String url, {
    Book? book,
    BookChapter? chapter,
    String? nextUrl,
    List<String> toc = const [],
  }) async {
    final targetBook = book ?? Book(origin: source.bookSourceUrl);
    final targetChapter =
        chapter ??
        BookChapter(title: '除錯', url: url, bookUrl: targetBook.bookUrl);

    log('︾開始解析正文頁: ${targetChapter.title}', state: 40);
    log('  正文 URL: $url');
    if (nextUrl != null) log('  下一章 URL: $nextUrl');

    Future<String> fetch() => _bookSourceService.getContent(
      source,
      targetBook,
      targetChapter,
      nextChapterUrl: nextUrl,
    );
    final pages = <LoggedPage>[];
    final requests = currentRequestLog;
    final content = await (requests == null
        ? fetch()
        : requests.keepingPages(pages, fetch));

    lastContent = (
      source: source,
      book: targetBook,
      content: content,
      pages: pages,
      toc: toc,
    );
    log('︽正文頁解析完成 (內容長度: ${content.length})', state: 1000);
    if (content.length > 100) {
      log('正文預覽: ${content.substring(0, 100)}...');
    } else {
      log('正文內容: $content');
    }
  }
}
