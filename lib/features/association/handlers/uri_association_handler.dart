import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/services/app_log_service.dart';

import '../import_content.dart';
import 'association_base.dart';

/// AssociationHandlerService 的 URI 解析邏輯擴展
/// 支援 legado:// 與 yuedu:// 兩種 scheme (對標 Android OnLineImportActivity)
///
/// legado:// 格式:
///   legado://import/{type}?src={url}  — 匯入書源或替換規則
///   legado://import/addToBookshelf?src={url}  — 加入書架
///   legado://import/auto?src={url}  — 沒寫類型，下載後依內容判斷
///
/// yuedu:// 格式 (舊版相容):
///   yuedu://booksource/importonline?src={url}  — 匯入書源
///   yuedu://rsssource/importonline?src={url}   — 訂閱源（不支援，只告知）
///   yuedu://replace/importonline?src={url}     — 匯入替換規則
mixin UriAssociationHandler on AssociationBase {
  void handleUri(BuildContext context, Uri uri) {
    AppLog.d('處理 Deep Link: $uri');

    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'legado') {
      _handleLegadoScheme(context, uri);
    } else if (scheme == 'yuedu') {
      _handleYueduScheme(context, uri);
    }
  }

  /// 處理 legado:// scheme
  void _handleLegadoScheme(BuildContext context, Uri uri) {
    final src = uri.queryParameters['src'];
    if (src == null || src.isEmpty) return;

    if (uri.host == 'import') {
      final type = uri.pathSegments.isNotEmpty ? uri.pathSegments[0] : '';
      // 對應 Legado 的 path 映射；其他路徑（含 /auto）照 Legado 下載後判斷。
      final kind = switch (type) {
        'bookSource' => ImportContentKind.bookSource,
        'rssSource' => ImportContentKind.rssSource,
        'replaceRule' => ImportContentKind.replaceRule,
        'addToBookshelf' => ImportContentKind.bookshelf,
        _ => null,
      };
      _dispatch(context, kind, src);
    } else if (uri.host == 'addBook') {
      final url = uri.queryParameters['url'] ?? src;
      showLinkImportDialog(context, ImportContentKind.bookshelf, url);
    }
  }

  /// 處理 yuedu:// scheme (舊版相容)
  /// 格式: yuedu://{host}/importonline?src={url}
  void _handleYueduScheme(BuildContext context, Uri uri) {
    final src = uri.queryParameters['src'];
    if (src == null || src.isEmpty) return;

    final kind = switch (uri.host.toLowerCase()) {
      'booksource' => ImportContentKind.bookSource,
      'rsssource' => ImportContentKind.rssSource,
      'replace' => ImportContentKind.replaceRule,
      _ => null,
    };
    _dispatch(context, kind, src);
  }

  void _dispatch(BuildContext context, ImportContentKind? kind, String src) {
    if (kind == null) {
      unawaited(importUntypedLink(context, src));
    } else {
      showLinkImportDialog(context, kind, src);
    }
  }
}
