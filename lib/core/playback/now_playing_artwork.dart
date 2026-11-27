import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/storage/resource_service.dart';
import 'package:night_reader/core/storage/source_cover_loader.dart';
import 'package:night_reader/shared/widgets/book/default_book_cover.dart';

/// 系統播放資訊的封面：把書的封面變成手機上的一個圖檔，交給系統去讀。
///
/// 系統（Android 的通知與鎖定畫面、iOS 的正在播放）只讀得到檔案或公開網址，
/// 讀不到 App 裡的 `local://`、`memory://`；網路封面也要先下載，載不到或
/// 不是圖時系統只會留白。這裡一律換成解得開的圖檔：網路封面用和書架同一個
/// 磁碟快取，沒有封面、載不到或解不開時畫預設封面（夜空，[DefaultBookCover]；有聲書畫它的變體）。
/// 檔案放在系統的暫存資料夾，空間不夠時由系統清掉。
class NowPlayingArtwork {
  NowPlayingArtwork({
    Future<Directory> Function()? directory,
    Future<File> Function(String url, String? origin)? download,
    Future<List<int>?> Function(String key)? memoryResource,
  }) : _directory = directory ?? _defaultDirectory,
       _download = download ?? _downloadToCoverCache,
       _memoryResource =
           memoryResource ??
           ((key) => ResourceService().getMemoryResource(key));

  final Future<Directory> Function() _directory;
  final Future<File> Function(String url, String? origin) _download;
  final Future<List<int>?> Function(String key) _memoryResource;

  /// 預設封面的大小：書封面的 5:7，系統再照自己的版面縮放與裁切。
  static const int defaultCoverWidth = 360;
  static const int defaultCoverHeight = 504;

  /// 這次開 App 換過的封面；同一本書換章時直接用，不再找一次檔案。封面的
  /// 圖檔照書源與網址記（有書源網址的網路封面分書源），預設封面照類別與
  /// 書名記；連預設封面都寫不出來時不記，下次再試。
  final Map<String, Future<Uri?>> _resolving = {};
  final Map<String, Uri> _resolved = {};

  /// 這次開 App 載不到或不是圖的封面，不每次換章都重抓。有書源網址的網路
  /// 封面分書源記；書源沒封面時常共用同一張預設圖的網址，一般圖片只記網址；
  /// 預設封面照每本的類別與書名存一張（有聲書的音量條照書名），天空一律是
  /// 夜空的中間那個顏色。
  final Set<String> _unavailable = {};

  /// 網路封面和書架的封面（`CachedNetworkImageProvider`）用同一個磁碟快取：
  /// 看過的封面不再下載。有書源網址 [origin] 時照書源抓（[SourceCoverLoader]，
  /// 帶書源標頭、Cookie 與解密），抓好的在同一個快取裡。
  static Future<File> _downloadToCoverCache(String url, String? origin) =>
      SourceCoverLoader.file(url, origin);

  static Future<Directory> _defaultDirectory() async {
    final temp = await getTemporaryDirectory();
    return Directory(p.join(temp.path, 'now_playing_art'));
  }

  /// 已經換好的封面；還沒換過的是 null（用 [resolve] 去換）。
  Uri? resolved(
    String? coverSource,
    String bookName, {
    BookSourceKind kind = BookSourceKind.novel,
    String? origin,
  }) {
    final source = _usableSource(coverSource, origin);
    return source != null
        ? _resolved[_coverKey(source, origin)]
        : _resolved[_defaultKey(bookName, kind)];
  }

  /// 書的封面檔案。[coverSource] 是 null、空的或載不到時，是 [bookName] 的
  /// 預設封面，照 [kind] 畫那一類的變體。
  Future<Uri> resolve(
    String? coverSource,
    String bookName, {
    BookSourceKind kind = BookSourceKind.novel,
    String? origin,
  }) async {
    final source = _usableSource(coverSource, origin);
    if (source != null) {
      final cover = await _once(
        _coverKey(source, origin),
        () => _coverUri(source, origin),
      );
      if (cover != null) return cover;
    }
    final fallback = await _once(
      _defaultKey(bookName, kind),
      () async => (await _defaultCover(bookName, kind)).uri,
    );
    return fallback!;
  }

