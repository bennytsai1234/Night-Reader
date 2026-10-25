import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/local_book/txt_parser.dart';
import 'package:night_reader/core/services/encoding_detect.dart';

class EpubBookInfo {
  const EpubBookInfo({
    required this.title,
    required this.author,
    required this.chapters,
    this.cover,
    this.coverExtension,
  });

  final String? title;
  final String? author;

  /// 每章在轉好的純文字檔裡的位元組範圍，和 TXT 的章節一樣讀。
  final List<({String title, int start, int end})> chapters;
  final Uint8List? cover;

  /// 封面檔的副檔名，含點（`.jpg`）。
  final String? coverExtension;
}

/// 只取 EPUB 的文字：插圖略過，封面另外交給書架。
class EpubParser {
  EpubParser._();

  /// 在另一個 isolate 把 [epubPath] 轉成一段一行的 UTF-8 純文字寫到
  /// [textPath]，回傳書名、作者、封面與章節。
  ///
  /// 章節照書內目錄分；沒有文字的章節（只有圖片的封面頁、和下一章指向
  /// 同一處的卷名）不列。目錄太粗、一章超過 [TxtParser.maxChapterChars]
  /// 字時（由 TXT 轉成的 EPUB 常只有「封面」一條），那一章照 TXT 的章名
  /// 規則再切。
  static Future<EpubBookInfo> convert(String epubPath, String textPath) =>
      Isolate.run(
        () => _withArchive(epubPath, (archive) => _convert(archive, textPath)),
      );
}

const _brokenMessage = 'EPUB 檔案損壞或格式不對';

/// 壓縮檔或 XML 壞掉（兩者都是 [FormatException]）換成給使用者看的說法。
T _withArchive<T>(String path, T Function(_Archive archive) action) {
  final input = InputFileStream(path);
  try {
    return action(_Archive(ZipDecoder().decodeStream(input)));
  } on FormatException {
    throw EpubFormatException(_brokenMessage);
  } finally {
    input.closeSync();
  }
}

EpubBookInfo _convert(_Archive archive, String textPath) {
  final package = _Package.read(archive);
  final text = _EpubText(archive, package);
  final pieces = <({String title, String text})>[];
  for (final range in _chapterRanges(package, text)) {
    final content = text.range(range);
    text.forgetBefore(range.endSpine);
    if (content.isEmpty) continue;
    if (content.length <= TxtParser.maxChapterChars) {
      pieces.add((title: range.title, text: content));
      continue;
    }
    for (final span in TxtParser.splitText(
      content,
      leadTitle: range.title,
      untitledTitle: range.title,
    )) {
      pieces.add((
        title: span.title,
        text: content.substring(span.start, span.end),
      ));
    }
  }
  if (pieces.isEmpty) throw EpubFormatException('EPUB 裡沒有文字');

  final chapters = <({String title, int start, int end})>[];
  final temp = File('$textPath.tmp');
  temp.parent.createSync(recursive: true);
  final output = temp.openSync(mode: FileMode.write);
  try {
    var offset = 0;
    for (final piece in pieces) {
      final bytes = utf8.encode(piece.text);
      output
        ..writeFromSync(bytes)
        ..writeByteSync(0x0A);
      chapters.add((
        title: piece.title,
        start: offset,
        end: offset + bytes.length,
      ));
      offset += bytes.length + 1;
    }
  } finally {
    output.closeSync();
  }
  temp.renameSync(textPath);

  final coverPath = package.coverPath;
  final cover = coverPath == null ? null : archive.bytes(coverPath);
  return EpubBookInfo(
    title: package.title,
    author: package.author,
    chapters: chapters,
    cover: cover == null || cover.isEmpty ? null : cover,
    coverExtension: coverPath == null ? null : p.url.extension(coverPath),
  );
}

