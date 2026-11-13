import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../utils/illustration_markers.dart';

/// 一章漫畫裡的一張圖。
class ComicPage {
  const ComicPage({required this.name, this.width, this.height});

  /// 在這一章裡的名稱：圖片資料夾裡的檔名，或 CBZ 裡的路徑；讀圖用它。
  final String name;

  /// 圖的寬高（像素）；讀不出來時是 null，閱讀器先畫固定比例的骨架。
  final int? width;
  final int? height;

  /// 高除以寬；不知道寬高時是 null。
  double? get aspectRatio =>
      width == null || height == null ? null : height! / width!;

  @override
  bool operator ==(Object other) =>
      other is ComicPage &&
      other.name == name &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(name, width, height);

  @override
  String toString() => 'ComicPage($name, ${width}x$height)';
}

/// CBZ 裡一張圖的資料在檔案裡的哪一段。
final class ComicArchiveEntry {
  const ComicArchiveEntry({
    required this.offset,
    required this.compressedSize,
    required this.size,
    required this.deflated,
  });

  /// 資料從檔案第幾個位元組開始。
  final int offset;

  /// 檔案裡佔幾個位元組。
  final int compressedSize;

  /// 解開後幾個位元組。
  final int size;

  /// Deflate 壓縮的要先解開；否則是原樣存著（夜讀打包的 CBZ 都是）。
  final bool deflated;
}

/// 檔案的大小與修改時間：開章後檔案換了（重抓這一話、下載完重新打包），
/// 記下的位置就不能用。
final class _FileStamp {
  const _FileStamp(this.length, this.modified);

  final int length;
  final DateTime modified;

  static _FileStamp? of(File file) {
    try {
      final stat = file.statSync();
      if (stat.type != FileSystemEntityType.file) return null;
      return _FileStamp(stat.size, stat.modified);
    } on FileSystemException {
      return null;
    }
  }

  static Future<_FileStamp?> ofAsync(File file) async {
    try {
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return null;
      return _FileStamp(stat.size, stat.modified);
    } on FileSystemException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is _FileStamp &&
      other.length == length &&
      other.modified == modified;

  @override
  int get hashCode => Object.hash(length, modified);
}

/// 打開的一章漫畫（[ComicChapterFiles.open]）：依序的每一張圖，以及讀出
/// 其中一張。
///
/// CBZ 打開時記下每張圖的資料在檔案裡的哪一段，讀圖時直接讀那一段，不再
/// 每張都重新解析整個 ZIP（同 Mihon 的 `ArchiveReader` 一話只開一次）。原樣
/// 存著的（夜讀打包的 CBZ）讀完就是圖；Deflate 壓縮的在另一個 isolate 解開。
/// 檔案的大小或修改時間和打開時不同、或這張沒記到位置（加密、其他壓縮
/// 方式）時，照整個 ZIP 解析讀。
final class ComicChapterContents {
  ComicChapterContents._(this.path, this.pages, this._archive);

  /// 這一章的資料夾或 CBZ。
  final String path;

  /// 依序的每一張圖。
  final List<ComicPage> pages;

  /// CBZ 打開時的檔案狀態與每張圖的位置；資料夾是 null。
  final ({_FileStamp stamp, Map<String, ComicArchiveEntry> entries})? _archive;

  /// 讀出 [name] 這張圖；章節或這張圖不見了時是 null。
  Future<Uint8List?> read(String name) async {
    final archive = _archive;
    if (!ComicChapterFiles.isArchive(path)) {
      final file = File(p.join(path, name));
      return await file.exists() ? file.readAsBytes() : null;
    }
    final entry = archive?.entries[name];
    final file = File(path);
    if (entry == null || await _FileStamp.ofAsync(file) != archive!.stamp) {
      return Isolate.run(() => ComicChapterFiles._readArchivePage(path, name));
    }
    if (entry.deflated) {
      final path = this.path;
      return Isolate.run(() => _inflateEntry(path, entry));
    }
    return _readRange(file, entry.offset, entry.compressedSize);
  }

  static Future<Uint8List?> _readRange(
    File file,
    int offset,
    int length,
  ) async {
    final RandomAccessFile handle;
    try {
      handle = await file.open();
    } on FileSystemException {
      return null;
    }
    try {
      await handle.setPosition(offset);
      final bytes = await handle.read(length);
      return bytes.length == length ? bytes : null;
    } finally {
      await handle.close();
    }
  }

