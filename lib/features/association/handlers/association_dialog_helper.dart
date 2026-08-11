import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'association_base.dart';
import 'package:night_reader/core/services/bookshelf_exchange_service.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';
import 'package:night_reader/features/replace_rule/replace_rule_provider.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';

/// AssociationHandlerService 的對話框與 UI 邏輯擴展
mixin AssociationDialogHelper on AssociationBase {
  void showImportDialog(
    BuildContext context,
    String type,
    String src, {
    bool isFile = false,
    String? jsonData,
  }) {
    final displaySource = isFile ? src.split(RegExp(r'[/\\]')).last : src;
    showDialog(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('外部匯入'),
            content: Text(
              '偵測到外部內容：\n$displaySource\n\n'
              '${_typeDescription(type)}',
            ),
            actions: [
              if (type == 'bookSource' || type == 'auto')
                _btn(dialogContext, '匯入書源', () async {
                  final count =
                      isFile
                          ? await SourceImportService().importFromJson(jsonData!)
                          : await SourceImportService().importFromUrl(src);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(count > 0 ? '成功匯入 $count 個書源' : '未匯入有效書源'),
                    ),
                  );
                }),
              if (type == 'book' || type == 'auto')
                _btn(dialogContext, '匯入書架', () async {
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
                    await context.read<BookshelfProvider>().importBookshelfFromUrl(
                      src,
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('書架匯入完成')));
                  }
                }),
              if (type == 'replaceRule' || type == 'auto')
                _btn(dialogContext, '匯入替換規則', () async {
                  final text =
                      isFile
                          ? jsonData!
                          : await SourceImportService().fetchImportTextFromUrl(src);
                  final count = await context
                      .read<ReplaceRuleProvider>()
                      .importFromText(text);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(count > 0 ? '成功匯入 $count 個替換規則' : '未匯入有效替換規則'),
                    ),
                  );
                }),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
            ],
          ),
    );
  }

  void showForceImportDialog(BuildContext context, String path) {
    showDialog(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('無法辨識檔案'),
            content: Text(
              '「${path.split(RegExp(r'[/\\]')).last}」不是可辨識的 Night Reader 匯入格式。',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('關閉'),
              ),
            ],
          ),
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

  Widget _btn(
    BuildContext dialogContext,
    String label,
    Future<void> Function() action,
  ) => TextButton(
    onPressed: () async {
      Navigator.pop(dialogContext);
      try {
        await action();
      } catch (error) {
        // 各匯入流程會在成功時自行提示；意外失敗統一回報。
        if (dialogContext.mounted) {
          ScaffoldMessenger.of(dialogContext).showSnackBar(
            SnackBar(content: Text('$label失敗：$error')),
          );
        }
      }
    },
    child: Text(label),
  );
}
// AI_PORT: GAP-INTENT-01 extracted from AssociationHandlerService
