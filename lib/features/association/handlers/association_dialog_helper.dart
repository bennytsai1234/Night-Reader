import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'association_base.dart';
import 'package:reader/features/source_manager/source_manager_provider.dart';
import 'package:reader/features/replace_rule/replace_rule_provider.dart';
import 'package:reader/features/bookshelf/bookshelf_provider.dart';

/// AssociationHandlerService 的對話框與 UI 邏輯擴展
mixin AssociationDialogHelper on AssociationBase {
  void showImportDialog(
    BuildContext context,
    String type,
    String src, {
    bool isFile = false,
    String? jsonData,
  }) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('外部匯入'),
            content: Text(
              '偵測到外部內容：\n${isFile ? src.split('/').last : src}\n\n辨識類型：$type',
            ),
            actions: [
              _btn(ctx, '書源', () async {
                final count =
                    isFile
                        ? await SourceImportService().importFromJson(jsonData!)
                        : await SourceImportService().importFromUrl(src);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(count > 0 ? '成功匯入 $count 個書源' : '未匯入有效書源'),
                    ),
                  );
                }
              }),
              if (type == 'book' || type == 'auto')
                _btn(
                  ctx,
                  '書籍',
                  () async => context
                      .read<BookshelfProvider>()
                      .importBookshelfFromUrl(src),
                ),
              if (type == 'replaceRule' || type == 'auto')
                _btn(ctx, '替換規則', () async {
                  if (isFile) {
                    context.read<ReplaceRuleProvider>().importFromText(
                      jsonData!,
                    );
                  }
                }),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
            ],
          ),
    );
  }

  void showForceImportDialog(
    BuildContext context,
    String path,
    Function(BuildContext, String) handleBook,
  ) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('格式不支援'),
            content: const Text('無法辨識此 JSON 內容，是否嘗試作為書籍導入？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  handleBook(context, path);
                },
                child: const Text('嘗試導入書籍'),
              ),
            ],
          ),
    );
  }

  Widget _btn(
    BuildContext context,
    String label,
    Future<void> Function() action,
  ) => TextButton(
    onPressed: () async {
      Navigator.pop(context);
      await action();
    },
    child: Text('匯入為 $label'),
  );
}
// AI_PORT: GAP-INTENT-01 extracted from AssociationHandlerService
