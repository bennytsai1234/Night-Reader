import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 文件、支援與暫存三個根目錄的路徑（[AppStoragePaths.roots]）。
typedef StorageRoots = ({String documents, String support, String temporary});

/// Centralizes app-owned filesystem locations so features don't hardcode paths.
class AppStoragePaths {
  /// 背景 isolate 用主 isolate 問好的三個根目錄（[useRoots]），不再每次經
  /// 平台頻道問：書源 isolate 讀一次快取就要問一次，網路 isolate 替停住的
  /// 書源 isolate 做事時也不必等平台回覆。
  static StorageRoots? _roots;

  /// 這個 isolate 的三個根目錄，給 [useRoots] 傳到背景 isolate。
  static Future<StorageRoots> roots() async => (
    documents: (await documentsDir()).path,
    support: (await supportDir()).path,
    temporary: (await temporaryDir()).path,
  );

  static void useRoots(StorageRoots roots) => _roots = roots;

  static Future<Directory> documentsDir() async {
    if (_roots case final roots?) return Directory(roots.documents);
    try {
      return await getApplicationDocumentsDirectory();
    } on MissingPluginException {
      return _fallbackRoot();
    }
  }

  static Future<Directory> supportDir() async {
    if (_roots case final roots?) return Directory(roots.support);
    try {
      return await getApplicationSupportDirectory();
    } on MissingPluginException {
      return _fallbackRoot();
    }
  }

  static Future<Directory> temporaryDir() async {
    if (_roots case final roots?) return Directory(roots.temporary);
    try {
      return await getTemporaryDirectory();
    } on MissingPluginException {
      return _fallbackRoot();
    }
  }

  static Future<Directory> ruleDataDir({bool ensureExists = false}) async {
    return _subdirectory(
      await documentsDir(),
      'ruleData',
      ensureExists: ensureExists,
    );
  }

  /// 加入書架的本地書原檔（TXT、EPUB）。選檔器給的是會被系統清掉的暫存
  /// 副本，一律複製到這裡再匯入。
  static Future<Directory> localBooksDir({bool ensureExists = false}) async {
    return _subdirectory(
      await documentsDir(),
      'InkpageBooks',
      ensureExists: ensureExists,
    );
  }

  static Future<Directory> imageCacheDir({bool ensureExists = false}) async {
    return _subdirectory(
      await temporaryDir(),
      'libCachedImageData',
      ensureExists: ensureExists,
    );
  }

  static Future<Directory> bookAssetsDir({bool ensureExists = false}) async {
    return _subdirectory(
      await documentsDir(),
      'book_assets',
      ensureExists: ensureExists,
    );
  }

  static Future<Directory> bookAssetDir(
    String bookKey, {
    bool ensureExists = false,
  }) async {
    _validatePathComponent(bookKey, argumentName: 'bookKey');
    return _subdirectory(
      await bookAssetsDir(ensureExists: ensureExists),
      bookKey,
      ensureExists: ensureExists,
    );
  }

  static Future<Directory> shareExportDir({bool ensureExists = false}) async {
    return _subdirectory(
      await temporaryDir(),
      'exports',
      ensureExists: ensureExists,
    );
  }

  static Future<File> shareExportFile(String fileName) async {
    _validatePathComponent(fileName, argumentName: 'fileName');
    final dir = await shareExportDir(ensureExists: true);
    return File(p.join(dir.path, fileName));
  }

  static Future<Directory> backupTempDir({bool ensureExists = false}) async {
    return _subdirectory(
      await temporaryDir(),
      'legado_backup_zip',
      ensureExists: ensureExists,
    );
  }

  /// App 內更新下載的 APK；Android 端的 FileProvider 只開放這個目錄。
  static Future<Directory> appUpdateDir({bool ensureExists = false}) async {
    return _subdirectory(
      await temporaryDir(),
      'updates',
      ensureExists: ensureExists,
    );
  }

  static Future<Directory> jsCacheDir({bool ensureExists = false}) async {
    return _subdirectory(
      await temporaryDir(),
      'js_cache',
      ensureExists: ensureExists,
    );
  }

  static Future<Directory> _subdirectory(
    Directory root,
    String name, {
    required bool ensureExists,
  }) async {
    final dir = Directory(p.join(root.path, name));
    if (ensureExists && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Directory _fallbackRoot() {
    return Directory(p.join(Directory.systemTemp.path, 'night_reader'));
  }

  static void _validatePathComponent(
    String value, {
    required String argumentName,
  }) {
    if (value.isEmpty ||
        value == '.' ||
        value == '..' ||
        value.contains('/') ||
        value.contains(r'\')) {
      throw ArgumentError.value(
        value,
        argumentName,
        'must be a single non-empty path component',
      );
    }
  }
}
