import 'package:flutter/material.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'association_base.dart';

/// AssociationHandlerService 的 URI 解析邏輯擴展
/// 支援 legado:// 與 yuedu:// 兩種 scheme (對標 Android OnLineImportActivity)
///
/// legado:// 格式:
///   legado://import/{type}?src={url}  — 匯入書源或替換規則
///   legado://import/addToBookshelf?src={url}  — 加入書架
///
/// yuedu:// 格式 (舊版相容):
///   yuedu://booksource/importonline?src={url}  — 匯入書源
///   yuedu://rsssource/importonline?src={url}   — 匯入 RSS (不支援，忽略)
///   yuedu://replace/importonline?src={url}     — 匯入替換規則
mixin UriAssociationHandler on AssociationBase {
  void handleUri(
    BuildContext context,
    Uri uri,
    Function(BuildContext, String, String) showDialog,
  ) {
    AppLog.d('處理 Deep Link: $uri');

    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'legado') {
      _handleLegadoScheme(context, uri, showDialog);
    } else if (scheme == 'yuedu') {
      _handleYueduScheme(context, uri, showDialog);
    }
  }

  /// 處理 legado:// scheme
  void _handleLegadoScheme(
    BuildContext context,
    Uri uri,
    Function(BuildContext, String, String) showDialog,
  ) {
    final src = uri.queryParameters['src'];
    if (src == null || src.isEmpty) return;

    if (uri.host == 'import') {
      final type = uri.pathSegments.isNotEmpty ? uri.pathSegments[0] : 'auto';
      // 對應 Legado 的 path 映射:
      // /bookSource, /replaceRule, /addToBookshelf
      final mappedType = switch (type) {
        'bookSource' => 'bookSource',
        'replaceRule' => 'replaceRule',
        'addToBookshelf' => 'book',
        _ => 'auto',
      };
      showDialog(context, mappedType, src);
    } else if (uri.host == 'addBook') {
      final url = uri.queryParameters['url'] ?? src;
      showDialog(context, 'book', url);
    }
  }

  /// 處理 yuedu:// scheme (舊版相容)
  /// 格式: yuedu://{host}/importonline?src={url}
  void _handleYueduScheme(
    BuildContext context,
    Uri uri,
    Function(BuildContext, String, String) showDialog,
  ) {
    final src = uri.queryParameters['src'];
    if (src == null || src.isEmpty) return;

    final host = uri.host.toLowerCase();
    final type = switch (host) {
      'booksource' => 'bookSource',
      'replace' => 'replaceRule',
      _ => 'auto',
    };
    showDialog(context, type, src);
  }
}