/// 一章在 EPUB 閱讀順序（spine）裡的範圍：從第 [startSpine] 個檔案的
/// [startFragment]（null 是檔案開頭）讀到第 [endSpine] 個檔案的
/// [endFragment] 之前（null 是讀完整個檔案）。
class _Range {
  const _Range({
    required this.title,
    required this.startSpine,
    required this.endSpine,
    this.startFragment,
    this.endFragment,
  });

  final String title;
  final int startSpine;
  final String? startFragment;
  final int endSpine;
  final String? endFragment;
}

/// 照書內目錄切章；目錄第一個條目之前的檔案（版權頁、序）併成一章。
/// 沒有能用的目錄時一個檔案一章。
List<_Range> _chapterRanges(_Package package, _EpubText text) {
  final starts = <_TocStart>[];
  for (final entry in package.toc) {
    final spine = package.spineIndexOf(entry.path);
    if (spine == null) continue;
    // 往回指的條目（附錄指回正文）會讓前後章重疊，不列。
    if (starts.isNotEmpty && spine < starts.last.spine) continue;
    starts.add(_TocStart(entry.title, spine, entry.fragment));
  }

  if (starts.isEmpty) {
    return [
      for (var i = 0; i < package.spine.length; i++)
        _Range(
          title: text.documentTitle(i) ?? '第 ${i + 1} 章',
          startSpine: i,
          endSpine: i,
        ),
    ];
  }

  final first = starts.first;
  if (first.spine > 0 || first.fragment != null) {
    final frontEnd = first.fragment == null ? first.spine - 1 : first.spine;
    final title = [for (var i = 0; i <= frontEnd; i++) i]
        .map(text.documentTitle)
        .nonNulls
        .firstOrNull;
    starts.insert(
      0,
      _TocStart(
        title == null || title == package.title ? '前言' : title,
        0,
        null,
      ),
    );
  }

  final last = package.spine.length - 1;
  return [
    for (var i = 0; i < starts.length; i++)
      if (i + 1 < starts.length)
        _Range(
          title: starts[i].title,
          startSpine: starts[i].spine,
          startFragment: starts[i].fragment,
          endSpine: starts[i + 1].fragment == null
              ? starts[i + 1].spine - 1
              : starts[i + 1].spine,
          endFragment: starts[i + 1].fragment,
        )
      else
        _Range(
          title: starts[i].title,
          startSpine: starts[i].spine,
          startFragment: starts[i].fragment,
          endSpine: last,
        ),
  ];
}

class _TocStart {
  const _TocStart(this.title, this.spine, this.fragment);

  final String title;
  final int spine;
  final String? fragment;
}

class _TocEntry {
  const _TocEntry(this.title, this.path, this.fragment);

  final String title;
  final String path;
  final String? fragment;
}

class _Archive {
  _Archive(this._archive)
    : _byLowerName = {
        for (final file in _archive.files)
          if (file.isFile) file.name.toLowerCase(): file,
      };

  final Archive _archive;
  final Map<String, ArchiveFile> _byLowerName;

  Uint8List? bytes(String path) {
    final file = _archive.find(path) ?? _byLowerName[path.toLowerCase()];
    return file?.readBytes();
  }

  XmlDocument xml(String path) {
    final data = bytes(path);
    if (data == null) throw EpubFormatException(_brokenMessage);
    return XmlDocument.parse(_decode(data));
  }
}

/// container.xml 指到的 OPF：書名、作者、閱讀順序、目錄與封面。
class _Package {
  _Package({
    required this.title,
    required this.author,
    required this.spine,
    required this.toc,
    required this.coverPath,
  }) : _spineIndex = {
         for (var i = spine.length - 1; i >= 0; i--) spine[i].toLowerCase(): i,
       };

  final String? title;
  final String? author;
  final List<String> spine;
  final List<_TocEntry> toc;
  final String? coverPath;
  final Map<String, int> _spineIndex;

  int? spineIndexOf(String path) => _spineIndex[path.toLowerCase()];

