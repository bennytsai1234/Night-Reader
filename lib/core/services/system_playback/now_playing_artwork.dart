import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/resource_service.dart';
import 'package:night_reader/core/widgets/default_book_cover.dart';

/// 系統播放資訊的封面：把書的封面變成手機上的一個圖檔，交給系統去讀。
///
/// 系統（Android 的通知與鎖定畫面、iOS 的正在播放）只讀得到檔案或公開網址，
/// 讀不到 App 裡的 `local://`、`memory://`；網路封面也要先下載，載不到或
/// 不是圖時系統只會留白。這裡一律換成解得開的圖檔：網路封面用和書架同一個
/// 磁碟快取，沒有封面、載不到或解不開時畫預設封面（夜空，[DefaultBookCover]）。
/// 檔案放在系統的暫存資料夾，空間不夠時由系統清掉。
class NowPlayingArtwork {
  NowPlayingArtwork({
    Future<Directory> Function()? directory,
    Future<File> Function(String url)? download,
    Future<List<int>?> Function(String key)? memoryResource,
  }) : _directory = directory ?? _defaultDirectory,
       _download = download ?? _downloadToCoverCache,
       _memoryResource =
           memoryResource ??
           ((key) => ResourceService().getMemoryResource(key));

  final Future<Directory> Function() _directory;
  final Future<File> Function(String url) _download;
  final Future<List<int>?> Function(String key) _memoryResource;

  /// 預設封面的大小：書封面的 5:7，系統再照自己的版面縮放與裁切。
  static const int defaultCoverWidth = 360;
  static const int defaultCoverHeight = 504;

  /// 這次開 App 換過的封面；同一本書換章時直接用，不再找一次檔案。載不到
  /// 的網路封面也記著用預設封面，不每次換章都重抓；連預設封面都寫不出來時
  /// 不記，下次再試。
  final Map<String, Future<Uri>> _resolving = {};
  final Map<String, Uri> _resolved = {};

  /// 網路封面和書架的封面（`CachedNetworkImageProvider`）用同一個磁碟快取：
  /// 看過的封面不再下載。
  static Future<File> _downloadToCoverCache(String url) =>
      CachedNetworkImageProvider.defaultCacheManager.getSingleFile(url);

  static Future<Directory> _defaultDirectory() async {
    final temp = await getTemporaryDirectory();
    return Directory(p.join(temp.path, 'now_playing_art'));
  }

  /// 已經換好的封面；還沒換過的是 null（用 [resolve] 去換）。
  Uri? resolved(String? coverSource, String bookName) =>
      _resolved[_keyOf(coverSource, bookName)];

  /// 書的封面檔案。[coverSource] 是 null、空的或載不到時，是 [bookName] 的
  /// 預設封面。
  Future<Uri> resolve(String? coverSource, String bookName) {
    final key = _keyOf(coverSource, bookName);
    final done = _resolved[key];
    if (done != null) return Future<Uri>.value(done);
    return _resolving.putIfAbsent(key, () async {
      try {
        final uri = await _resolve(coverSource, bookName);
        _resolved[key] = uri;
        return uri;
      } finally {
        unawaited(_resolving.remove(key));
      }
    });
  }

  static String _keyOf(String? coverSource, String bookName) {
    final source = coverSource?.trim() ?? '';
    return source.isEmpty ? 'default\u0000$bookName' : 'cover\u0000$source';
  }

  Future<Uri> _resolve(String? coverSource, String bookName) async {
    final source = coverSource?.trim() ?? '';
    if (source.isNotEmpty) {
      try {
        final file = await _coverFile(source);
        if (file != null && await _isImage(file)) return file.uri;
      } catch (error) {
        AppLog.d('NowPlayingArtwork: cover unavailable, use default: $error');
      }
    }
    return (await _defaultCover(bookName)).uri;
  }

  Future<File?> _coverFile(String source) async {
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
      return _download(source);
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

  Future<File> _defaultCover(String bookName) async {
    final file = File(
      p.join((await _directory()).path, 'night_sky_${_hash(bookName)}.png'),
    );
    if (await file.exists() && await file.length() > 0) return file;
    final png = await DefaultBookCover.renderPng(
      bookName,
      width: defaultCoverWidth,
      height: defaultCoverHeight,
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png, flush: true);
    return file;
  }

  static String _hash(String value) =>
      sha1.convert(utf8.encode(value)).toString().substring(0, 16);
}
