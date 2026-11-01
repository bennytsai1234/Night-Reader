import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/encoding_detect.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:path/path.dart' as p;

import '../js_encode_utils.dart';
import '../js_extensions_base.dart';
import 'js_blocking_tasks.dart';

/// 規則 JS 的檔案函式，照 Legado：路徑都相對 App 的快取資料夾（Legado 是
/// `externalCache`），`downloadFile`、`unzipFile` 傳回的也是相對路徑；出了
/// 快取資料夾所在的 App 資料夾就丟「非法路徑」。
///
/// 快取資料夾在哪要問平台，第一次交給網路 isolate 問（[BlockingCall]，
/// ADR 0034），之後記住；讀寫檔案在這裡直接做，下載交給網路 isolate。
extension JsFileExtensions on JsExtensionsBase {
  void injectFileExtensions() {
    // java.getFile(path)：快取資料夾裡的完整路徑，JS 包成 java.io.File。
    onBlocking('getFile', (path) => _cacheFile('$path').path);

    // java.io.File 的方法：[動作, 路徑]，照 Java File 各自的做法（delete
    // 不刪有東西的資料夾、mkdir 與 createNewFile 不建上層資料夾）。只能碰
    // App 自己的資料夾。
    runtime.onMessage('_fileOp', (args) {
      final list = args as List;
      final path = _canonical(p.normalize('${list[1]}'));
      final appRoot = p.dirname(_cacheRoot());
      if (!p.isWithin(appRoot, path) && path != appRoot) {
        throw const FileSystemException('非法路徑');
      }
      final type = FileSystemEntity.typeSync(path);
      final exists = type != FileSystemEntityType.notFound;
      bool attempt(void Function() action) {
        try {
          action();
          return true;
        } on FileSystemException {
          return false;
        }
      }

      return switch (list[0]) {
        'canonical' => path,
        'exists' => exists,
        'isFile' => type == FileSystemEntityType.file,
        'isDirectory' => type == FileSystemEntityType.directory,
        'length' =>
          type == FileSystemEntityType.file ? File(path).lengthSync() : 0,
        'lastModified' =>
          exists ? FileStat.statSync(path).modified.millisecondsSinceEpoch : 0,
        'delete' => switch (type) {
          FileSystemEntityType.notFound => false,
          FileSystemEntityType.directory => attempt(Directory(path).deleteSync),
          _ => attempt(File(path).deleteSync),
        },
        'mkdirs' =>
          !exists && attempt(() => Directory(path).createSync(recursive: true)),
        'mkdir' => !exists && attempt(Directory(path).createSync),
        'createNewFile' => !exists && attempt(File(path).createSync),
        'list' =>
          type == FileSystemEntityType.directory
              ? [
                  for (final entity in Directory(path).listSync())
                    p.basename(entity.path),
                ]
              : null,
        final op => throw UnsupportedError('java.io.File 沒有 $op'),
      };
    });

    onBlocking('readFile', (path) {
      final file = _cacheFile('$path');
      return file.existsSync() ? file.readAsBytesSync() : null;
    });

    // java.readTxtFile(path[, charset])：沒給字元集時自動偵測。
    onBlocking('readTxtFile', (payload) {
      final args = payload as List;
      final file = _cacheFile('${args[0]}');
      if (!file.existsSync()) return '';
      return _decode(file.readAsBytesSync(), args.length > 1 ? args[1] : null);
    });

    // java.deleteFile(path)：資料夾連裡面的一起刪（同 Legado）。
    onBlocking('deleteFile', (path) {
      final target = _cacheFile('$path').path;
      return _deleteQuietly(target, FileSystemEntity.typeSync(target));
    });

    // java.downloadFile(url)：照書源的請求（網址選項 type 當副檔名）下載到
    // 快取資料夾，傳回相對路徑。downloadFile(十六進位, url) 是舊寫法：內容
    // 已經在手上，只寫檔。
    onBlocking('downloadFile', (payload) {
      final args = payload as List;
      final hex = args.length > 1 ? args[0]?.toString() : null;
      final url = '${args.length > 1 ? args[1] : args[0]}';
      final request = AnalyzeUrl(url, source: source);
      final type = request.type ?? (hex == null ? _suffix(url) : null);
      if (type == null) return '';
      final name = '${JsEncodeUtils.md5Encode16(url)}.$type';
      final file = File(p.join(_cacheRoot(), name));
      final bytes = hex == null
          ? BlockingCall.run(responseBytes(request)) as Uint8List
          : _hexDecode(hex);
      file
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      return '${p.separator}$name';
    });

    // unzipFile、unArchiveFile：解到快取資料夾的 ArchiveTemp/<檔名的 md5>，
    // 傳回這個相對路徑。夜讀只解 zip。
    for (final channel in ['unzipFile', 'unArchiveFile']) {
      onBlocking(channel, (zipPath) {
        if ('$zipPath'.isEmpty) return '';
        final zip = _cacheFile('$zipPath');
        final folder = p.join(
          'ArchiveTemp',
          JsEncodeUtils.md5Encode16(p.basename(zip.path)),
        );
        final out = Directory(p.join(_cacheRoot(), folder));
        if (out.existsSync()) out.deleteSync(recursive: true);
        out.createSync(recursive: true);
        final outRoot = p.normalize(out.absolute.path);
        for (final entry in ZipDecoder().decodeBytes(zip.readAsBytesSync())) {
          if (!entry.isFile) continue;
          final target = p.normalize(p.join(outRoot, entry.name));
          if (!p.isWithin(outRoot, target)) {
            AppLog.w('java.unzipFile 略過跑出資料夾的項目: ${entry.name}');
            continue;
          }
          File(target)
            ..createSync(recursive: true)
            ..writeAsBytesSync(entry.content as List<int>);
        }
        return folder;
      });
    }

    // java.getTxtInFolder(path)：資料夾裡每個檔案照各自偵測的字元集讀出來，
    // 換行接在一起，讀完刪掉資料夾（同 Legado）。
    onBlocking('getTxtInFolder', (path) {
      if ('$path'.isEmpty) return '';
      final folder = Directory(_cacheFile('$path').path);
      if (!folder.existsSync()) return '';
      final texts = [
        for (final file in folder.listSync().whereType<File>())
          _decode(file.readAsBytesSync(), null),
      ];
      folder.deleteSync(recursive: true);
      return texts.join('\n');
    });

    // getZipByteArrayContent(url, path)、getZipStringContent(url, path[,
    // charset])：url 是網址時照書源的請求抓，不是時當十六進位的內容。
    onBlocking('getZipByteArrayContent', (payload) {
      final args = payload as List;
      return _zipEntry('${args[0]}', '${args[1]}');
    });
    onBlocking('getZipStringContent', (payload) {
      final args = payload as List;
      final bytes = _zipEntry('${args[0]}', '${args[1]}');
      if (bytes == null) return '';
      return _decode(bytes, args.length > 2 ? args[2] : null);
    });
  }

