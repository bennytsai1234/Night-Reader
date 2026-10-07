import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';

class ImportPreviewResult {
  final List<BookSource> newSources;
  final List<BookSource> updatedSources;
  final List<BookSource> unchangedSources;
  final List<BookSource> unsupportedSources;

  ImportPreviewResult({
    required this.newSources,
    required this.updatedSources,
    required this.unchangedSources,
    this.unsupportedSources = const <BookSource>[],
  });

  int get total =>
      newSources.length + updatedSources.length + unchangedSources.length;

  int get importableTotal =>
      newSources.length + updatedSources.length + unchangedSources.length;

  int get unsupportedCount => unsupportedSources.length;
}

/// 顯示匯入預覽：列出新增、更新、無變化與不支援的數量，讓使用者勾選要
/// 匯入的類別。回傳確認匯入的書源；取消時回傳 null。
Future<List<BookSource>?> showImportPreviewDialog(
  BuildContext context,
  ImportPreviewResult preview,
) {
  var importNew = true;
  var importUpdated = true;
  return showStatefulAppAlert<List<BookSource>>(
    context: context,
    builder: (dialogContext, setState, _) {
      final p = preview;
      final chrome = AppChrome.of(dialogContext);
      final scheme = Theme.of(dialogContext).colorScheme;
      final selectedCount =
          (importNew ? p.newSources.length : 0) +
          (importUpdated ? p.updatedSources.length : 0);
      return AppAlert<bool>(
        title: '匯入預覽',
        message: '共解析 ${p.total} 個書源',
        onAction: (confirmed) {
          if (!confirmed) {
            Navigator.pop(dialogContext);
            return;
          }
          final result = <BookSource>[];
          if (importNew) result.addAll(p.newSources);
          if (importUpdated) result.addAll(p.updatedSources);
          Navigator.pop(dialogContext, result);
        },
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (p.unsupportedSources.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  '含非小說/不支援來源：${p.unsupportedSources.length} 個（新增或更新時會以停用狀態匯入）',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySm.copyWith(
                    color: dialogContext.warning,
                  ),
                ),
              ),
            if (p.newSources.isNotEmpty)
              AlertCheckRow(
                title: '新書源：${p.newSources.length} 個',
                subtitle: '本地不存在，將新增',
                value: importNew,
                onChanged: (v) => setState(() => importNew = v),
              ),
            if (p.updatedSources.isNotEmpty)
              AlertCheckRow(
                title: '已有書源：${p.updatedSources.length} 個',
                subtitle: '本地已存在，將覆蓋更新',
                value: importUpdated,
                onChanged: (v) => setState(() => importUpdated = v),
              ),
            if (p.unchangedSources.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  '無變化：${p.unchangedSources.length} 個（跳過）',
                  style: AppTextStyles.bodySm.copyWith(
                    color: chrome.sectionText,
                  ),
                ),
              ),
            if (p.newSources.isEmpty && p.updatedSources.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  '沒有需要匯入的變更',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySm.copyWith(color: scheme.onSurface),
                ),
              ),
          ],
        ),
        actions: [
          const AppAlertAction(label: '取消', value: false),
          AppAlertAction(
            label: '匯入 ($selectedCount)',
            value: true,
            isDefault: true,
            enabled: selectedCount > 0,
          ),
        ],
      );
    },
  );
}
