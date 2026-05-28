import 'dart:io';
import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'package:night_reader/core/storage/app_storage_paths.dart';

/// RuleBigDataService - 大數據規則變數持久化服務 (原 Android help/RuleBigDataHelp.kt)
/// 當變數過大時，將其存儲為本地檔案而非資料庫欄位
class RuleBigDataService {
  static final RuleBigDataService _instance = RuleBigDataService._internal();
  factory RuleBigDataService() => _instance;
  RuleBigDataService._internal();

  Directory? _ruleDataDir;

  Future<void> _ensureInit() async {
    if (_ruleDataDir != null) return;
    _ruleDataDir = await AppStoragePaths.ruleDataDir(ensureExists: true);
  }

  String _md5(String input) => md5.convert(utf8.encode(input)).toString();

  Future<void> putBookVariable(
    String bookUrl,
    String key,
    String? value,
  ) async {
    await _ensureInit();
    final md5Url = _md5(bookUrl);
    final md5Key = _md5(key);
    final dir = Directory('${_ruleDataDir!.path}/book/$md5Url');
    if (!await dir.exists()) await dir.create(recursive: true);

    final file = File('${dir.path}/$md5Key.txt');
    if (value == null) {
      if (await file.exists()) await file.delete();
    } else {
      await file.writeAsString(value);
      // Save original URL for reference (matching Android)
      final urlFile = File('${dir.path}/bookUrl.txt');
      if (!await urlFile.exists()) await urlFile.writeAsString(bookUrl);
    }
  }

  Future<String?> getBookVariable(String bookUrl, String key) async {
    await _ensureInit();
    final md5Url = _md5(bookUrl);
    final md5Key = _md5(key);
    final file = File('${_ruleDataDir!.path}/book/$md5Url/$md5Key.txt');
    if (await file.exists()) {
      return await file.readAsString();
    }
    return null;
  }

  Future<void> putChapterVariable(
    String bookUrl,
    String chapterUrl,
    String key,
    String? value,
  ) async {
    await _ensureInit();
    final md5Url = _md5(bookUrl);
    final md5ChUrl = _md5(chapterUrl);
    final md5Key = _md5(key);
    final dir = Directory('${_ruleDataDir!.path}/book/$md5Url/$md5ChUrl');
    if (!await dir.exists()) await dir.create(recursive: true);

    final file = File('${dir.path}/$md5Key.txt');
    if (value == null) {
      if (await file.exists()) await file.delete();
    } else {
      await file.writeAsString(value);
    }
  }

  Future<String?> getChapterVariable(
    String bookUrl,
    String chapterUrl,
    String key,
  ) async {
    await _ensureInit();
    final md5Url = _md5(bookUrl);
    final md5ChUrl = _md5(chapterUrl);
    final md5Key = _md5(key);
    final file = File(
      '${_ruleDataDir!.path}/book/$md5Url/$md5ChUrl/$md5Key.txt',
    );
    if (await file.exists()) {
      return await file.readAsString();
    }
    return null;
  }

  Future<void> putRssVariable(
    String origin,
    String link,
    String key,
    String? value,
  ) async {
    await _ensureInit();
    final md5Origin = _md5(origin);
    final md5Link = _md5(link);
    final md5Key = _md5(key);
    final dir = Directory('${_ruleDataDir!.path}/rss/$md5Origin/$md5Link');
    if (!await dir.exists()) await dir.create(recursive: true);

    final file = File('${dir.path}/$md5Key.txt');
    if (value == null) {
      if (await file.exists()) await file.delete();
    } else {
      await file.writeAsString(value);
    }
  }

  Future<String?> getRssVariable(String origin, String link, String key) async {
    await _ensureInit();
    final md5Origin = _md5(origin);
    final md5Link = _md5(link);
    final md5Key = _md5(key);
    final file = File(
      '${_ruleDataDir!.path}/rss/$md5Origin/$md5Link/$md5Key.txt',
    );
    if (await file.exists()) {
      return await file.readAsString();
    }
    return null;
  }

  Future<String> getStorageDir() async {
    await _ensureInit();
    return _ruleDataDir!.path;
  }

  Future<void> clear() async {
    await _ensureInit();
    if (await _ruleDataDir!.exists()) {
      await _ruleDataDir!.delete(recursive: true);
      await _ruleDataDir!.create(recursive: true);
    }
  }
}
