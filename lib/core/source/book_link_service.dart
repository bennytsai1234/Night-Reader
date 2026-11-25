import 'dart:convert';

import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/parsers/java_regexp.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source/book_source_service.dart';

/// 一本書的網址找不到書可加的原因，給讀者看。
class BookLinkException extends AppException {
  BookLinkException(super.message);
}

/// 外部給的一本書的詳情頁網址（`legado://import/addToBookshelf?src=…`）找出
/// 是哪個書源的哪本書，照 Legado `AddToBookshelfDialog`。
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

  /// 照順序試這些書源，第一個抓得到詳情的就是：網址的選項註明的書源
  /// （`origin`）、書源網址就是這個網址的網站的啟用書源、詳情頁網址規則
  /// （`bookUrlPattern`）整個符合這個網址的啟用書源（照書源排序）。書架上
  /// 已經有這本、不是網址、都抓不到時丟 [BookLinkException]。
  Future<Book> findBook(String url) async {
    final onShelf = await _bookDao.getByUrl(url);
    if (onShelf != null && onShelf.isInBookshelf) {
      throw BookLinkException('《${onShelf.name}》已在書架');
    }
    final baseUrl = _baseUrl(url);
    if (baseUrl == null) throw BookLinkException('書的網址格式不對');

    final tried = <String>{};
    Future<Book?> tryOn(BookSource? source) async {
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
        );
      } catch (_) {
        return null;
      }
    }

    final named = _namedOrigin(url);
    if (named != null) {
      final book = await tryOn(await _sourceDao.getByUrl(named));
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
    final base = end < 0 ? url : url.substring(0, end);
    final option = _optionPattern.firstMatch(base);
    return option == null ? base : base.substring(0, option.start);
  }

  /// 網址後面選項裡的 `origin`（註明用哪個書源）。
  static String? _namedOrigin(String url) {
    final option = _optionPattern.firstMatch(url);
    if (option == null) return null;
    try {
      final json = jsonDecode(url.substring(option.end));
      final origin = json is Map ? json['origin'] : null;
      return origin is String && origin.isNotEmpty ? origin : null;
    } on FormatException {
      return null;
    }
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
