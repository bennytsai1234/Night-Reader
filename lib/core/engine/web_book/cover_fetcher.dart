import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/engine/web_book/illustration_fetcher.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';

/// 書源的封面照書源抓（Legado `OkHttpStreamFetcher` 加 `ImageUtils.decode`），
/// 在書源 isolate 裡跑：網址照書源的標頭、網址選項（`,{"headers":…}`）、
/// Cookie 與限流抓，書源寫了 `coverDecodeJs` 時抓到的位元組先交給它解
/// （`result` 是位元組、`src` 是封面網址、`book` 是這本書）。
abstract final class CoverFetcher {
  /// [url] 這張封面的位元組；解不出圖時丟出 [FormatException]。
  static Future<Uint8List> fetch(
    BookSource source,
    Book? book,
    String url, {
    CancelToken? cancelToken,
  }) async {
    final fetched = await AnalyzeUrl(
      url,
      source: source,
      ruleData: book,
    ).getByteArray(cancelToken: cancelToken);
    final decoded = IllustrationFetcher.decodeWith(
      source.coverDecodeJs,
      source,
      book,
      url,
      fetched,
    );
    if (decoded == null || decoded.isEmpty) {
      throw FormatException('封面解不出來：$url');
    }
    return decoded;
  }

  /// 這個書源的封面要不要照書源抓：網址帶選項、書源有標頭、要登入（Cookie）
  /// 或要解密時才要；其他的照一般圖片抓。
  static bool needsSource(BookSource source, String url) =>
      url.contains(RegExp(r',\s*\{')) ||
      (source.header?.trim().isNotEmpty ?? false) ||
      (source.coverDecodeJs?.trim().isNotEmpty ?? false) ||
      (source.loginUrl?.trim().isNotEmpty ?? false);

  /// 抓這張封面要不要跑書源的程式（封面解密、寫成 JS 的標頭或網址）：要的
  /// 才交給書源 isolate；只帶靜態標頭、Cookie、網址選項的在主 isolate 照書源
  /// 組請求抓，不建 JS 引擎。書源 isolate 等每個請求時整條停住（ADR 0034），
  /// 搜尋結果上百張封面不跟搜尋搶它。
  static bool needsScript(BookSource source, String url) {
    bool isScript(String? text) {
      final t = text?.trim() ?? '';
      return t.startsWith('@js:') || t.toLowerCase().startsWith('<js>');
    }

    return (source.coverDecodeJs?.trim().isNotEmpty ?? false) ||
        isScript(source.header) ||
        url.contains('@js:') ||
        url.toLowerCase().contains('<js>') ||
        url.contains('{{');
  }
}