  static _Package read(_Archive archive) {
    final container = archive.xml('META-INF/container.xml');
    final rootfiles = _elements(container, 'rootfile').toList();
    final rootfile =
        rootfiles
            .where(
              (e) =>
                  e.getAttribute('media-type') ==
                  'application/oebps-package+xml',
            )
            .firstOrNull ??
        rootfiles.firstOrNull;
    final opfPath = rootfile?.getAttribute('full-path');
    if (opfPath == null || opfPath.isEmpty) {
      throw EpubFormatException(_brokenMessage);
    }
    final opf = archive.xml(opfPath);
    final opfDir = p.url.dirname(opfPath);

    final items = <String, _ManifestItem>{};
    for (final item in _elements(opf, 'item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      items[id] = _ManifestItem(
        path: _resolve(opfDir, href),
        mediaType: item.getAttribute('media-type') ?? '',
        properties: (item.getAttribute('properties') ?? '').split(' '),
      );
    }

    final spine = [
      for (final ref in _elements(opf, 'itemref'))
        if (items[ref.getAttribute('idref')] case final item?
            when item.isDocument)
          item.path,
    ];
    if (spine.isEmpty) throw EpubFormatException('EPUB 裡沒有文字');

    final nav = items.values
        .where((item) => item.properties.contains('nav'))
        .firstOrNull;
    final spineToc = _elements(opf, 'spine').firstOrNull?.getAttribute('toc');
    final ncx =
        items[spineToc] ??
        items.values
            .where((item) => item.mediaType == 'application/x-dtbncx+xml')
            .firstOrNull;
    var toc = nav == null ? const <_TocEntry>[] : _navToc(archive, nav.path);
    if (toc.isEmpty && ncx != null) toc = _ncxToc(archive, ncx.path);

    return _Package(
      title: _text(_elements(opf, 'title').firstOrNull),
      author: _text(_elements(opf, 'creator').firstOrNull),
      spine: spine,
      toc: toc,
      coverPath: _coverPath(opf, items),
    );
  }

  static String? _coverPath(XmlDocument opf, Map<String, _ManifestItem> items) {
    final declared = items.values
        .where((item) => item.properties.contains('cover-image'))
        .firstOrNull;
    if (declared != null) return declared.path;

    for (final meta in _elements(opf, 'meta')) {
      if (meta.getAttribute('name') != 'cover') continue;
      final item = items[meta.getAttribute('content')];
      if (item != null && item.isImage) return item.path;
    }

    for (final MapEntry(key: id, value: item) in items.entries) {
      if (item.isImage &&
          (id.toLowerCase().contains('cover') ||
              p.url.basename(item.path).toLowerCase().contains('cover'))) {
        return item.path;
      }
    }
    return null;
  }

  /// EPUB 3 的目錄頁：`<nav epub:type="toc">` 裡的連結依序就是章節。
  static List<_TocEntry> _navToc(_Archive archive, String path) {
    final data = archive.bytes(path);
    if (data == null) return const [];
    final navs = _parseHtml(data).getElementsByTagName('nav');
    final toc =
        navs
            .where(
              (nav) => (nav.attributes['epub:type'] ?? '')
                  .split(' ')
                  .contains('toc'),
            )
            .firstOrNull ??
        navs.firstOrNull;
    if (toc == null) return const [];
    final dir = p.url.dirname(path);
    return [
      for (final link in toc.getElementsByTagName('a'))
        ?_tocEntry(dir, _collapse(link.text), link.attributes['href']),
    ];
  }

  /// EPUB 2 的 NCX：巢狀的 navPoint 依文件順序攤平。
  static List<_TocEntry> _ncxToc(_Archive archive, String path) {
    final XmlDocument ncx;
    try {
      ncx = archive.xml(path);
    } on FormatException {
      return const [];
    } on EpubFormatException {
      return const [];
    }
    final dir = p.url.dirname(path);
    return [
      for (final point in _elements(ncx, 'navPoint'))
        ?_tocEntry(
          dir,
          _text(_child(point, 'navLabel')),
          _child(point, 'content')?.getAttribute('src'),
        ),
    ];
  }

