import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:night_reader/core/local_book/local_book_formats.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'association_base.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';

/// AssociationHandlerService 的檔案分享與解析邏輯擴展
mixin FileAssociationHandler on AssociationBase {
  void handleSharedMedia(
    BuildContext context,
    List<SharedMediaFile> media,
    Function(BuildContext, String, String, {bool isFile, String? jsonData})
    showImportDialog,
    Function(BuildContext, String) showForceImportDialog,
  ) async {
    for (var file in media) {
      AppLog.d('收到分享檔案: ${file.path}');
      final ext = p.extension(file.path).toLowerCase();
      if (ext == '.json') {
        if (!context.mounted) {
          return;
        }
        _handleSharedFile(
          context,
          file.path,
          showImportDialog,
          showForceImportDialog,
        );
      } else if (isSupportedLocalBookExtension(ext)) {
        if (!context.mounted) {
          return;
        }
        handleSharedBook(context, file.path);
      }
    }
  }

  Future<void> handleSharedBook(BuildContext context, String path) async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final targetDir = Directory(p.join(appDocDir.path, 'InkpageBooks'));
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final fileName = p.basename(path);
      final targetPath = p.join(targetDir.path, fileName);
      if (!await File(targetPath).exists()) {
        await File(path).copy(targetPath);
      }

      if (context.mounted) {
        context.read<BookshelfProvider>().importLocalBookPath(targetPath);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已將書籍複製並匯入: $fileName')));
      }
    } catch (e) {
      AppLog.e('搬移並匯入書籍失敗: $e', error: e);
    }
  }

  Future<void> _handleSharedFile(
    BuildContext context,
    String path,
    Function(BuildContext, String, String, {bool isFile, String? jsonData})
    showImportDialog,
    Function(BuildContext, String) showForceImportDialog,
  ) async {
    try {
      final content = await File(path).readAsString();
      final data = jsonDecode(content);
      var type = 'auto';

      final dynamic first =
          (data is List && data.isNotEmpty) ? data.first : data;
      if (first is Map) {
        if (first.containsKey('bookSourceUrl')) {
          type = 'bookSource';
        } else if (first.containsKey('pattern')) {
          type = 'replaceRule';
        } else if (first.containsKey('themeName')) {
          type = 'theme';
        }
      }

      if (context.mounted) {
        showImportDialog(context, type, path, isFile: true, jsonData: content);
      }
    } catch (e) {
      if (context.mounted) {
        showForceImportDialog(context, path);
      }
    }
  }
}
