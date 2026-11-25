import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/parsers/java_regexp.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/source/source_site.dart';
import 'package:night_reader/core/source/book_source_service.dart';

/// 一本書的網址找不到書可加的原因，給讀者看。
class BookLinkException extends AppException {
  BookLinkException(super.message);
}

/// 這本書已經在書架上：只是告知，不算失敗。
class BookAlreadyOnShelfException extends BookLinkException {
  BookAlreadyOnShelfException(String name) : super('《$name》已在書架');
}

/// 外部給的一本書的詳情頁網址（`legado://import/addToBookshelf?src=…`）找出
/// 是哪個書源的哪本書，照 Legado `AddToBookshelfDialog`。連結來自 App 外面，
/// 和 Legado 刻意不同的三處（ADR 0086）：網址裡有規則 JS 或反斜線的不抓；網址選項
/// 只拿 `origin` 挑書源，其餘不照著送，存的網址也不帶選項；註明的書源和網址
/// 不是同一個網站、也不符合它的詳情頁網址規則時不抓。
class BookLinkService {
  BookLinkService({
    BookSourceDao? sourceDao,
    BookDao? bookDao,
    BookSourceService? service,
  }) : _sourceDao = sourceDao ?? getIt<BookSourceDao>(),
       _bookDao = bookDao ?? getIt<BookDao>(),
       _service = service ?? BookSourceService();

  final BookSourceDao _sourceDao;
  final BookDao _bookDao;
  final BookSourceService _service;

  /// 書源規則裡網址後面接選項的寫法（`網址,{…}`），同 `AnalyzeUrl`。
  static final RegExp _optionPattern = RegExp(r'\s*,\s*(?=\{)');

  /// 抓網址時會被當成規則 JS 跑的寫法（`AnalyzeUrl.initUrl`）。
  static final RegExp _jsPattern = RegExp(
    r'\{\{|\}\}|<js>|</js>|@js:',
    caseSensitive: false,
  );

  /// 照順序試這些書源，第一個抓得到詳情的就是：網址的選項註明的書源
  /// （`origin`，要和網址同一個網站或符合它的詳情頁網址規則）、書源網址就是
  /// 這個網址的網站的啟用書源、詳情頁網址規則（`bookUrlPattern`）整個符合
  /// 這個網址的啟用書源（照書源排序）。書架上已經有這本時丟
  /// [BookAlreadyOnShelfException]；不是網址、註明的書源對不上、都抓不到時
  /// 丟 [BookLinkException]。[cancelToken] 取消時停掉正在抓的，不再試下一個，
  /// 丟出取消的錯誤。
  Future<Book> findBook(String link, {CancelToken? cancelToken}) async {
    final option = _optionPattern.firstMatch(link);
    final url = option == null ? link : link.substring(0, option.start);
    // 反斜線：各家網址解析對它看法不一，判斷網站的主機可能和真的送去的不同。
    if (_jsPattern.hasMatch(url) || url.contains(r'\')) {
      throw BookLinkException('書的網址格式不對');
    }
    final onShelf = await _bookDao.getByUrl(url);
    if (onShelf != null && onShelf.isInBookshelf) {
      throw BookAlreadyOnShelfException(onShelf.name);
    }
    final baseUrl = _baseUrl(url);
    if (baseUrl == null) throw BookLinkException('書的網址格式不對');

    final tried = <String>{};
    Future<Book?> tryOn(BookSource? source) async {
      if (cancelToken?.cancelError case final cancelled?) throw cancelled;
      if (source == null || !tried.add(source.bookSourceUrl)) return null;
      try {
        return await _service.getBookInfo(
          source,
          Book(
            bookUrl: url,
            origin: source.bookSourceUrl,
            originName: source.bookSourceName,
            type: source.bookSourceType,
          ),
          cancelToken: cancelToken,
        );
      } catch (_) {
        if (cancelToken?.isCancelled ?? false) rethrow;
        return null;
      }
    }

    final named = option == null
        ? null
        : await _namedSource(link.substring(option.end));
    if (named != null) {
      if (siteHost(named.bookSourceUrl) != siteHost(url) &&
          !_matchesPattern(named.bookUrlPattern, url)) {
        throw BookLinkException('連結指定的書源和書的網址不是同一個網站');
      }
      final book = await tryOn(named);
      if (book != null) return book;
    }
    final enabled = (await _sourceDao.getEnabled())
      ..sort((a, b) => a.customOrder.compareTo(b.customOrder));
    for (final source in enabled) {
      if (source.bookSourceUrl != baseUrl) continue;
      final book = await tryOn(source);
      if (book != null) return book;
    }
    for (final source in enabled) {
      if (!_matchesPattern(source.bookUrlPattern, url)) continue;
      final book = await tryOn(source);
      if (book != null) return book;
    }
    throw BookLinkException('找不到符合這個網址的書源');
  }

  /// 同 Legado `NetworkUtils.getBaseUrl`：`http(s)://網站`，不是網址時 null。
  static String? _baseUrl(String url) {
    final lower = url.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return null;
    }
    final end = url.indexOf('/', 9);
    return end < 0 ? url : url.substring(0, end);
  }

  /// 網址選項裡的 `origin` 註明的書源；沒寫、不是 JSON、書源不在時 null。
  Future<BookSource?> _namedSource(String options) async {
    final Object? json;
    try {
      json = jsonDecode(options);
    } on FormatException {
      return null;
    }
    final origin = json is Map ? json['origin'] : null;
    if (origin is! String || origin.isEmpty) return null;
    return _sourceDao.getByUrl(origin);
  }

  /// Legado `bookUrl.matches(bookUrlPattern.toRegex())`：整個網址都符合才算；
  /// 空的、`NONE` 與寫錯的規則都不算。
  static bool _matchesPattern(String? pattern, String url) {
    final rule = pattern?.trim() ?? '';
    if (rule.isEmpty || rule == 'NONE') return false;
    try {
      return javaRegExp(rule, wholeInput: true).hasMatch(url);
    } on FormatException {
      return false;
    }
  }
}