  static _TocEntry? _tocEntry(String dir, String? title, String? href) {
    if (title == null || title.isEmpty || href == null || href.isEmpty) {
      return null;
    }
    final hash = href.indexOf('#');
    final fragment = hash < 0 ? '' : href.substring(hash + 1);
    return _TocEntry(
      title,
      _resolve(dir, href),
      fragment.isEmpty ? null : _decodeComponent(fragment),
    );
  }
}

class _ManifestItem {
  const _ManifestItem({
    required this.path,
    required this.mediaType,
    required this.properties,
  });

  final String path;
  final String mediaType;
  final List<String> properties;

  /// 書架封面畫得出來的點陣圖；SVG 不算。
  bool get isImage =>
      mediaType.startsWith('image/') && mediaType != 'image/svg+xml';

  bool get isDocument =>
      mediaType == 'application/xhtml+xml' ||
      mediaType == 'text/html' ||
      const {
        '.xhtml',
        '.html',
        '.htm',
      }.contains(p.url.extension(path).toLowerCase());
}

/// 把 spine 裡的 XHTML 轉成一段一行的純文字。
class _EpubText {
  _EpubText(this._archive, this._package);

  final _Archive _archive;
  final _Package _package;
  final Map<int, dom.Document?> _documents = {};

  static const _blockTags = {
    'address',
    'article',
    'aside',
    'blockquote',
    'body',
    'br',
    'caption',
    'dd',
    'div',
    'dl',
    'dt',
    'figcaption',
    'figure',
    'footer',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'header',
    'hr',
    'li',
    'main',
    'nav',
    'ol',
    'p',
    'pre',
    'section',
    'table',
    'tr',
    'ul',
  };

  /// 不是正文的元素：注音（ruby 的 rt、rp）只留本字，圖片與多媒體略過。
  static const _skippedTags = {
    'audio',
    'head',
    'iframe',
    'img',
    'math',
    'noscript',
    'object',
    'rp',
    'rt',
    'script',
    'style',
    'svg',
    'template',
    'video',
  };

  String range(_Range range) {
    final buffer = StringBuffer();
    final last = range.endSpine.clamp(0, _package.spine.length - 1);
    for (var spine = range.startSpine; spine <= last; spine++) {
      final body = _document(spine)?.body;
      if (body == null) continue;
      final startId = spine == range.startSpine ? range.startFragment : null;
      final stopId = spine == range.endSpine ? range.endFragment : null;
      // 錨點在檔案裡找不到時當作沒有錨點：從頭讀、讀到尾。
      _TextWalker(
        buffer,
        startId: startId != null && _hasId(body, startId) ? startId : null,
        stopId: stopId != null && _hasId(body, stopId) ? stopId : null,
      ).walk(body);
      buffer.write('\n');
    }
    return buffer
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
  }

  /// 第 [spine] 個檔案的第一個標題或 `<title>`，給沒有目錄條目的章節當章名。
  String? documentTitle(int spine) {
    final document = _document(spine);
    if (document == null) return null;
    for (final selector in const ['h1', 'h2', 'h3', 'title']) {
      final element = document.querySelector(selector);
      final title = element == null ? '' : _collapse(element.text);
      if (title.isNotEmpty) return title;
    }
    return null;
  }

  /// 切章時只往後走，前面的檔案不會再用到。
  void forgetBefore(int spine) {
    _documents.removeWhere((index, _) => index < spine);
  }

  dom.Document? _document(int spine) {
    return _documents.putIfAbsent(spine, () {
      final data = _archive.bytes(_package.spine[spine]);
      return data == null ? null : _parseHtml(data);
    });
  }
}

class _TextWalker {
  _TextWalker(this._buffer, {required this.startId, required this.stopId})
    : _started = startId == null;

  final StringBuffer _buffer;
  final String? startId;
  final String? stopId;
  bool _started;
  bool _stopped = false;
  int _preDepth = 0;

