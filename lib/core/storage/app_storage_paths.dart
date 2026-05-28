import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Centralizes app-owned filesystem locations so features don't hardcode paths.
class AppStoragePaths {
  static Future<Directory> documentsDir() async {
    try {
      return await getApplicationDocumentsDirectory();
    } on MissingPluginException {
      return _fallbackRoot();
    }
  }

  static Future<Directory> temporaryDir() async {
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
    return Directory(p.join(Directory.systemTemp.path, 'inkpage_reader'));
  }
}
