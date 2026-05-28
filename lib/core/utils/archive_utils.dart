import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// ArchiveUtils - 壓縮檔工具 (原 Android utils/ArchiveUtils.kt)
/// 目前主要支援 ZIP 格式 (使用 archive 插件)
class ArchiveUtils {
  ArchiveUtils._();

  static const String tempFolderName = 'ArchiveTemp';

  /// 獲取暫存目錄
  static Future<String> getTempPath() async {
    final cache = await getTemporaryDirectory();
    final dir = Directory(p.join(cache.path, tempFolderName));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir.path;
  }

  /// 解壓縮檔案 (目前僅支援 ZIP)
  static Future<List<File>> deCompress(
    File archiveFile, {
    String? destPath,
    bool Function(String)? filter,
  }) async {
    final path = destPath ?? await getTempPath();
    final bytes = await archiveFile.readAsBytes();

    // 目前僅支援 ZIP，7z/RAR 需額外插件或原生支援
    if (!archiveFile.path.toLowerCase().endsWith('.zip')) {
      throw Exception(
        'Currently only ZIP is supported. Suffix: ${p.extension(archiveFile.path)}',
      );
    }

    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <File>[];

    for (final file in archive) {
      if (file.isFile) {
        if (filter != null && !filter(file.name)) continue;

        final data = file.content as List<int>;
        final outFile = File(p.join(path, file.name));
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(data);
        files.add(outFile);
      } else {
        await Directory(p.join(path, file.name)).create(recursive: true);
      }
    }
    return files;
  }

  /// 獲取壓縮檔內的文件名列表
  static Future<List<String>> getArchiveFilesName(
    File archiveFile, {
    bool Function(String)? filter,
  }) async {
    final bytes = await archiveFile.readAsBytes();
    if (!archiveFile.path.toLowerCase().endsWith('.zip')) {
      return [];
    }

    final archive = ZipDecoder().decodeBytes(bytes);
    final names = <String>[];
    for (final file in archive) {
      if (file.isFile) {
        if (filter == null || filter(file.name)) {
          names.add(file.name);
        }
      }
    }
    return names;
  }

  /// GZIP 壓縮
  static List<int> gzip(List<int> data) {
    return GZipEncoder().encode(data)!;
  }

  /// GZIP 解壓
  static List<int> unGzip(List<int> data) {
    return GZipDecoder().decodeBytes(data);
  }

  /// 將位元組陣列包裝成單個檔案的 ZIP
  static List<int> zipByteArray(List<int> data, String fileName) {
    final archive = Archive();
    archive.addFile(ArchiveFile(fileName, data.length, data));
    return ZipEncoder().encode(archive)!;
  }

  /// 將多個位元組陣列包裝成 ZIP
  static List<int> byteArraysToZip(Map<String, List<int>> files) {
    final archive = Archive();
    files.forEach((name, data) {
      archive.addFile(ArchiveFile(name, data.length, data));
    });
    return ZipEncoder().encode(archive)!;
  }

  /// 壓縮多個檔案/資料夾為 ZIP
  static Future<bool> zipFiles(List<String> srcPaths, String zipPath) async {
    try {
      final archive = Archive();
      for (final path in srcPaths) {
        final file = File(path);
        if (file.existsSync()) {
          final bytes = await file.readAsBytes();
          archive.addFile(ArchiveFile(p.basename(path), bytes.length, bytes));
        } else if (Directory(path).existsSync()) {
          final dir = Directory(path);
          await for (final entity in dir.list(recursive: true)) {
            if (entity is File) {
              final bytes = await entity.readAsBytes();
              final relativePath = p.relative(
                entity.path,
                from: dir.parent.path,
              );
              archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
            }
          }
        }
      }
      final zipData = ZipEncoder().encode(archive);
      if (zipData == null) return false;
      await File(zipPath).writeAsBytes(zipData);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 從壓縮檔中提取特定檔案的位元組
  static Future<List<int>?> getByteArrayContent(
    File archiveFile,
    String internalPath,
  ) async {
    try {
      final bytes = await archiveFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        if (file.isFile && file.name == internalPath) {
          return file.content as List<int>;
        }
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  /// 獲取 ZIP 註釋
  static Future<List<String>> getZipComments(File archiveFile) async {
    // Dart archive 包對 ZipEntry comment 的支持可能有限，通常是 ArchiveFile 級別
    final bytes = await archiveFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    return archive.files.map((f) => f.comment ?? '').toList();
  }

  /// 判斷是否為支援的壓縮檔
  static bool isArchive(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.zip') ||
        lower.endsWith('.7z') ||
        lower.endsWith('.rar') ||
        lower.endsWith('.gz');
  }
}
