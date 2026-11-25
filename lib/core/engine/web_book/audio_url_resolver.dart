import 'package:dio/dio.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/engine/web_book/complete_content_fetcher.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';

/// 有聲書一集的音訊請求：播放器拿它自己抓（ADR 0055）。
class AudioRequest {
  const AudioRequest({required this.url, required this.headers});

  final String url;
  final Map<String, String> headers;
}

/// 有聲書源的正文規則回傳的是音訊網址（可以帶 Legado 的網址選項，例如
/// 標頭）；正文規則空白時章節網址就是音訊網址。同 Legado
/// `WebBook.getContentAwait` 與 `AudioPlayService.play`。
final class AudioUrlResolver {
  AudioUrlResolver._();

  static Future<AudioRequest> resolve(
    BookSource source,
    Book book,
    BookChapter chapter, {
    CancelToken? cancelToken,
  }) async {
    // 正文規則空白時抓到的就是章節網址（[CompleteContentFetcher.fetch]）。
    final content = await CompleteContentFetcher.fetch(
      source,
      book,
      chapter,
      cancelToken: cancelToken,
    );
    final raw = firstUrl(content);
    if (raw.isEmpty) {
      throw SourceException('沒有取得音訊網址', sourceUrl: chapter.url);
    }
    final request = await AnalyzeUrl(
      raw,
      baseUrl: chapter.getAbsoluteURL(),
      source: source,
      ruleData: book,
    ).playbackRequest();
    return AudioRequest(url: request.url, headers: request.headers);
  }

  /// 正文裡的第一個非空行：替換規則可能在每行前面加了全形空白縮排。
  static String firstUrl(String content) {
    for (final line in content.split(RegExp(r'\r?\n'))) {
      final trimmed = line.replaceAll('　', ' ').trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }
}
