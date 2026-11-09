import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../constant/app_pattern.dart';
import '../engine/analyze_url.dart';
import '../engine/web_book/complete_content_fetcher.dart';
import '../engine/web_book/illustration_fetcher.dart';
import '../models/book.dart';
import '../models/book_source.dart';
import '../models/chapter.dart';
import '../services/book_chapter_files.dart';
import '../utils/illustration_markers.dart';
import 'comic_chapter_files.dart';

/// 網路漫畫一話的下載（ADR 0052），在書源 isolate 裡跑。照檔案型章節的
/// 存法（[BookChapterFiles]）：
///
/// - 下載中放 `chapters/<章節網址雜湊>.part/`：依序的圖片網址記在
///   [pageListName]，抓到的圖存成 `0001.jpg`、`0002.png`…，閱讀器照樣能讀。
/// - 抓齊後打包成 `chapters/<章節網址雜湊>.cbz`（不壓縮，附記著每張寬高的
///   `ComicInfo.xml`），刪掉暫存資料夾。CBZ 在就是下載好了。
abstract final class ComicChapterDownload {
  /// 暫存資料夾裡記圖片網址的檔。
  static const String pageListName = 'pages.json';

  static const String cbzExtension = '.cbz';

  /// [chapter] 的暫存資料夾（不保證存在）。
  static Future<Directory> partialDirFor(Book book, BookChapter chapter) async {
    final dir = await BookChapterFiles.dirFor(book);
    return Directory(
      '${BookChapterFiles.pathFor(dir, chapter, '')}'
      '${BookChapterFiles.partialSuffix}',
    );
  }

  /// [chapter] 下載好的 CBZ；還沒下載好時是 null。
  static Future<File?> cbzFor(Book book, BookChapter chapter) async {
    final file = File(
      BookChapterFiles.pathFor(
        await BookChapterFiles.dirFor(book),
        chapter,
        cbzExtension,
      ),
    );
    return await file.exists() ? file : null;
  }

  /// 正文裡依序的圖片網址：`<img src>`，以及整行只有一個網址的行（有些
  /// 漫畫源的正文規則直接回傳一串網址）。
  static List<String> imageUrlsOf(String content) {
    final urls = <String>[];
    for (final line in content.split('\n')) {
      final tags = IllustrationMarkers.sourcesOf(line);
      if (tags.isNotEmpty) {
        urls.addAll(tags);
        continue;
      }
      final bare = line.replaceAll(AppPattern.imgPattern, '').trim();
      if (_urlLine.hasMatch(bare)) urls.add(bare);
    }
    return urls;
  }

  static final RegExp _urlLine = RegExp(r'^https?://\S+$');

  /// 第 [index] 張（從 0 起）在暫存資料夾與 CBZ 裡的檔名。
  static String pageFileName(int index, String extension) =>
      '${(index + 1).toString().padLeft(4, '0')}$extension';

  /// 暫存資料夾裡第 [index] 張的檔案；還沒抓到時是 null。
  static File? pageFileIn(Directory dir, int index) {
    if (!dir.existsSync()) return null;
    final prefix = pageFileName(index, '.');
    for (final entity in dir.listSync(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is File &&
          name.startsWith(prefix) &&
          !name.endsWith(BookChapterFiles.partialSuffix)) {
        return entity;
      }
    }
    return null;
  }

  /// 這一話依序的圖片網址：暫存資料夾記著就用，否則照書源抓正文；
  /// [remember] 時記進暫存資料夾（書架上的書），閱讀與下載都用同一份。
  static Future<List<String>> pageUrls(
    BookSource source,
    Book book,
    BookChapter chapter, {
    bool remember = true,
    CancelToken? cancelToken,
  }) async {
    final dir = await partialDirFor(book, chapter);
    final list = File(p.join(dir.path, pageListName));
    if (await list.exists()) {
      try {
        final decoded = jsonDecode(await list.readAsString());
        if (decoded is List && decoded.every((url) => url is String)) {
          return decoded.cast<String>();
        }
      } on FormatException {
        // 壞掉的清單重抓。
      }
    }
    final content = await CompleteContentFetcher.fetch(
      source,
      book,
      chapter,
      cancelToken: cancelToken,
    );
    final urls = imageUrlsOf(content);
    if (urls.isEmpty) throw const FormatException('這一話的正文裡沒有圖');
    if (remember) {
      await dir.create(recursive: true);
      await list.writeAsString(jsonEncode(urls));
    }
    return urls;
  }

  /// 照書源抓一張圖（標頭、Cookie、限流照書源，有 `imageDecode` 先解）。
  /// 網站回的不是圖時丟出 [FormatException]。
  static Future<Uint8List> fetchImage(
    BookSource source,
    Book book,
    String url, {
    CancelToken? cancelToken,
  }) async {
    final fetched = await AnalyzeUrl(
      url,
      source: source,
      ruleData: book,
    ).getByteArray(cancelToken: cancelToken);
    final bytes = IllustrationFetcher.decode(source, book, url, fetched);
    if (bytes == null || ImageSize.ofBytes(bytes) == null) {
      throw FormatException('網站回的不是圖：$url');
    }
    return bytes;
  }

