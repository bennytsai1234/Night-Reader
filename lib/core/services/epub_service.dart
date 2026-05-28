import 'dart:collection';
import 'dart:io';

import 'package:epubx/epubx.dart';
import 'package:flutter/foundation.dart';

/// EpubService - 專業 EPUB 解析與資源服務
/// 提供 Isolate 友善的解析接口與資源管理
class EpubService {
  static final EpubService _instance = EpubService._internal();
  factory EpubService() => _instance;
  EpubService._internal();

  static const int _maxCachedBooks = 2;
  final LinkedHashMap<String, Future<_EpubParsedBook>> _parsedCache =
      LinkedHashMap<String, Future<_EpubParsedBook>>();

  /// 在背景線程解析 EPUB 元數據與章節
  Future<EpubMetadata> parseMetadata(File file) async {
    final parsed = await _loadParsedBook(file);
    return EpubMetadata(
      title: parsed.title,
      author: parsed.author,
      chapters: parsed.chapters,
      coverBytes: parsed.coverBytes,
    );
  }

  /// 獲取特定章節的 HTML 正文
  Future<String> getChapterContent(File file, String href) async {
    final parsed = await _loadParsedBook(file);
    return _resolveChapterContent(parsed.htmlByKey, href);
  }

  Future<_EpubParsedBook> _loadParsedBook(File file) async {
    final stat = await file.stat();
    final key = _cacheKey(file.path, stat);
    final existing = _parsedCache.remove(key);
    if (existing != null) {
      _parsedCache[key] = existing;
      return existing;
    }

    final task = compute(_parseEpubFile, file.path);
    _parsedCache[key] = task;
    _trimCache();
    try {
      return await task;
    } catch (_) {
      if (identical(_parsedCache[key], task)) {
        _parsedCache.remove(key);
      }
      rethrow;
    }
  }

  String _cacheKey(String path, FileStat stat) {
    return '$path|${stat.modified.millisecondsSinceEpoch}|${stat.size}';
  }

  void _trimCache() {
    while (_parsedCache.length > _maxCachedBooks) {
      _parsedCache.remove(_parsedCache.keys.first);
    }
  }

  String _resolveChapterContent(Map<String, String> htmlByKey, String href) {
    final fileName = href.split('#').first.trim();
    if (fileName.isEmpty) return '';

    final direct = htmlByKey[fileName];
    if (direct != null) return direct;

    for (final entry in htmlByKey.entries) {
      if (entry.key.endsWith('/$fileName')) {
        return entry.value;
      }
    }
    return '';
  }
}

Future<_EpubParsedBook> _parseEpubFile(String filePath) async {
  final bytes = await File(filePath).readAsBytes();
  final epubBook = await EpubReader.readBook(bytes);

  final chapters = <Map<String, String>>[];
  _processChapters(epubBook.Chapters ?? [], 0, chapters);

  final htmlByKey = <String, String>{};
  for (final entry in (epubBook.Content?.Html ?? const {}).entries) {
    final key = entry.key.toString();
    final content = entry.value.Content ?? '';
    if (content.isEmpty) continue;
    htmlByKey[key] = content;

    final plain = key.split('#').first;
    htmlByKey.putIfAbsent(plain, () => content);

    final slash = plain.lastIndexOf('/');
    if (slash >= 0 && slash + 1 < plain.length) {
      final basename = plain.substring(slash + 1);
      htmlByKey.putIfAbsent(basename, () => content);
    }
  }

  return _EpubParsedBook(
    title: epubBook.Title ?? 'Unknown Title',
    author: epubBook.Author ?? 'Unknown Author',
    chapters: chapters,
    coverBytes: await _extractCover(epubBook),
    htmlByKey: htmlByKey,
  );
}

void _processChapters(
  List<EpubChapter> epubChapters,
  int level,
  List<Map<String, String>> results,
) {
  for (final chapter in epubChapters) {
    final prefix = '  ' * level;
    results.add({
      'title': '$prefix${chapter.Title ?? "Unnamed"}',
      'href': chapter.ContentFileName ?? '',
    });
    if (chapter.SubChapters != null) {
      _processChapters(chapter.SubChapters!, level + 1, results);
    }
  }
}

Future<Uint8List?> _extractCover(EpubBook book) async {
  try {
    String? coverId;
    book.Schema?.Package?.Manifest?.Items?.forEach((item) {
      if (item.Properties != null && item.Properties!.contains('cover-image')) {
        coverId = item.Id;
      }
    });

    if (coverId != null) {
      final coverFile = book.Content?.Images?[coverId];
      if (coverFile != null) return Uint8List.fromList(coverFile.Content!);
    }

    for (final key in book.Content?.Images?.keys ?? const []) {
      if (key.toString().toLowerCase().contains('cover')) {
        return Uint8List.fromList(book.Content!.Images![key]!.Content!);
      }
    }
  } catch (_) {}
  return null;
}

class _EpubParsedBook {
  const _EpubParsedBook({
    required this.title,
    required this.author,
    required this.chapters,
    required this.coverBytes,
    required this.htmlByKey,
  });

  final String title;
  final String author;
  final List<Map<String, String>> chapters;
  final Uint8List? coverBytes;
  final Map<String, String> htmlByKey;
}

class EpubMetadata {
  final String title;
  final String author;
  final List<Map<String, String>> chapters;
  final Uint8List? coverBytes;

  EpubMetadata({
    required this.title,
    required this.author,
    required this.chapters,
    this.coverBytes,
  });
}
