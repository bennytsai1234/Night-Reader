import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../models/book.dart';
import '../models/book_source.dart';
import '../models/chapter.dart';
import 'book_chapter_files.dart';
import 'book_source_service.dart';
import 'network_service.dart';

/// 有聲書一集的手動下載（ADR 0055）：照書源拿到音訊網址與標頭，整個檔抓下來
/// 存成這本書的章節檔（[BookChapterFiles]）。播放器遇到下載好的集放本機檔。
abstract final class AudioChapterDownload {
  /// 認得的音訊副檔名。iPhone 的播放器靠副檔名認格式，所以照網址或回應的
  /// 類型取；都認不出來時當 MP3（書源最常見的格式）。
  static const Set<String> extensions = {
    '.mp3',
    '.m4a',
    '.m4b',
    '.aac',
    '.ogg',
    '.oga',
    '.opus',
    '.flac',
    '.wav',
  };

  static const Map<String, String> _byContentType = {
    'audio/mpeg': '.mp3',
    'audio/mp3': '.mp3',
    'audio/mp4': '.m4a',
    'audio/x-m4a': '.m4a',
    'audio/aac': '.aac',
    'audio/ogg': '.ogg',
    'audio/opus': '.opus',
    'audio/flac': '.flac',
    'audio/x-flac': '.flac',
    'audio/wav': '.wav',
    'audio/x-wav': '.wav',
  };

  /// 下載 [chapter]，傳回存好的檔。已經下載好的直接傳回。
  static Future<File> download(
    BookSource source,
    Book book,
    BookChapter chapter, {
    CancelToken? cancelToken,
    BookSourceService? service,
    Dio? dio,
  }) async {
    final existing = await BookChapterFiles.fileFor(book, chapter);
    if (existing != null) return existing;
    final request = await (service ?? BookSourceService()).getAudioRequest(
      source,
      book,
      chapter,
      cancelToken: cancelToken,
    );
    final dir = Directory(await BookChapterFiles.dirFor(book));
    await dir.create(recursive: true);
    // 結尾是 .part：還沒存好前不算已下載（[BookChapterFiles.downloaded]）。
    final temp = File(
      p.join(
        dir.path,
        '${BookChapterFiles.baseNameFor(chapter)}.download'
        '${BookChapterFiles.partialSuffix}',
      ),
    );
    try {
      // 走共用的網路設定（Cookie、通行檢查、逾時，CODING_STANDARDS.md）。
      final response = await (dio ?? NetworkService().dio).download(
        request.url,
        temp.path,
        options: Options(headers: request.headers),
        cancelToken: cancelToken,
      );
      final contentType = response.headers.value(Headers.contentTypeHeader);
      await _checkIsAudio(temp, contentType);
      final extension = extensionFor(request.url, contentType);
      return await BookChapterFiles.save(
        book,
        chapter,
        extension,
        (partial) => temp.rename(partial.path),
      );
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  /// 抓到的是音訊檔才存：m3u8 這類串流只是一份清單（分段另外抓），存下來
  /// 沒網路時播不了，還會蓋過可以串流播的網址；書源回網頁（錯誤頁、登入
  /// 頁）也不是音訊。
  static Future<void> _checkIsAudio(File file, String? contentType) async {
    final type = contentType?.split(';').first.trim().toLowerCase() ?? '';
    final head = await file
        .openRead(0, 16)
        .fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk));
    final text = String.fromCharCodes(head).trimLeft();
    if (type.contains('mpegurl') || text.startsWith('#EXTM3U')) {
      throw const AudioDownloadRefused('這一集是串流，不能下載，照樣可以線上聽');
    }
    if (type.startsWith('text/') ||
        text.startsWith('<') ||
        text.toLowerCase().startsWith('<!doctype')) {
      throw const AudioDownloadRefused('書源回的是網頁，不是音訊');
    }
  }

  /// 存檔用的副檔名：網址路徑的副檔名認得就用它，否則看回應的類型。
  static String extensionFor(String url, String? contentType) {
    final path = Uri.tryParse(url)?.path ?? url;
    final fromUrl = p.extension(path).toLowerCase();
    if (extensions.contains(fromUrl)) return fromUrl;
    final type = contentType?.split(';').first.trim().toLowerCase();
    return _byContentType[type] ?? '.mp3';
  }
}

/// 抓到的不是可以離線播的音訊檔（串流清單、網頁），沒有存。
class AudioDownloadRefused implements Exception {
  const AudioDownloadRefused(this.message);
  final String message;

  @override
  String toString() => message;
}