  /// 在另一個 isolate 裡讀出 Deflate 壓縮的那一段並解開。
  static Uint8List? _inflateEntry(String path, ComicArchiveEntry entry) {
    final RandomAccessFile handle;
    try {
      handle = File(path).openSync();
    } on FileSystemException {
      return null;
    }
    final Uint8List raw;
    try {
      handle.setPositionSync(entry.offset);
      raw = handle.readSync(entry.compressedSize);
    } finally {
      handle.closeSync();
    }
    if (raw.length != entry.compressedSize) return null;
    final bytes = Inflate(raw, uncompressedSize: entry.size).getBytes();
    return bytes.length == entry.size ? bytes : null;
  }
}

/// 存在手機上的一章漫畫：一個圖片資料夾或一個 CBZ／ZIP 檔（ADR 0052）。
/// 下載中的章節、下載完打包的 CBZ 與本地漫畫都是這兩種，閱讀器只讀它們。
///
/// 照 Mihon 的 `DirectoryPageLoader`、`ArchivePageLoader`：只收圖片檔（看
/// 副檔名，沒有副檔名時看檔頭），依名稱自然排序（`2.jpg` 在 `10.jpg`
/// 前面、不分大小寫）；CBZ 裡的資料夾不分章，裡面的圖照路徑一起排。
/// 讀檔與解壓都在另一個 isolate 做。
abstract final class ComicChapterFiles {
  /// 漫畫的壓縮檔副檔名。
  static const Set<String> archiveExtensions = {'.cbz', '.zip'};

  /// 認得的圖片副檔名（同 Mihon 的 `ImageUtil.ImageType`，加上 BMP）。
  static const Set<String> imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.avif',
    '.heif',
    '.heic',
    '.jxl',
  };

  /// CBZ 裡記章節資訊與每張圖寬高的檔（ComicInfo 格式，Mihon 也讀寫它）。
  static const String comicInfoName = 'ComicInfo.xml';

  /// [path] 是不是 CBZ／ZIP 檔（看副檔名）。
  static bool isArchive(String path) =>
      archiveExtensions.contains(p.extension(path).toLowerCase());

  /// 打開這一章：依序的每一張圖與寬高，CBZ 另外記下每張圖在檔案裡的位置，
  /// 之後讀圖（[ComicChapterContents.read]）直接讀那一段。CBZ 有
  /// [comicInfoName] 記著每張的寬高時直接用，否則讀每張圖的檔頭。資料夾或
  /// 檔案不存在時丟出 [FileSystemException]，ZIP 壞掉時丟出
  /// [FormatException]；不是 ZIP 的檔讀不到任何圖，回傳沒有圖的一章。
  static Future<ComicChapterContents> open(String path) =>
      Isolate.run(() => _openSync(path));

  static ComicChapterContents _openSync(String path) {
    if (!isArchive(path)) {
      return ComicChapterContents._(path, _directoryPages(path), null);
    }
    final stamp = _FileStamp.of(File(path));
    final (pages, entries) = _archiveIndex(path);
    return ComicChapterContents._(
      path,
      pages,
      stamp == null ? null : (stamp: stamp, entries: entries),
    );
  }

  /// 讀出 [path] 這一章的 [name] 這張圖，給已經在背景 isolate 裡的呼叫端；
  /// 章節或這張圖不見了時是 null。閱讀器用 [open]。
  static Uint8List? readPageSync(String path, String name) {
    if (isArchive(path)) return _readArchivePage(path, name);
    final file = File(p.join(path, name));
    return file.existsSync() ? file.readAsBytesSync() : null;
  }

  /// 這一章依序的每一張圖與寬高，給已經在背景 isolate 裡的呼叫端（規則同
  /// [open]）。
  static List<ComicPage> listPagesSync(String path) =>
      isArchive(path) ? _archivePages(path) : _directoryPages(path);

