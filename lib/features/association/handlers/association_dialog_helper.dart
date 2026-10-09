import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'association_base.dart';

import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/services/bookshelf_exchange_service.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';

/// 外部匯入對話框可選的匯入方式。
enum _ImportKind { bookSource, bookshelf, replaceRule }

/// AssociationHandlerService 的對話框與 UI 邏輯擴展
mixin AssociationDialogHelper on AssociationBase {
  void showImportDialog(
    BuildContext context,
    String type,
    String src, {
    bool isFile = false,
    String? jsonData,
  }) {
    unawaited(
      _runImportDialog(context, type, src, isFile: isFile, jsonData: jsonData),
    );
  }

  Future<void> _runImportDialog(
    BuildContext context,
    String type,
    String src, {
    required bool isFile,
    String? jsonData,
  }) async {
    final displaySource = isFile ? src.split(RegExp(r'[/\\]')).last : src;
    final isAuto = type == 'auto';
    final kind = await showAppAlert<_ImportKind?>(
      context: context,
      title: '外部匯入',
      message: '偵測到外部內容：\n$displaySource\n\n${_typeDescription(type)}',
      actions: [
        if (type == 'bookSource' || isAuto)
          const AppAlertAction(
            label: '匯入書源',
            value: _ImportKind.bookSource,
            isDefault: true,
          ),
        if (type == 'book' || isAuto)
          AppAlertAction(
            label: '匯入書架',
            value: _ImportKind.bookshelf,
            isDefault: !isAuto,
          ),
        if (type == 'replaceRule' || isAuto)
          AppAlertAction(
            label: '匯入替換規則',
            value: _ImportKind.replaceRule,
            isDefault: !isAuto,
          ),
        const AppAlertAction(label: '取消', value: null),
      ],
    );
    if (kind == null || !context.mounted) return;

    final label = switch (kind) {
      _ImportKind.bookSource => '匯入書源',
      _ImportKind.bookshelf => '匯入書架',
      _ImportKind.replaceRule => '匯入替換規則',
    };
    try {
      switch (kind) {
        case _ImportKind.bookSource:
          final count = isFile
              ? await SourceImportService().importFromJson(jsonData!)
              : await SourceImportService().importFromUrl(src);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(count > 0 ? '成功匯入 $count 個書源' : '未匯入有效書源')),
          );
        case _ImportKind.bookshelf:
          if (isFile) {
            final result = await BookshelfExchangeService().importFromFile(
              File(src),
            );
            if (!context.mounted) return;
            await context.read<BookshelfProvider>().loadBooks();
            if (!context.mounted) return;
            final total =
                result.books +
                result.chapters +
                result.sources +
                result.contents;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  total > 0
                      ? '已匯入 ${result.books} 本書、${result.chapters} 個章節'
                      : '未找到可匯入的書架資料',
                ),
              ),
            );
          } else {
            await context.read<BookshelfProvider>().importBookshelfFromUrl(src);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('書架匯入完成')));
          }
        case _ImportKind.replaceRule:
          final text = isFile
              ? jsonData!
              : await SourceImportService().fetchImportTextFromUrl(src);
          final count = await _importReplaceRules(text);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(count > 0 ? '成功匯入 $count 個替換規則' : '未匯入有效替換規則'),
            ),
          );
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$label失敗：$error')));
    }
  }

  Future<int> _importReplaceRules(String text) async {
    final decoded = jsonDecode(text);
    if (decoded is! List) {
      throw const FormatException('替換規則格式不正確');
    }
    final dao = getIt<ReplaceRuleDao>();
    var count = 0;
    for (final item in decoded) {
      if (item is! Map) continue;
      final rule = ReplaceRule.fromJson(Map<String, dynamic>.from(item));
      await dao.upsert(rule);
      count += 1;
    }
    return count;
  }

  void showForceImportDialog(BuildContext context, String path) {
    showAppAlert<void>(
      context: context,
      title: '無法辨識檔案',
      message:
          '「${path.split(RegExp(r'[/\\]')).last}」不是可辨識的 Night Reader 匯入格式。',
      actions: const [
        AppAlertAction(label: '關閉', value: null, isDefault: true),
      ],
    );
  }

  String _typeDescription(String type) {
    return switch (type) {
      'bookSource' => '辨識為書源資料',
      'replaceRule' => '辨識為替換規則',
      'book' => '辨識為書架資料',
      'theme' => '辨識為閱讀主題，但目前沒有可用的主題匯入流程',
      _ => '無法自動判斷類型，請選擇要使用的匯入方式',
    };
  }
}
// AI_PORT: GAP-INTENT-01 extracted from AssociationHandlerService