  /// 第 [index] 張：暫存資料夾有就讀，否則照書源抓；[keep] 時抓到的存進
  /// 暫存資料夾（書架上的書，下載不用再抓一次）。
  static Future<Uint8List> pageBytes(
    BookSource source,
    Book book,
    BookChapter chapter,
    int index,
    String url, {
    bool keep = true,
    CancelToken? cancelToken,
  }) async {
    final dir = await partialDirFor(book, chapter);
    if (pageFileIn(dir, index) case final file?) return file.readAsBytes();
    final bytes = await fetchImage(source, book, url, cancelToken: cancelToken);
    if (keep) await _savePage(dir, index, bytes);
    return bytes;
  }

  /// 抓齊這一話還沒抓到的圖，打包成 CBZ。已經是 CBZ 就不動。抓不到的圖
  /// 讓整話失敗（下載照重試規則再試），已抓到的留在暫存資料夾。
  static Future<File> download(
    BookSource source,
    Book book,
    BookChapter chapter, {
    CancelToken? cancelToken,
  }) async {
    if (await cbzFor(book, chapter) case final cbz?) return cbz;
    final urls = await pageUrls(
      source,
      book,
      chapter,
      cancelToken: cancelToken,
    );
    final dir = await partialDirFor(book, chapter);
    for (var i = 0; i < urls.length; i++) {
      if (pageFileIn(dir, i) != null) continue;
      final bytes = await fetchImage(
        source,
        book,
        urls[i],
        cancelToken: cancelToken,
      );
      await _savePage(dir, i, bytes);
    }
    final cbz = await pack(book, chapter, dir, urls.length);
    await dir.delete(recursive: true);
    return cbz;
  }

  /// 暫存資料夾裡的 [count] 張圖打包成這一話的 CBZ。
  static Future<File> pack(
    Book book,
    BookChapter chapter,
    Directory dir,
    int count,
  ) => BookChapterFiles.save(book, chapter, cbzExtension, (partial) async {
    final pages = <(File, String)>[];
    for (var i = 0; i < count; i++) {
      final file = pageFileIn(dir, i);
      if (file == null) throw StateError('第 ${i + 1} 張還沒抓到');
      pages.add((file, p.basename(file.path)));
    }
    // 圖本來就壓縮過，不再壓（同 Mihon），讀一張不用解壓整個檔。
    final encoder = ZipFileEncoder()..create(partial.path);
    try {
      for (final (file, name) in pages) {
        final input = InputFileStream(file.path);
        try {
          encoder.addArchiveFile(
            ArchiveFile.stream(name, input)..compression = CompressionType.none,
          );
        } finally {
          input.closeSync();
        }
      }
      encoder.addArchiveFile(
        ArchiveFile.string(
          ComicChapterFiles.comicInfoName,
          comicInfoXml(chapter.title, [
            for (final (file, _) in pages) ImageSize.ofFile(file.path),
          ]),
        ),
      );
    } finally {
      encoder.closeSync();
    }
  });

  /// ComicInfo 格式（Mihon 也讀寫）：章名與每張圖的寬高。
  static String comicInfoXml(
    String title,
    List<({int width, int height})?> sizes,
  ) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln('<ComicInfo>')
      ..writeln('  <Title>${_escape(title)}</Title>')
      ..writeln('  <PageCount>${sizes.length}</PageCount>')
      ..writeln('  <Pages>');
    for (var i = 0; i < sizes.length; i++) {
      final size = sizes[i];
      buffer.writeln(
        size == null
            ? '    <Page Image="$i" />'
            : '    <Page Image="$i" ImageWidth="${size.width}" '
                  'ImageHeight="${size.height}" />',
      );
    }
    buffer
      ..writeln('  </Pages>')
      ..writeln('</ComicInfo>');
    return buffer.toString();
  }

  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static Future<void> _savePage(
    Directory dir,
    int index,
    Uint8List bytes,
  ) async {
    await dir.create(recursive: true);
    final target = File(
      p.join(dir.path, pageFileName(index, extensionOf(bytes))),
    );
    final temp = File('${target.path}${BookChapterFiles.partialSuffix}');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(target.path);
  }

  /// 照檔頭認副檔名；認不出來當 JPEG。
  static String extensionOf(Uint8List b) {
    bool starts(List<int> magic, [int at = 0]) {
      if (b.length < at + magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (b[at + i] != magic[i]) return false;
      }
      return true;
    }

    if (starts(const [0x89, 0x50, 0x4E, 0x47])) return '.png';
    if (starts(const [0x47, 0x49, 0x46])) return '.gif';
    if (starts(const [0x52, 0x49, 0x46, 0x46]) &&
        starts(const [0x57, 0x45, 0x42, 0x50], 8)) {
      return '.webp';
    }
    if (starts(const [0x42, 0x4D])) return '.bmp';
    return '.jpg';
  }
}