  void walk(dom.Node node) {
    if (_stopped) return;
    if (node is dom.Text) {
      if (!_started) return;
      _buffer.write(
        _preDepth > 0 ? node.data : node.data.replaceAll(_whitespace, ' '),
      );
      return;
    }
    if (node is! dom.Element) {
      for (final child in node.nodes) {
        walk(child);
      }
      return;
    }

    final id = node.attributes['id'];
    if (stopId != null && id == stopId) {
      _stopped = true;
      return;
    }
    if (!_started && id == startId) _started = true;

    final tag = node.localName?.toLowerCase() ?? '';
    if (_EpubText._skippedTags.contains(tag)) return;
    final block = _EpubText._blockTags.contains(tag);
    if (block && _started) _buffer.write('\n');
    if (tag == 'pre') _preDepth++;
    for (final child in node.nodes) {
      walk(child);
    }
    if (tag == 'pre') _preDepth--;
    if (!_started) return;
    if (block) {
      _buffer.write('\n');
    } else if (tag == 'td' || tag == 'th') {
      _buffer.write(' ');
    }
  }
}

final _whitespace = RegExp(r'[ \t\r\n\f]+');

/// 不用 `getElementById`：它走 CSS 選擇器，數字開頭或帶點的 id 會出錯。
bool _hasId(dom.Element root, String id) {
  if (root.attributes['id'] == id) return true;
  return root.children.any((child) => _hasId(child, id));
}

Iterable<XmlElement> _elements(XmlDocument document, String localName) =>
    document.descendantElements.where((e) => e.localName == localName);

XmlElement? _child(XmlElement parent, String localName) =>
    parent.childElements.where((e) => e.localName == localName).firstOrNull;

String? _text(XmlElement? element) {
  if (element == null) return null;
  final text = _collapse(element.innerText);
  return text.isEmpty ? null : text;
}

String _collapse(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// zip 裡的路徑：去掉錨點與查詢字串、解開百分比編碼，再相對 [dir] 正規化。
String _resolve(String dir, String href) {
  var path = href;
  final cut = path.indexOf(RegExp('[#?]'));
  if (cut >= 0) path = path.substring(0, cut);
  path = _decodeComponent(path);
  final joined = path.startsWith('/')
      ? path.substring(1)
      : p.url.join(dir == '.' ? '' : dir, path);
  return p.url.normalize(joined);
}

String _decodeComponent(String value) {
  try {
    return Uri.decodeComponent(value);
  } on ArgumentError {
    return value;
  }
}

final _xmlEncoding = RegExp(
  r'''^\s*<\?xml[^>]*encoding\s*=\s*["']([^"']+)["']''',
  caseSensitive: false,
);

String _decode(Uint8List data) {
  final head = latin1.decode(
    data.length > 200 ? Uint8List.sublistView(data, 0, 200) : data,
  );
  final declared = _xmlEncoding.firstMatch(head)?.group(1)?.toLowerCase();
  if (declared != null && declared != 'utf-8' && declared != 'utf8') {
    return EncodingDetect.decodeWithCharset(data, declared);
  }
  final hasBom =
      data.length >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF;
  return utf8.decode(
    hasBom ? Uint8List.sublistView(data, 3) : data,
    allowMalformed: true,
  );
}

/// XHTML 交給寬鬆的 HTML 解析器。HTML 不認得非空元素的自閉寫法，
/// `<title/>` 會把後面整份當成標題吞掉，先展開成成對標籤。
dom.Document _parseHtml(Uint8List data) {
  final source = _decode(data).replaceAllMapped(_selfClosing, (match) {
    final tag = match.group(1)!;
    if (_voidTags.contains(tag.toLowerCase())) return match.group(0)!;
    return '<$tag${match.group(2) ?? ''}></$tag>';
  });
  return html_parser.parse(source);
}

final _selfClosing = RegExp(r'<([A-Za-z][\w:.-]*)(\s[^<>]*?)?\s*/>');

const _voidTags = {
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};