  List<int>? _zipEntry(String url, String path) {
    final bytes = RegExp(r'^https?://', caseSensitive: false).hasMatch(url)
        ? BlockingCall.run(responseBytes(AnalyzeUrl(url, source: source)))
              as Uint8List
        : _hexDecode(url);
    final entry = ZipDecoder().decodeBytes(bytes).findFile(path);
    if (entry == null) {
      AppLog.d('getZipContent 未發現內容: $path');
      return null;
    }
    return entry.content as List<int>;
  }

  /// 刪掉 [path]（資料夾連裡面的一起），刪掉了傳回 true。
  static bool _deleteQuietly(String path, FileSystemEntityType type) {
    try {
      switch (type) {
        case FileSystemEntityType.notFound:
          return false;
        case FileSystemEntityType.directory:
          Directory(path).deleteSync(recursive: true);
        default:
          File(path).deleteSync();
      }
      return true;
    } on FileSystemException catch (e) {
      AppLog.w('規則 JS 刪不掉 $path: $e');
      return false;
    }
  }

  /// [charset] 沒給時自動偵測（Legado `EncodingDetect.getEncode`）。
  static String _decode(List<int> bytes, Object? charset) => charset == null
      ? EncodingDetect.decode(Uint8List.fromList(bytes))
      : Charsets.decode(bytes, charset.toString());

  /// 快取資料夾裡的 [path]（Legado `getFile`）：開頭有沒有 `/` 都接在快取
  /// 資料夾後面；跑出快取資料夾所在的 App 資料夾就丟出。
  File _cacheFile(String path) {
    final root = _cacheRoot();
    final relative = path.startsWith('/') || path.startsWith(r'\')
        ? path.substring(1)
        : path;
    final file = File(_canonical(p.normalize(p.join(root, relative))));
    final safe = p.dirname(root);
    if (!p.isWithin(safe, file.path) && file.path != safe) {
      throw const FileSystemException('非法路徑');
    }
    return file;
  }

  /// [path] 解開捷徑（符號連結）後的實際位置，同 Java 的 canonicalPath：
  /// 還不存在的部分接在最近一層存在的資料夾後面。
  static String _canonical(String path) {
    var existing = path;
    final rest = <String>[];
    while (FileSystemEntity.typeSync(existing, followLinks: false) ==
        FileSystemEntityType.notFound) {
      final parent = p.dirname(existing);
      if (parent == existing) return path;
      rest.insert(0, p.basename(existing));
      existing = parent;
    }
    return p.joinAll([File(existing).resolveSymbolicLinksSync(), ...rest]);
  }

  static String? _root;

  /// App 的快取資料夾（解開捷徑後的）：書源 isolate 啟動時就拿到了；不知道
  /// 時交給網路 isolate 問平台，之後記住。
  String _cacheRoot() => _canonical(
    p.normalize(
      AppStoragePaths.knownTemporaryPath ??
          (_root ??= BlockingCall.run(cacheDirPath()) as String),
    ),
  );

  /// 網址最後一段的副檔名（Legado `UrlUtil.getSuffix`）：不是 1 到 5 個
  /// 英數字時用 `ext`。
  static String _suffix(String url) {
    final noOption = url.split(RegExp(r'\s*,\s*(?=\{)')).first;
    final last = noOption.split('/').last.split('?').first.split('#').first;
    final dot = last.lastIndexOf('.');
    final suffix = dot < 0 ? '' : last.substring(dot + 1);
    return RegExp(r'^[a-zA-Z0-9]{1,5}$').hasMatch(suffix) ? suffix : 'ext';
  }

  static Uint8List _hexDecode(String hex) {
    final clean = hex.length.isOdd ? '0$hex' : hex;
    return Uint8List.fromList([
      for (var i = 0; i < clean.length; i += 2)
        int.parse(clean.substring(i, i + 2), radix: 16),
    ]);
  }

  /// `java.importScript` 的本機路徑（相對快取資料夾）。
  String readCacheText(String path) {
    final file = _cacheFile(path);
    return file.existsSync() ? _decode(file.readAsBytesSync(), null) : '';
  }
}