  static List<ComicPage> _directoryPages(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      throw FileSystemException('章節資料夾不存在', path);
    }
    final files = <String>[
      for (final entity in dir.listSync(followLinks: false))
        if (entity is File &&
            _isImageFile(p.basename(entity.path), () => _headOf(entity)))
          p.basename(entity.path),
    ]..sort(compareNatural);
    return [
      for (final name in files)
        _pageWithSize(name, ImageSize.ofFile(p.join(path, name))),
    ];
  }

  static List<ComicPage> _archivePages(String path) => _archiveIndex(path).$1;

  /// CBZ 依序的每一張圖，以及每張圖的資料在檔案裡的哪一段（讀不了那一段的
  /// 不列：加密的、不是「不壓縮」或 Deflate 的）。
  static (List<ComicPage>, Map<String, ComicArchiveEntry>) _archiveIndex(
    String path,
  ) => _withArchive(path, (archive, directory) {
    final images = <ArchiveFile>[
      for (final file in archive.files)
        if (file.isFile &&
            !_isHidden(file.name) &&
            _isImageFile(file.name, () => _archiveHeadOf(file)))
          file,
    ]..sort((a, b) => compareNatural(a.name, b.name));
    final recorded = _recordedSizes(archive, images.length);
    final pages = [
      for (var i = 0; i < images.length; i++)
        _pageWithSize(
          images[i].name,
          recorded?[i] ?? _measureAndFree(images[i]),
        ),
    ];
    return (
      pages,
      _entriesOf(path, directory, {for (final f in images) f.name}),
    );
  });

  /// [names] 每一張的資料在 [path] 裡的位置。同名的照 [ZipDecoder] 用第一個；
  /// 資料從項目開頭的固定 30 位元組、檔名與附加欄位之後開始，後兩者的長度
  /// 要讀項目開頭才知道（目錄裡記的附加欄位可能和項目開頭的不同）。
  static Map<String, ComicArchiveEntry> _entriesOf(
    String path,
    ZipDirectory directory,
    Set<String> names,
  ) {
    final headers = <String, ZipFileHeader>{};
    for (final header in directory.fileHeaders) {
      final name = header.file?.filename;
      if (name != null && names.contains(name)) {
        headers.putIfAbsent(name, () => header);
      }
    }
    final entries = <String, ComicArchiveEntry>{};
    final handle = File(path).openSync();
    try {
      final length = handle.lengthSync();
      for (final MapEntry(key: name, value: header) in headers.entries) {
        final deflated = switch (header.compressionMethod) {
          0 => false,
          8 => true,
          _ => null,
        };
        final encrypted = (header.generalPurposeBitFlag & 0x1) != 0;
        if (deflated == null || encrypted) continue;
        handle.setPositionSync(header.localHeaderOffset + 26);
        final lengths = handle.readSync(4);
        if (lengths.length < 4) continue;
        final view = ByteData.sublistView(lengths);
        final offset =
            header.localHeaderOffset +
            30 +
            view.getUint16(0, Endian.little) +
            view.getUint16(2, Endian.little);
        if (offset + header.compressedSize > length) continue;
        entries[name] = ComicArchiveEntry(
          offset: offset,
          compressedSize: header.compressedSize,
          size: header.uncompressedSize,
          deflated: deflated,
        );
      }
    } finally {
      handle.closeSync();
    }
    return entries;
  }

  /// 沒記寬高的那張讀出來量，量完就放掉：archive 讀過的內容會留在項目
  /// 裡，不放掉的話列一話就把整話的圖都留在記憶體。
  static ({int width, int height})? _measureAndFree(ArchiveFile file) {
    try {
      return _sizeOfBytes(file.readBytes());
    } finally {
      file.clear();
    }
  }

  static Uint8List? _readArchivePage(String path, String name) {
    if (!File(path).existsSync()) return null;
    return _withArchive(path, (archive, _) => archive.find(name)?.readBytes());
  }

  static T _withArchive<T>(
    String path,
    T Function(Archive archive, ZipDirectory directory) action,
  ) {
    if (!File(path).existsSync()) {
      throw FileSystemException('章節檔不存在', path);
    }
    final input = InputFileStream(path);
    try {
      final decoder = ZipDecoder();
      final archive = decoder.decodeStream(input);
      return action(archive, decoder.directory);
    } on ArchiveException catch (error) {
      throw FormatException('不是 ZIP 檔：$error', path);
    } finally {
      input.closeSync();
    }
  }

  /// CBZ 裡 [comicInfoName] 記的每張寬高，依圖的順序；沒有這個檔，或沒記
  /// 齊 [count] 張時是 null（照圖的檔頭重讀，不混用）。
  static List<({int width, int height})>? _recordedSizes(
    Archive archive,
    int count,
  ) {
    final info = archive.find(comicInfoName);
    final bytes = info?.readBytes();
    if (bytes == null) return null;
    final XmlDocument document;
    try {
      document = XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
    } on XmlException {
      return null;
    }
    final sizes = List<({int width, int height})?>.filled(count, null);
    for (final page in document.findAllElements('Page')) {
      final index = int.tryParse(page.getAttribute('Image') ?? '');
      final width = int.tryParse(page.getAttribute('ImageWidth') ?? '');
      final height = int.tryParse(page.getAttribute('ImageHeight') ?? '');
      if (index == null || index < 0 || index >= count) continue;
      if (width == null || height == null || width <= 0 || height <= 0) {
        continue;
      }
      sizes[index] = (width: width, height: height);
    }
    if (sizes.any((size) => size == null)) return null;
    return [for (final size in sizes) size!];
  }

  static ComicPage _pageWithSize(
    String name,
    ({int width, int height})? size,
  ) => ComicPage(name: name, width: size?.width, height: size?.height);

  static ({int width, int height})? _sizeOfBytes(Uint8List? bytes) =>
      bytes == null ? null : ImageSize.ofBytes(bytes);

  /// macOS 壓縮時夾帶的 `__MACOSX/` 與 `.` 開頭的隱藏檔。
  static bool _isHidden(String name) =>
      name.split('/').any((part) => part.startsWith('.')) ||
      name.startsWith('__MACOSX/');

  static bool _isImageFile(String name, Uint8List? Function() head) {
    if (p.basename(name).startsWith('.')) return false;
    final extension = p.extension(name).toLowerCase();
    if (imageExtensions.contains(extension)) return true;
    if (extension.isNotEmpty) return false;
    final bytes = head();
    return bytes != null && ImageSize.ofBytes(bytes) != null;
  }

  static const int _sniffBytes = 64;

  static Uint8List? _headOf(File file) {
    RandomAccessFile? handle;
    try {
      handle = file.openSync();
      return handle.readSync(_sniffBytes);
    } on FileSystemException {
      return null;
    } finally {
      handle?.closeSync();
    }
  }

  static Uint8List? _archiveHeadOf(ArchiveFile file) {
    final bytes = file.readBytes();
    if (bytes == null) return null;
    return bytes.length <= _sniffBytes
        ? bytes
        : Uint8List.sublistView(bytes, 0, _sniffBytes);
  }

  /// 不分大小寫的自然排序：數字照數值比（`2` 在 `10` 前面），其他照字元比
  /// （同 Mihon 的 `compareToCaseInsensitiveNaturalOrder`）。
  static int compareNatural(String a, String b) {
    final x = a.toLowerCase();
    final y = b.toLowerCase();
    var i = 0;
    var j = 0;
    while (i < x.length && j < y.length) {
      final cx = x.codeUnitAt(i);
      final cy = y.codeUnitAt(j);
      if (_isDigit(cx) && _isDigit(cy)) {
        final startX = i;
        final startY = j;
        while (i < x.length && _isDigit(x.codeUnitAt(i))) {
          i++;
        }
        while (j < y.length && _isDigit(y.codeUnitAt(j))) {
          j++;
        }
        final byValue = _compareDigits(
          x.substring(startX, i),
          y.substring(startY, j),
        );
        if (byValue != 0) return byValue;
        continue;
      }
      if (cx != cy) return cx - cy;
      i++;
      j++;
    }
    final byLength = (x.length - i) - (y.length - j);
    return byLength != 0 ? byLength : a.compareTo(b);
  }

  static bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

  /// 兩串數字照數值比，不轉成整數（頁碼可能長得超過 int）。
  static int _compareDigits(String a, String b) {
    final x = a.replaceFirst(RegExp('^0+(?=.)'), '');
    final y = b.replaceFirst(RegExp('^0+(?=.)'), '');
    if (x.length != y.length) return x.length - y.length;
    return x.compareTo(y);
  }
}
