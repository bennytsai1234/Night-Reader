import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../models/book.dart';
import '../models/book_source.dart';
import '../models/chapter.dart';
import 'book_chapter_files.dart';
import 'book_source_service.dart';

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
      final response = await (dio ?? Dio()).download(
        request.url,
        temp.path,
        options: Options(headers: request.headers),
        cancelToken: cancelToken,
      );
      final extension = extensionFor(
        request.url,
        response.headers.value(Headers.contentTypeHeader),
      );
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

  /// 存檔用的副檔名：網址路徑的副檔名認得就用它，否則看回應的類型。
  static String extensionFor(String url, String? contentType) {
    final path = Uri.tryParse(url)?.path ?? url;
    final fromUrl = p.extension(path).toLowerCase();
    if (extensions.contains(fromUrl)) return fromUrl;
    final type = contentType?.split(';').first.trim().toLowerCase();
    return _byContentType[type] ?? '.mp3';
  }
}
