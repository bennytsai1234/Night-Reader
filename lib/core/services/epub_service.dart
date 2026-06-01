import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

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

// ─── top-level isolate entry point ─────────────────────────────────────────

Future<_EpubParsedBook> _parseEpubFile(String filePath) async {
  final bytes = await File(filePath).readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);

  ArchiveFile? findFile(String path) {
    final norm = path.replaceAll('\\', '/');
    for (final f in archive.files) {
      if (f.isFile && f.name == norm) return f;
    }
    final lower = norm.toLowerCase();
    for (final f in archive.files) {
      if (f.isFile && f.name.toLowerCase() == lower) return f;
    }
    return null;
  }

  String readText(ArchiveFile f) {
    final data = f.content as List<int>;
    try {
      return utf8.decode(data);
    } catch (_) {
      return latin1.decode(data);
    }
  }

  // 1. container.xml → OPF path
  final containerFile = findFile('META-INF/container.xml');
  if (containerFile == null) {
    throw Exception('Invalid EPUB: missing META-INF/container.xml');
  }
  final containerDoc = XmlDocument.parse(readText(containerFile));
  final rootfiles = containerDoc.descendants
      .whereType<XmlElement>()
      .where((e) => e.localName == 'rootfile')
      .toList();
  if (rootfiles.isEmpty) throw Exception('Invalid EPUB: no rootfile in container.xml');

  final opfPath = rootfiles
      .firstWhere(
        (e) => e.getAttribute('media-type') == 'application/oebps-package+xml',
        orElse: () => rootfiles.first,
      )
      .getAttribute('full-path')!;

  final opfDir = opfPath.contains('/')
      ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
      : '';

  // 2. OPF
  final opfFile = findFile(opfPath);
  if (opfFile == null) throw Exception('EPUB OPF not found: $opfPath');
  final opfDoc = XmlDocument.parse(readText(opfFile));

  // 3. Metadata — search by local name to be namespace-prefix agnostic
  String? dcValue(String localName) {
    for (final el in opfDoc.descendants.whereType<XmlElement>()) {
      if (el.localName == localName) {
        final t = el.innerText.trim();
        if (t.isNotEmpty) return t;
      }
    }
    return null;
  }

  final title = dcValue('title') ?? 'Unknown Title';
  final author = dcValue('creator') ?? 'Unknown Author';

  // 4. Manifest
  final manifest = <String, _ManifestItem>{};
  for (final item in opfDoc.descendants
      .whereType<XmlElement>()
      .where((e) => e.localName == 'item')) {
    final id = item.getAttribute('id') ?? '';
    final rawHref = item.getAttribute('href') ?? '';
    if (id.isEmpty || rawHref.isEmpty) continue;
    final href = Uri.decodeFull(rawHref);
    manifest[id] = _ManifestItem(
      fullHref: '$opfDir$href',
      href: href,
      mediaType: item.getAttribute('media-type') ?? '',
      properties: item.getAttribute('properties') ?? '',
    );
  }

  // 5. Cover bytes (raw — no image decoding needed)
  Uint8List? coverBytes;
  final coverItem =
      manifest.values.where((v) => v.properties.contains('cover-image')).firstOrNull;
  if (coverItem != null) {
    final f = findFile(coverItem.fullHref);
    if (f != null) coverBytes = Uint8List.fromList(f.content as List<int>);
  }
  if (coverBytes == null) {
    for (final meta in opfDoc.descendants
        .whereType<XmlElement>()
        .where((e) => e.localName == 'meta')) {
      if (meta.getAttribute('name') == 'cover') {
        final coverId = meta.getAttribute('content');
        if (coverId != null) {
          final item = manifest[coverId];
          if (item != null) {
            final f = findFile(item.fullHref);
            if (f != null) {
              coverBytes = Uint8List.fromList(f.content as List<int>);
              break;
            }
          }
        }
      }
    }
  }
  if (coverBytes == null) {
    for (final item in manifest.values) {
      if (item.mediaType.startsWith('image/') &&
          item.href.toLowerCase().contains('cover')) {
        final f = findFile(item.fullHref);
        if (f != null) {
          coverBytes = Uint8List.fromList(f.content as List<int>);
          break;
        }
      }
    }
  }

  // 6. HTML content index — keyed by fullHref, href, and basename
  final htmlByKey = <String, String>{};
  for (final item in manifest.values) {
    if (item.mediaType != 'application/xhtml+xml' && item.mediaType != 'text/html') {
      continue;
    }
    final f = findFile(item.fullHref);
    if (f == null) continue;
    final content = readText(f);
    if (content.isEmpty) continue;

    htmlByKey[item.fullHref] = content;
    htmlByKey.putIfAbsent(item.href, () => content);

    final slash = item.fullHref.lastIndexOf('/');
    if (slash >= 0 && slash + 1 < item.fullHref.length) {
      htmlByKey.putIfAbsent(item.fullHref.substring(slash + 1), () => content);
    }
  }

  // 7. TOC — prefer EPUB3 nav, fallback to EPUB2 NCX, then spine order
  final chapters = <Map<String, String>>[];
  final navItem =
      manifest.values.where((v) => v.properties.contains('nav')).firstOrNull;
  final ncxItem = manifest.values
      .where((v) => v.mediaType == 'application/x-dtbncx+xml')
      .firstOrNull;

  if (navItem != null) {
    final f = findFile(navItem.fullHref);
    if (f != null) _parseNavToc(readText(f), navItem.fullHref, chapters);
  } else if (ncxItem != null) {
    final f = findFile(ncxItem.fullHref);
    if (f != null) _parseNcxToc(readText(f), ncxItem.fullHref, chapters);
  }

  if (chapters.isEmpty) {
    for (final itemref in opfDoc.descendants
        .whereType<XmlElement>()
        .where((e) => e.localName == 'itemref')) {
      final item = manifest[itemref.getAttribute('idref') ?? ''];
      if (item == null) continue;
      if (item.mediaType != 'application/xhtml+xml' && item.mediaType != 'text/html') {
        continue;
      }
      chapters.add({
        'title': item.href.split('/').last.split('.').first,
        'href': item.fullHref,
      });
    }
  }

  return _EpubParsedBook(
    title: title,
    author: author,
    chapters: chapters,
    coverBytes: coverBytes,
    htmlByKey: htmlByKey,
  );
}

