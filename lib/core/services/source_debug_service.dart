import 'dart:async';
import 'package:intl/intl.dart';
import 'book_source_service.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/utils/html_formatter.dart';

class DebugLog {
  final int
  state; // 1: info, 10: search, 20: detail, 30: toc, 40: content, 1000: success, -1: error
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
  bool _isCancelled = false;

  void log(String msg, {int state = 1, bool isHtml = false}) {
    if (_isCancelled) return;

    var printMsg = msg;
    if (isHtml) {
      printMsg = HtmlFormatter.format(msg);
    }

    final debugLog = DebugLog(state, printMsg, DateTime.now());
    _logController.add(debugLog);
  }

  void cancel() {
    _isCancelled = true;
  }

  Future<void> startDebug(BookSource source, String key) async {
    _isCancelled = false;
    log('⇒開始調試書源: ${source.bookSourceName}');

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
      log('︽解析完成', state: 1000);
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
  }) async {
    final targetBook = book ?? Book(origin: source.bookSourceUrl);
    final targetChapter =
        chapter ??
        BookChapter(title: '調試', url: url, bookUrl: targetBook.bookUrl);

    log('︾開始解析正文頁: ${targetChapter.title}', state: 40);
    log('  正文 URL: $url');

    final content = await _bookSourceService.getContent(
      source,
      targetBook,
      targetChapter,
      nextChapterUrl: nextUrl,
    );

    log('︽正文頁解析完成 (內容長度: ${content.length})', state: 1000);
    if (content.length > 100) {
      log('正文預覽: ${content.substring(0, 100)}...');
    } else {
      log('正文內容: $content');
    }
  }
}
