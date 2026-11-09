import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/book_illustration_storage.dart';
import 'package:night_reader/core/utils/illustration_markers.dart';

/// 網路書一章正文裡的插圖抓進這本書的插圖資料夾（ADR 0050），在書源
/// isolate 裡跑：網址照書源的標頭、Cookie 與限流抓（同 Legado
/// `BookHelp.saveImage`），書源有 `imageDecode` 時抓到的位元組先交給它解。
abstract final class IllustrationFetcher {
  /// [content] 裡還沒存的插圖抓進 [dir]，回傳還沒抓到、也還不能確定抓不到
  /// 的張數（連不上、逾時這類，下次再試）。網站回了錯誤碼、回的不是圖或
  /// 解不出圖的記成確定抓不到（[BookIllustrationStorage.missingPathFor]），
  /// [retryMissing] 為 false 時不再抓它們。抓不到的圖閱讀器不畫（ADR
  /// 0050），不讓整章失敗；取消時照樣丟出取消。
  static Future<int> fetch(
    BookSource source,
    Book book,
    String content,
    String dir, {
    bool retryMissing = true,
    CancelToken? cancelToken,
  }) async {
    final sources = IllustrationMarkers.sourcesOf(content).toSet();
    if (sources.isEmpty) return 0;
    await Directory(dir).create(recursive: true);
    var pending = 0;
    for (final src in sources) {
      final target = File(BookIllustrationStorage.pathFor(dir, src));
      if (await target.exists()) continue;
      final missing = File(BookIllustrationStorage.missingPathFor(dir, src));
      if (!retryMissing && await missing.exists()) continue;
      final Uint8List fetched;
      try {
        fetched = await AnalyzeUrl(
          src,
          source: source,
          ruleData: book,
        ).getByteArray(cancelToken: cancelToken);
      } on DioException catch (error) {
        if (error.type == DioExceptionType.cancel) rethrow;
        if (error.type == DioExceptionType.badResponse) {
          await missing.create();
        } else {
          pending += 1;
        }
        continue;
      } on Exception catch (error) {
        AppLog.w('插圖抓不到：$src（$error）');
        pending += 1;
        continue;
      }
      Uint8List? bytes;
      try {
        bytes = _decode(source, book, src, fetched);
      } on Exception catch (error) {
        AppLog.w('插圖解不出來：$src（$error）');
      }
      // 網站回錯誤頁、解不出圖時不存。
      if (bytes == null || ImageSize.ofBytes(bytes) == null) {
        await missing.create();
        continue;
      }
      try {
        final temp = File('${target.path}.part');
        await temp.writeAsBytes(bytes, flush: true);
        await temp.rename(target.path);
        if (await missing.exists()) await missing.delete();
      } on FileSystemException catch (error) {
        AppLog.w('插圖存不進去：$src（$error）');
        pending += 1;
      }
    }
    return pending;
  }

  /// 書源的 `imageDecode`（Legado `ImageUtils.decode`）：`result` 是抓到的
  /// 位元組、`src` 是圖的網址，傳回解好的位元組。沒有這條規則時原樣傳回。
  static Uint8List? _decode(
    BookSource source,
    Book book,
    String src,
    Uint8List bytes,
  ) {
    final js = source.ruleContent?.imageDecode;
    if (js == null || js.trim().isEmpty) return bytes;
    final rule = AnalyzeRule(source: source, ruleData: book).setContent(src);
    try {
      return switch (rule.evalJS(js, bytes)) {
        final Uint8List decoded => decoded,
        final List<Object?> decoded when decoded.every((v) => v is num) =>
          Uint8List.fromList([
            for (final value in decoded.cast<num>()) value.toInt() & 0xFF,
          ]),
        _ => null,
      };
    } finally {
      rule.dispose();
    }
  }
}
