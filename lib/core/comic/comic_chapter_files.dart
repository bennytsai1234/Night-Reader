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

  /// 這一章依序的每一張圖與寬高。CBZ 有 [comicInfoName] 記著每張的寬高時
  /// 直接用，否則讀每張圖的檔頭。資料夾或檔案不存在時丟出
  /// [FileSystemException]，ZIP 壞掉時丟出 [FormatException]；不是 ZIP 的檔
  /// 讀不到任何圖，回傳空的。
  static Future<List<ComicPage>> pagesOf(String path) =>
      Isolate.run(() => listPagesSync(path));

  /// 讀出 [name] 這張圖；章節或這張圖不見了時是 null。
  static Future<Uint8List?> readPage(String path, String name) {
    if (!isArchive(path)) {
      final file = File(p.join(path, name));
      return file.exists().then((exists) => exists ? file.readAsBytes() : null);
    }
    return Isolate.run(() => _readArchivePage(path, name));
  }

  /// [readPage] 的同步版本，給已經在背景 isolate 裡的呼叫端。
  static Uint8List? readPageSync(String path, String name) {
    if (isArchive(path)) return _readArchivePage(path, name);
    final file = File(p.join(path, name));
    return file.existsSync() ? file.readAsBytesSync() : null;
  }

  /// [pagesOf] 的同步版本，給已經在背景 isolate 裡的呼叫端。
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

  static List<ComicPage> _archivePages(String path) =>
      _withArchive(path, (archive) {
        final images = <ArchiveFile>[
          for (final file in archive.files)
            if (file.isFile &&
                !_isHidden(file.name) &&
                _isImageFile(file.name, () => _archiveHeadOf(file)))
              file,
        ]..sort((a, b) => compareNatural(a.name, b.name));
        final recorded = _recordedSizes(archive, images.length);
        return [
          for (var i = 0; i < images.length; i++)
            _pageWithSize(
              images[i].name,
              recorded?[i] ?? _sizeOfBytes(images[i].readBytes()),
            ),
        ];
      });

  static Uint8List? _readArchivePage(String path, String name) {
    if (!File(path).existsSync()) return null;
    return _withArchive(path, (archive) => archive.find(name)?.readBytes());
  }

  static T _withArchive<T>(String path, T Function(Archive archive) action) {
    if (!File(path).existsSync()) {
      throw FileSystemException('章節檔不存在', path);
    }
    final input = InputFileStream(path);
    try {
      return action(ZipDecoder().decodeStream(input));
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
