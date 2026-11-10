import 'dart:async';
import 'dart:io';

import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/core/local_book/local_book_formats.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'association_base.dart';

import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';

/// AssociationHandlerService 的檔案分享與解析邏輯擴展
mixin FileAssociationHandler on AssociationBase {
  Future<void> handleSharedMedia(
    BuildContext context,
    List<SharedMediaFile> media,
  ) async {
    for (final item in media) {
      final path = item.path;
      // 點了 legado://、yuedu:// 連結（ACTION_VIEW）時，分享套件也會把同一個
      // 連結回報成一筆 url；連結由 app_links 那條處理，這裡再處理一次會把網址
      // 當成檔案去讀，跳出「無法辨識」。
      if (item.type == SharedMediaType.url) continue;
      // text/plain 分享的可能是檔案（套件存成暫存檔，path 是檔案路徑），也可能
      // 是文字本身（path 就是那段文字）。
      final isFile =
          item.type != SharedMediaType.text || await File(path).exists();
      if (!context.mounted) return;
      if (!isFile) {
        // 不存在的絕對路徑是套件沒解析出檔案時給的 URI 路徑，不是分享的文字：
        // 例如帶 text/plain 類型的 yuedu:// 連結會變成 `/importonline`，
        // 連結本身由 app_links 處理。
        if (!p.posix.isAbsolute(path)) _handleSharedText(context, path);
        continue;
      }
      AppLog.d('收到分享檔案: $path');
      final ext = p.extension(path).toLowerCase();
      if (ext == '.json') {
        await _handleSharedJsonFile(context, path);
      } else if (isSupportedLocalBookExtension(ext)) {
        await handleSharedBook(context, path);
      }
    }
  }

  Future<void> handleSharedBook(BuildContext context, String path) async {
    try {
      final fileName = p.basename(path);
      final imported = await context
          .read<BookshelfProvider>()
          .importLocalBookPath(path);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(imported ? '已將書籍加入書架：$fileName' : '加入書架失敗：$fileName'),
        ),
      );
    } catch (e) {
      AppLog.e('匯入分享的書籍失敗: $e', error: e);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('匯入書籍失敗：${userErrorReason(e)}')));
    }
  }

  /// 分享的文字是網址時照沒寫類型的連結處理（下載後判斷），否則當成內容判斷。
  void _handleSharedText(BuildContext context, String text) {
    final trimmed = text.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty) {
      unawaited(importUntypedLink(context, trimmed));
    } else {
      importContent(context, '分享的文字', text);
    }
  }

  Future<void> _handleSharedJsonFile(BuildContext context, String path) async {
    final String content;
    try {
      content = await File(path).readAsString();
    } catch (error, stackTrace) {
      final message = failureMessage('讀取檔案', error, stackTrace);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    if (!context.mounted) return;
    importContent(context, p.basename(path), content);
  }
}
