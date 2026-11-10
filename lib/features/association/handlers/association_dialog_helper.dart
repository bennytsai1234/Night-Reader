import 'dart:async';
import 'dart:convert';

import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../import_content.dart';
import 'association_base.dart';

import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/services/bookshelf_exchange_service.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';

/// AssociationHandlerService 的對話框與 UI 邏輯擴展
mixin AssociationDialogHelper on AssociationBase {
  @override
  void showLinkImportDialog(
    BuildContext context,
    ImportContentKind kind,
    String url,
  ) {
    unawaited(_runImportDialog(context, kind, url, url: url));
  }

  @override
  Future<void> importUntypedLink(BuildContext context, String url) async {
    final String text;
    try {
      text = await SourceImportService().fetchImportTextFromUrl(url);
    } catch (error, stackTrace) {
      final message = failureMessage('讀取匯入內容', error, stackTrace);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    if (!context.mounted) return;
    importContent(context, url, text);
  }

  @override
  void importContent(BuildContext context, String label, String text) {
    final kind = detectImportContentKind(text);
    if (kind == null) {
      showAppAlert<void>(
        context: context,
        title: '無法辨識',
        message: '「$label」不是夜讀能匯入的格式。',
        actions: const [
          AppAlertAction(label: '關閉', value: null, isDefault: true),
        ],
      );
      return;
    }
    unawaited(_runImportDialog(context, kind, label, text: text));
  }

  /// 問要不要匯入，按下後才匯入。[text] 是已經拿到的內容；沒有時（類型寫在
  /// 連結上）按下才從 [url] 下載。
  Future<void> _runImportDialog(
    BuildContext context,
    ImportContentKind kind,
    String label, {
    String? url,
    String? text,
  }) async {
    final action = switch (kind) {
      ImportContentKind.bookSource => '匯入書源',
      ImportContentKind.replaceRule => '匯入替換規則',
      ImportContentKind.bookshelf => '匯入書架',
      ImportContentKind.rssSource || ImportContentKind.theme => null,
    };
    final confirmed = await showAppAlert<bool>(
      context: context,
      title: '外部匯入',
      message: '偵測到外部內容：\n$label\n\n${kind.description}',
      actions: [
        if (action != null)
          AppAlertAction(label: action, value: true, isDefault: true),
        const AppAlertAction(label: '取消', value: false),
      ],
    );
    if (confirmed != true || action == null || !context.mounted) return;

    try {
      // 逐步呼叫會丟出原因的方法（網址、HTTP、JSON 錯誤），交給外層顯示
      // 「匯入書源失敗：原因」。
      final service = SourceImportService();
      final content = normalizeImportJson(
        text ?? await service.fetchImportTextFromUrl(url!),
      );
      final String message;
      switch (kind) {
        case ImportContentKind.bookSource:
          final parsed = await service.parseSourcesDetailedAsync(content);
          final count = await service.importSources(parsed.allSources);
          // 和書源管理的匯入同一套說法：夜讀不支援的書源會匯入但停用。
          final unsupportedCount = parsed.unsupportedSources.length;
          message = count == 0
              ? '未匯入有效書源'
              : unsupportedCount > 0
              ? '成功匯入 $count 個書源，其中 $unsupportedCount 個已標記為不支援並停用'
              : '成功匯入 $count 個書源';
        case ImportContentKind.bookshelf:
          final result = await BookshelfExchangeService().importFromText(
            content,
          );
          if (!context.mounted) return;
          await context.read<BookshelfProvider>().loadBooks();
          final total =
              result.books + result.chapters + result.sources + result.contents;
          message = total > 0
              ? '已匯入 ${result.books} 本書、${result.chapters} 個章節'
              : '未找到可匯入的書架資料';
        case ImportContentKind.replaceRule:
          final count = await _importReplaceRules(content);
          message = count > 0 ? '成功匯入 $count 個替換規則' : '未匯入有效替換規則';
        case ImportContentKind.rssSource || ImportContentKind.theme:
          return;
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failureMessage(action, error))));
    }
  }

  Future<int> _importReplaceRules(String text) async {
    final decoded = jsonDecode(text);
    // 單一規則的匯出是一個物件，辨識時也當成替換規則，這裡一併接受。
    final items = decoded is Map
        ? [decoded]
        : decoded is List
        ? decoded
        : throw const FormatException('替換規則格式不正確');
    final dao = getIt<ReplaceRuleDao>();
    var count = 0;
    for (final item in items) {
      if (item is! Map) continue;
      final rule = ReplaceRule.fromJson(Map<String, dynamic>.from(item));
      // 空的或正則寫錯的規則不寫入，也不算進成功數。
      if (!rule.isValid()) continue;
      await dao.upsert(rule);
      count += 1;
    }
    return count;
  }
}
// AI_PORT: GAP-INTENT-01 extracted from AssociationHandlerService
