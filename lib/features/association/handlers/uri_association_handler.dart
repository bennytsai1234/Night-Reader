import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/services/app_log_service.dart';

import '../import_content.dart';
import 'association_base.dart';

/// AssociationHandlerService 的 URI 解析邏輯擴展：legado:// 與 yuedu:// 照
/// Legado 的 `OnLineImportActivity`，一定要帶 `src`（沒有就不理），照路徑
/// 判斷類型，認不得的路徑下載後依內容判斷。
///
///   legado://import/{bookSource|rssSource|replaceRule|addToBookshelf}?src={url}
///   yuedu://{booksource|rsssource|replace}/importonline?src={url}
///   其他路徑（例如 legado://import/auto?src={url}）：下載後依內容判斷
///
/// 訂閱源不支援，只告知。
mixin UriAssociationHandler on AssociationBase {
  void handleUri(BuildContext context, Uri uri) {
    AppLog.d('處理 Deep Link: $uri');

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'legado' && scheme != 'yuedu') return;
    final src = uri.queryParameters['src'];
    if (src == null || src.isEmpty) return;

    final kind = switch (uri.path) {
      '/bookSource' => ImportContentKind.bookSource,
      '/rssSource' => ImportContentKind.rssSource,
      '/replaceRule' => ImportContentKind.replaceRule,
      '/addToBookshelf' => ImportContentKind.bookshelf,
      '/importonline' => switch (uri.host.toLowerCase()) {
        'booksource' => ImportContentKind.bookSource,
        'rsssource' => ImportContentKind.rssSource,
        'replace' => ImportContentKind.replaceRule,
        _ => null,
      },
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
