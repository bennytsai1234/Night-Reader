import 'dart:io';
import 'package:path/path.dart' as p;

/// FileUtils - 檔案靜態輔助工具 (原 Android utils/FileUtils.kt)
class FileUtils {
  FileUtils._();

  /// 獲取系統暫存目錄
  static Directory getTempDir() {
    return Directory.systemTemp;
  }

  /// 建立目錄 (如果不存在)
  static Directory createFolderIfNotExist(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// 格式化檔案大小
  static String formatFileSize(int size) {
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(2)}KB';
    if (size < 1024 * 1024 * 1024)
      return '${(size / (1024 * 1024)).toStringAsFixed(2)}MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }

  /// 獲取路徑中的檔名 (不含字尾)
  static String getNameExcludeExtension(String path) {
    return p.basenameWithoutExtension(path);
  }

  /// 獲取路徑中的字尾 (不含點)
  static String getExtension(String path) {
    final ext = p.extension(path);
    return ext.startsWith('.') ? ext.substring(1) : ext;
  }

  /// 路徑合併
  static String getPath(String root, List<String> subPaths) {
    return p.joinAll([root, ...subPaths]);
  }

  /// 刪除檔案或目錄
  static Future<void> delete(String path, {bool recursive = true}) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.file) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } else if (type == FileSystemEntityType.directory) {
      final dir = Directory(path);
      if (await dir.exists()) await dir.delete(recursive: recursive);
    }
  }
}