  /// 有內容、這次開 App 還沒判定載不到的封面來源；其他是 null。
  String? _usableSource(String? coverSource, String? origin) {
    final source = coverSource?.trim() ?? '';
    return source.isEmpty || _unavailable.contains(_sourceKey(source, origin))
        ? null
        : source;
  }

  static String _coverKey(String source, String? origin) =>
      'cover\u0000${_sourceKey(source, origin)}';

  /// 有書源網址的網路封面以書源與網址記（兩個書源共用同一個封面網址時
  /// 各記各的）；本機、記憶體與沒有書源網址的封面只記網址。
  static String _sourceKey(String source, String? origin) {
    if (origin == null || origin.isEmpty) return source;
    if (!source.startsWith('http://') && !source.startsWith('https://')) {
      return source;
    }
    return SourceCoverLoader.sourceKey(origin, source);
  }

  static String _defaultKey(String bookName, BookSourceKind kind) =>
      'default\u0000${kind.name}\u0000$bookName';

  /// 同一個 [key] 同時只換一次，換到的記下來；[work] 出錯時不記，下次再試。
  Future<Uri?> _once(String key, Future<Uri?> Function() work) {
    final done = _resolved[key];
    if (done != null) return Future<Uri?>.value(done);
    return _resolving.putIfAbsent(key, () async {
      try {
        final uri = await work();
        if (uri != null) _resolved[key] = uri;
        return uri;
      } finally {
        unawaited(_resolving.remove(key));
      }
    });
  }

  /// [source] 換成解得開的圖檔；載不到或不是圖時記進 [_unavailable]，是 null。
  Future<Uri?> _coverUri(String source, String? origin) async {
    try {
      final file = await _coverFile(source, origin);
      if (file != null && await _isImage(file)) return file.uri;
    } catch (error) {
      AppLog.d('NowPlayingArtwork: cover unavailable, use default: $error');
    }
    _unavailable.add(_sourceKey(source, origin));
    return null;
  }

  Future<File?> _coverFile(String source, String? origin) async {
    if (source.startsWith('local://')) {
      return File(source.substring('local://'.length));
    }
    if (source.startsWith('file://')) {
      return File(Uri.parse(source).toFilePath());
    }
    if (source.startsWith('memory://')) {
      final bytes = await _memoryResource(source);
      if (bytes == null || bytes.isEmpty) return null;
      final file = File(
        p.join((await _directory()).path, 'memory_${_hash(source)}'),
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return file;
    }
    if (source.startsWith('http://') || source.startsWith('https://')) {
      return _download(source, origin);
    }
    return null;
  }

  /// [file] 是解得開的圖：只讀檔頭，不整張解碼。網站有時回一頁錯誤訊息或
  /// 壞掉的檔案，交給系統只會留白。
  static Future<bool> _isImage(File file) async {
    if (!await file.exists() || await file.length() == 0) return false;
    final buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      descriptor.dispose();
      return true;
    } catch (error) {
      AppLog.d('NowPlayingArtwork: cover is not an image: $error');
      return false;
    } finally {
      buffer.dispose();
    }
  }

  Future<File> _defaultCover(String bookName, BookSourceKind kind) async {
    final file = File(
      p.join(
        (await _directory()).path,
        // 預設封面的畫法改了檔名就換版本，舊圖不再沿用（v4：星星照書名）。
        'night_sky_v4_${kind.name}_${_hash(bookName)}.png',
      ),
    );
    if (await file.exists() && await file.length() > 0) return file;
    final png = await DefaultBookCover.renderPng(
      bookName,
      width: defaultCoverWidth,
      height: defaultCoverHeight,
      kind: kind,
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png, flush: true);
    return file;
  }

  static String _hash(String value) =>
      sha1.convert(utf8.encode(value)).toString().substring(0, 16);
}
