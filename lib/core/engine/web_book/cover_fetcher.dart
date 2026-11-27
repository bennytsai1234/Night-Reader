import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/engine/web_book/illustration_fetcher.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/source/lenient_json.dart';

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

  /// 這個書源的封面要不要照書源抓：要跑書源程式（[needsScript]：封面解密、
  /// 網址帶 `{{}}`／`@js:`／`<js>`、標頭或網址選項是 JS）、書源有標頭、要
  /// 登入（Cookie）或網址帶選項時才要；其他的照一般圖片抓。Legado 每張封面
  /// 都經過 `AnalyzeUrl`。
  static bool needsSource(BookSource source, String url) =>
      needsScript(source, url) ||
      url.contains(RegExp(r',\s*\{')) ||
      (source.header?.trim().isNotEmpty ?? false) ||
      (source.loginUrl?.trim().isNotEmpty ?? false);

  /// 抓這張封面要不要跑書源的程式（封面解密、寫成 JS 的標頭或網址）：要的
  /// 才交給書源 isolate；只帶靜態標頭、Cookie、網址選項的在主 isolate 照書源
  /// 組請求抓，不建 JS 引擎。書源 isolate 等每個請求時整條停住（ADR 0034），
  /// 搜尋結果上百張封面不跟搜尋搶它。標頭或網址選項解不成 JSON 時，
  /// AnalyzeUrl 會當成 JS 跑（`_decodeLooseObject`），也算要。
  static bool needsScript(BookSource source, String url) {
    if (source.coverDecodeJs?.trim().isNotEmpty ?? false) return true;
    final lower = url.toLowerCase();
    // AnalyzeUrl 的 _jsPattern 不分大小寫。
    if (lower.contains('@js:') ||
        lower.contains('<js>') ||
        url.contains('{{')) {
      return true;
    }
    if (!_isPlainObject(source.header)) return true;
    final options = RegExp(r',\s*(\{.*)$', dotAll: true).firstMatch(url);
    return options != null && !_isPlainObject(options.group(1));
  }

  /// [text] 是空的，或解得成一個 JSON 物件（寬鬆寫法也算）。
  static bool _isPlainObject(String? text) {
    final t = text?.trim() ?? '';
    if (t.isEmpty) return true;
    try {
      return decodeLenientJson(t) is Map;
    } on Object {
      return false;
    }
  }
}
