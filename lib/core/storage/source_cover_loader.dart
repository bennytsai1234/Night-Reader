import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/web_book/cover_fetcher.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source/book_source_service.dart';

/// 網路封面的位元組，照書的書源抓（Legado 的封面帶著 `sourceOrigin`，
/// `OkHttpStreamFetcher` 照書源組請求）：書源有標頭、要登入、要解密或網址
/// 帶選項時照書源組請求（[CoverFetcher]；要跑書源程式的才交給書源
/// isolate），其他的照一般圖片抓。都存進同一個磁碟快取
/// （`CachedNetworkImageProvider` 用的那個），鍵是封面網址。
abstract final class SourceCoverLoader {
  /// 書源網址 [origin] 的書源（找不到是 null），記一分鐘：搜尋結果上百張
  /// 封面，不必每張都讀一次資料庫；書源改了一分鐘內就照新的抓。
  static final Map<String, (DateTime, Future<BookSource?>)> _sources = {};
  static const _sourceMemo = Duration(minutes: 1);

  static Future<BookSource?> _sourceOf(String origin) {
    final now = DateTime.now();
    final memo = _sources[origin];
    if (memo != null && now.difference(memo.$1) < _sourceMemo) return memo.$2;
    final lookup = getIt<BookSourceDao>().getByUrl(origin);
    _sources[origin] = (now, lookup);
    return lookup;
  }

  /// [url] 這張封面的位元組；[origin] 是書的書源網址，[book] 交給書源的解密
  /// 程式（`coverDecodeJs` 的 `book`）。
  static Future<Uint8List> load(
    String url,
    String? origin, {
    Book? book,
  }) async {
    final cache = CachedNetworkImageProvider.defaultCacheManager;
    final cached = await cache.getFileFromCache(url);
    if (cached != null) return cached.file.readAsBytes();
    final source = origin == null || origin.isEmpty
        ? null
        : await _sourceOf(origin);
    if (source != null && CoverFetcher.needsSource(source, url)) {
      final bytes = CoverFetcher.needsScript(source, url)
          ? await BookSourceService().fetchCover(source, url, book: book)
          : await CoverFetcher.fetch(source, book, url);
      await cache.putFile(url, bytes);
      return bytes;
    }
    final file = await cache.getSingleFile(url);
    return file.readAsBytes();
  }
}