// ─── TOC parsers ────────────────────────────────────────────────────────────

String _dirOf(String path) =>
    path.contains('/') ? path.substring(0, path.lastIndexOf('/') + 1) : '';

void _parseNcxToc(
  String ncxContent,
  String ncxPath,
  List<Map<String, String>> results,
) {
  final doc = XmlDocument.parse(ncxContent);
  final baseDir = _dirOf(ncxPath);
  final navMap = doc.descendants
      .whereType<XmlElement>()
      .where((e) => e.localName == 'navMap')
      .firstOrNull;
  if (navMap == null) return;
  _processNcxNavPoints(navMap.childElements, baseDir, 0, results);
}

void _processNcxNavPoints(
  Iterable<XmlElement> elements,
  String baseDir,
  int level,
  List<Map<String, String>> results,
) {
  for (final np in elements.where((e) => e.localName == 'navPoint')) {
    final label = np.descendants
            .whereType<XmlElement>()
            .where((e) => e.localName == 'text')
            .firstOrNull
            ?.innerText
            .trim() ??
        '';
    final src = np.descendants
            .whereType<XmlElement>()
            .where((e) => e.localName == 'content')
            .firstOrNull
            ?.getAttribute('src') ??
        '';
    if (src.isNotEmpty) {
      final cleanSrc = src.split('#').first;
      final fullHref =
          cleanSrc.startsWith('/') ? cleanSrc.substring(1) : '$baseDir$cleanSrc';
      results.add({'title': '${'  ' * level}$label', 'href': fullHref});
    }
    _processNcxNavPoints(np.childElements, baseDir, level + 1, results);
  }
}

void _parseNavToc(
  String navContent,
  String navPath,
  List<Map<String, String>> results,
) {
  final doc = XmlDocument.parse(navContent);
  final baseDir = _dirOf(navPath);

  XmlElement? tocNav;
  for (final el
      in doc.descendants.whereType<XmlElement>().where((e) => e.localName == 'nav')) {
    final epubType = el.getAttribute('epub:type') ?? el.getAttribute('type') ?? '';
    if (epubType.contains('toc')) {
      tocNav = el;
      break;
    }
  }
  tocNav ??= doc.descendants
      .whereType<XmlElement>()
      .where((e) => e.localName == 'nav')
      .firstOrNull;
  if (tocNav == null) return;

  void processOl(XmlElement ol, int depth) {
    for (final li in ol.childElements.where((e) => e.localName == 'li')) {
      final anchor = li.childElements.where((e) => e.localName == 'a').firstOrNull ??
          li.childElements.where((e) => e.localName == 'span').firstOrNull;
      if (anchor != null) {
        final rawHref = anchor.getAttribute('href') ?? '';
        if (rawHref.isNotEmpty) {
          final cleanHref = rawHref.split('#').first;
          final fullHref = cleanHref.startsWith('/')
              ? cleanHref.substring(1)
              : '$baseDir$cleanHref';
          results.add({
            'title': '${'  ' * depth}${anchor.innerText.trim()}',
            'href': fullHref,
          });
        }
      }
      for (final nestedOl in li.childElements.where((e) => e.localName == 'ol')) {
        processOl(nestedOl, depth + 1);
      }
    }
  }

  for (final ol in tocNav.childElements.where((e) => e.localName == 'ol')) {
    processOl(ol, 0);
  }
}

// ─── private data classes ───────────────────────────────────────────────────

class _ManifestItem {
  const _ManifestItem({
    required this.fullHref,
    required this.href,
    required this.mediaType,
    required this.properties,
  });

  final String fullHref;
  final String href;
  final String mediaType;
  final String properties;
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

// ─── public data class ──────────────────────────────────────────────────────

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
