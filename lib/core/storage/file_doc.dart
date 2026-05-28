import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../services/app_log_service.dart';

/// FileDoc - 虛擬文件系統封裝 (原 Android utils/FileDocExtensions.kt)
/// 統一處理 Sandbox 內部與外部掛載文件的存取介面
class FileDoc {
  final String name;
  final bool isDir;
  final int size;
  final int lastModified;
  final String path;

  FileDoc({
    required this.name,
    required this.isDir,
    required this.size,
    required this.lastModified,
    required this.path,
  });

  factory FileDoc.fromFile(File file) {
    final stat = file.statSync();
    return FileDoc(
      name: p.basename(file.path),
      isDir: false,
      size: stat.size,
      lastModified: stat.modified.millisecondsSinceEpoch,
      path: file.path,
    );
  }

  factory FileDoc.fromDirectory(Directory dir) {
    final stat = dir.statSync();
    return FileDoc(
      name: p.basename(dir.path),
      isDir: true,
      size: 0, // 目錄大小通常不直接計算
      lastModified: stat.modified.millisecondsSinceEpoch,
      path: dir.path,
    );
  }

  /// 列出子文件 (對標 list)
  List<FileDoc> list({bool Function(FileDoc)? filter}) {
    if (!isDir) return [];
    final dir = Directory(path);
    if (!dir.existsSync()) return [];

    final result = <FileDoc>[];
    try {
      for (final entity in dir.listSync()) {
        FileDoc doc;
        if (entity is File) {
          doc = FileDoc.fromFile(entity);
        } else if (entity is Directory) {
          doc = FileDoc.fromDirectory(entity);
        } else {
          continue;
        }
        if (filter == null || filter(doc)) {
          result.add(doc);
        }
      }
    } catch (e, s) {
      AppLog.put('Unexpected Error', error: e, stackTrace: s);
    }
    return result;
  }

  /// 讀取為位元組 (對標 readBytes)
  Future<Uint8List> readBytes() async {
    if (isDir) throw Exception('Cannot read bytes from a directory');
    return await File(path).readAsBytes();
  }

  /// 刪除文件或目錄 (對標 delete)
  Future<void> delete() async {
    final entity = isDir ? Directory(path) : File(path);
    if (await entity.exists()) {
      await entity.delete(recursive: true);
    }
  }

  /// 檢查是否存在 (對標 exists)
  bool exists() {
    return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
  }

  @override
  String toString() => path;
}
