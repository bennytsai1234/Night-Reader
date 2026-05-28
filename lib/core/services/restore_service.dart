import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/database/dao/book_group_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/models/bookmark.dart';
import 'package:night_reader/core/models/book_group.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/models/reader_chapter_content.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:path/path.dart' as p;

/// RestoreService - 統一恢復調度器
/// (原 Android help/storage/Restore.kt)
class RestoreService {
  static final RestoreService _instance = RestoreService._internal();
  factory RestoreService() => _instance;
  RestoreService._internal();

  final BookDao _bookDao = getIt<BookDao>();
  final BookSourceDao _sourceDao = getIt<BookSourceDao>();
  final ReplaceRuleDao _ruleDao = getIt<ReplaceRuleDao>();
  final BookGroupDao _groupDao = getIt<BookGroupDao>();
  final BookmarkDao _bookmarkDao = getIt<BookmarkDao>();
  final DownloadDao _downloadDao = getIt<DownloadDao>();
  final ReaderChapterContentDao _chapterContentDao =
      getIt<ReaderChapterContentDao>();

  /// 從備份包 (ZIP) 恢復所有數據
  Future<bool> restoreFromZip(File zipFile) async {
    try {
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final files = archive.where((file) => file.isFile).toList();
      if (files.isEmpty) return false;

      Map<String, dynamic>? manifest;
      for (final file in files) {
        if (_normalizedFileName(file.name) != 'manifest.json') continue;
        final data = utf8.decode(
          file.content as List<int>,
          allowMalformed: true,
        );
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) {
          manifest = decoded;
          break;
        }
      }
      if (!_isManifestCompatible(manifest)) {
        AppLog.w('Restore aborted: missing or incompatible manifest');
        return false;
      }

      var restoredAny = false;
      for (final file in files) {
        final fileName = _normalizedFileName(file.name);
        if (fileName == 'manifest.json') continue;
        final data = utf8.decode(
          file.content as List<int>,
          allowMalformed: true,
        );
        try {
          final dynamic decoded = jsonDecode(data);
          if (decoded is List<dynamic>) {
            await _importListData(fileName, decoded);
            restoredAny = true;
          } else if (fileName == 'config.json' &&
              decoded is Map<String, dynamic>) {
            await _restorePreferences(decoded);
            restoredAny = true;
          }
        } catch (e) {
          AppLog.e('Restore failed for $fileName: $e', error: e);
          return false;
        }
      }
      return restoredAny;
    } catch (e) {
      AppLog.e('Restore from ZIP failed: $e', error: e);
      return false;
    }
  }

  Future<void> _importListData(String fileName, List<dynamic> list) async {
    for (var item in list) {
      if (item is Map<String, dynamic>) {
        switch (fileName) {
          case 'books.json':
          case 'bookshelf.json':
            await _bookDao.upsert(Book.fromJson(item));
            break;
          case 'bookSources.json':
          case 'bookSource.json':
            await _sourceDao.upsert(BookSource.fromJson(item));
            break;
          case 'replaceRules.json':
          case 'replaceRule.json':
            await _ruleDao.upsert(ReplaceRule.fromJson(item));
            break;
          case 'bookGroups.json':
          case 'bookGroup.json':
            await _groupDao.upsert(BookGroup.fromJson(item));
            break;
          case 'bookmarks.json':
          case 'bookmark.json':
            await _bookmarkDao.upsert(Bookmark.fromJson(item));
            break;
          case 'downloadTask.json':
          case 'downloadTasks.json':
            await _downloadDao.upsert(DownloadTask.fromJson(item));
            break;
          case 'readerChapterContent.json':
          case 'readerChapterContents.json':
            await _chapterContentDao.upsertEntry(
              ReaderChapterContentEntry.fromJson(item),
            );
            break;
        }
      }
    }
  }

  Future<void> _restorePreferences(Map<String, dynamic> values) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in values.entries) {
      final val = entry.value;
      if (val is String) {
        await prefs.setString(entry.key, val);
      } else if (val is int) {
        await prefs.setInt(entry.key, val);
      } else if (val is bool) {
        await prefs.setBool(entry.key, val);
      } else if (val is double) {
        await prefs.setDouble(entry.key, val);
      } else if (val is List) {
        final strings = val.whereType<String>().toList();
        if (strings.length == val.length) {
          await prefs.setStringList(entry.key, strings);
        }
      }
    }
  }

  String _normalizedFileName(String path) => p.basename(path);

  bool _isManifestCompatible(Map<String, dynamic>? manifest) {
    if (manifest == null) return false;
    final schemaVersion = manifest['schemaVersion'];
    if (schemaVersion is! int) return false;
    return schemaVersion <= AppDatabase().schemaVersion;
  }
}
