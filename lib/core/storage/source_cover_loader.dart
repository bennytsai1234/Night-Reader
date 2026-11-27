import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
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
/// （`CachedNetworkImageProvider` 用的那個），照書源抓的鍵連書源網址一起記。
abstract final class SourceCoverLoader {
  /// 書源網址 [origin] 的書源（找不到是 null），記一分鐘：搜尋結果上百張
  /// 封面，不必每張都讀一次資料庫；書源改了一分鐘內就照新的抓。
  static final Map<String, (DateTime, Future<BookSource?>)> _sources = {};
  static const _sourceMemo = Duration(minutes: 1);

  /// 測試用：忘掉書源的一分鐘查詢快取。
  @visibleForTesting
  static void clearSourcesForTest() => _sources.clear();

  static Future<BookSource?> _sourceOf(String origin) {
    final now = DateTime.now();
    final memo = _sources[origin];
    if (memo != null && now.difference(memo.$1) < _sourceMemo) return memo.$2;
    final lookup = getIt<BookSourceDao>().getByUrl(origin);
    _sources[origin] = (now, lookup);
    // 讀不到時不記：下一張封面再讀一次。
    lookup.catchError((Object _) {
      _sources.remove(origin);
      return null;
    });
    return lookup;
  }

  /// 照 [origin] 的書源抓的封面在快取裡的鍵：連書源網址一起記，兩個書源
  /// 共用同一個封面網址、其中一個要解密或帶標頭時各拿各的；和一般圖片
  /// （鍵就是網址）分開，照一般圖片抓下、沒解密或沒帶標頭的那份不會被當成
  /// 照書源抓的。
  static String sourceKey(String origin, String url) =>
      'source\u0000$origin\u0000$url';

  /// [url] 這張封面的位元組；[origin] 是書的書源網址，[book] 交給書源的解密
  /// 程式（`coverDecodeJs` 的 `book`；Legado 畫面上的封面不傳，存封面時才
  /// 有）。
  static Future<Uint8List> load(
    String url,
    String? origin, {
    Book? book,
  }) async => (await file(url, origin, book: book)).readAsBytes();

  /// 同 [load]，交回快取裡的檔案（系統播放資訊要檔案）。
  static Future<File> file(String url, String? origin, {Book? book}) async {
    final cache = CachedNetworkImageProvider.defaultCacheManager;
    if (origin == null || origin.isEmpty) return cache.getSingleFile(url);
    final source = await _sourceOf(origin);
    if (source == null || !CoverFetcher.needsSource(source, url)) {
      return cache.getSingleFile(url);
    }
    final key = sourceKey(origin, url);
    final cached = await cache.getFileFromCache(key);
    if (cached != null) return cached.file;
    final bytes = CoverFetcher.needsScript(source, url)
        ? await BookSourceService().fetchCover(source, url, book: book)
        : await CoverFetcher.fetch(source, book, url);
    return cache.putFile(key, bytes, key: key);
  }
}
