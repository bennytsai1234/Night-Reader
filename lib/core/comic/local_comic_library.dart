import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'comic_chapter_download.dart';
import 'comic_chapter_files.dart';

/// 匯入時找到的一話：一個 CBZ／ZIP 檔，或一個圖片資料夾。
class LocalComicSource {
  const LocalComicSource({required this.path, required this.title});

  final String path;

  /// 章名：檔名或資料夾名。
  final String title;
}

/// 匯入好的一話：存進本地書資料夾的 CBZ 與它的章指紋。
class LocalComicChapter {
  const LocalComicChapter({required this.fingerprint, required this.title});

  /// 章指紋（[LocalComicLibrary.fingerprintOf]），也是存檔的檔名。
  final String fingerprint;
  final String title;

  /// 這一話在書的資料夾裡的檔名。
  String get fileName => '$fingerprint${LocalComicLibrary.chapterExtension}';
}

/// 本地漫畫（ADR 0052）存在本地書資料夾裡的一個資料夾：每話一個
/// `<章指紋>.cbz`。圖片資料夾匯入時打包成 CBZ；原本就是 CBZ／ZIP 的照原樣
/// 複製。這裡的工作都讀寫檔案，要在背景 isolate 跑。
abstract final class LocalComicLibrary {
  static const String chapterExtension = '.cbz';

  /// [path]（使用者選的作品資料夾，或單一個 CBZ／ZIP）裡的每一話，照名稱
  /// 自然排序（同 Mihon 的本地漫畫）：
  /// - CBZ／ZIP 檔是一話；
  /// - 裡面直接有圖的資料夾是一話；
  /// - 作品資料夾本身直接放圖、沒有子章節時，整個資料夾是一話。
  static List<LocalComicSource> discover(String path) {
    if (FileSystemEntity.isFileSync(path)) {
      return ComicChapterFiles.isArchive(path)
          ? [LocalComicSource(path: path, title: _titleOf(path))]
          : const [];
    }
    final dir = Directory(path);
    if (!dir.existsSync()) return const [];
    final sources = <LocalComicSource>[];
    var looseImages = false;
    for (final entity in dir.listSync(followLinks: false)) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      if (entity is File) {
        if (ComicChapterFiles.isArchive(entity.path)) {
          sources.add(
            LocalComicSource(path: entity.path, title: _titleOf(name)),
          );
        } else if (_isImage(name)) {
          looseImages = true;
        }
      } else if (entity is Directory && _hasImages(entity)) {
        sources.add(LocalComicSource(path: entity.path, title: name));
      }
    }
    if (sources.isEmpty && looseImages) {
      return [LocalComicSource(path: path, title: p.basename(path))];
    }
    sources.sort((a, b) => ComicChapterFiles.compareNatural(a.title, b.title));
    return sources;
  }

  /// 一話的章指紋（SHA-256，十六進位）：依序每張圖的內容，不看檔名與
  /// 容器。同一話不管是 CBZ 還是圖片資料夾、哪台手機匯入，算出來都一樣。
  static String fingerprintOf(String chapterPath) {
    final pages = ComicChapterFiles.listPagesSync(chapterPath);
    final sink = _DigestSink();
    final hasher = sha256.startChunkedConversion(sink);
    for (final page in pages) {
      final bytes = ComicChapterFiles.readPageSync(chapterPath, page.name);
      if (bytes == null) continue;
      final length = ByteData(8)..setUint64(0, bytes.length);
      hasher
        ..add(length.buffer.asUint8List())
        ..add(bytes);
    }
    hasher.close();
    return sink.value.toString();
  }

  /// 把 [source] 存成 [bookDir] 裡的 `<章指紋>.cbz`，傳回存好的那一話；
  /// 沒有圖的傳回 null。同一話已經存過就不再存。
  static LocalComicChapter? store(LocalComicSource source, String bookDir) {
    if (ComicChapterFiles.listPagesSync(source.path).isEmpty) return null;
    final print = fingerprintOf(source.path);
    final chapter = LocalComicChapter(fingerprint: print, title: source.title);
    final target = File(p.join(bookDir, chapter.fileName));
    if (target.existsSync()) return chapter;
    Directory(bookDir).createSync(recursive: true);
    final partial = File('${target.path}.part');
    if (FileSystemEntity.isFileSync(source.path)) {
      File(source.path).copySync(partial.path);
    } else {
      _pack(source.path, partial.path, source.title);
    }
    partial.renameSync(target.path);
    return chapter;
  }

  /// 圖片資料夾打包成不壓縮的 CBZ（圖本來就壓縮過），寬高記進 ComicInfo：
  /// 開這一話時不用把每張圖讀出來量。
  static void _pack(String dir, String zipPath, String title) {
    final pages = ComicChapterFiles.listPagesSync(dir);
    final encoder = ZipFileEncoder()..create(zipPath);
    try {
      for (final page in pages) {
        final input = InputFileStream(p.join(dir, page.name));
        try {
          encoder.addArchiveFile(
            ArchiveFile.stream(page.name, input)
              ..compression = CompressionType.none,
          );
        } finally {
          input.closeSync();
        }
      }
      encoder.addArchiveFile(
        ArchiveFile.string(
          ComicChapterFiles.comicInfoName,
          ComicChapterDownload.comicInfoXml(title, [
            for (final page in pages)
              if (page.width case final width?)
                if (page.height case final height?)
                  (width: width, height: height)
                else
                  null
              else
                null,
          ]),
        ),
      );
    } finally {
      encoder.closeSync();
    }
  }

  static String _titleOf(String path) => p.basenameWithoutExtension(path);

  static bool _isImage(String name) => ComicChapterFiles.imageExtensions
      .contains(p.extension(name).toLowerCase());

  static bool _hasImages(Directory dir) {
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is File && _isImage(entity.path)) return true;
    }
    return false;
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? _value;
  Digest get value => _value!;

  @override
  void add(Digest data) => _value = data;

  @override
  void close() {}
}
