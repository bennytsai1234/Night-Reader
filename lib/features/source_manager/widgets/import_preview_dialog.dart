import 'package:flutter/material.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/shared/theme/app_tokens.dart';
import 'package:reader/shared/theme/app_text_styles.dart';
import 'package:reader/shared/theme/context_ext.dart';

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
      newSources.length +
      updatedSources.length +
      unchangedSources.length +
      unsupportedSources.length;

  int get importableTotal =>
      newSources.length + updatedSources.length + unchangedSources.length;

  int get unsupportedCount => unsupportedSources.length;
}

/// Shows a dialog summarizing what will happen if sources are imported.
/// Returns the list of sources the user confirms to import, or null if cancelled.
Future<List<BookSource>?> showImportPreviewDialog(
  BuildContext context,
  ImportPreviewResult preview,
) {
  return showDialog<List<BookSource>>(
    context: context,
    builder: (ctx) => _ImportPreviewDialog(preview: preview),
  );
}

class _ImportPreviewDialog extends StatefulWidget {
  final ImportPreviewResult preview;
  const _ImportPreviewDialog({required this.preview});

  @override
  State<_ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<_ImportPreviewDialog> {
  bool _importNew = true;
  bool _importUpdated = true;

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    return AlertDialog(
      title: const Text('匯入預覽'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '共解析 ${p.total} 個書源',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (p.unsupportedSources.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                '含非小說/不支援來源：${p.unsupportedSources.length} 個（會以停用狀態匯入）',
                style: AppTextStyles.bodyXs.copyWith(color: context.warning),
              ),
            ),
          const SizedBox(height: 12),
          if (p.newSources.isNotEmpty)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('新書源：${p.newSources.length} 個'),
              subtitle: const Text('本地不存在，將新增'),
              value: _importNew,
              onChanged: (v) => setState(() => _importNew = v ?? true),
            ),
          if (p.updatedSources.isNotEmpty)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('已有書源：${p.updatedSources.length} 個'),
              subtitle: const Text('本地已存在，將覆蓋更新'),
              value: _importUpdated,
              onChanged: (v) => setState(() => _importUpdated = v ?? true),
            ),
          if (p.unchangedSources.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                '無變化：${p.unchangedSources.length} 個（跳過）',
                style: AppTextStyles.bodyXs.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            final result = <BookSource>[];
            if (_importNew) result.addAll(p.newSources);
            if (_importUpdated) result.addAll(p.updatedSources);
            Navigator.pop(context, result);
          },
          child: Text(
            '匯入 (${(_importNew ? p.newSources.length : 0) + (_importUpdated ? p.updatedSources.length : 0)})',
          ),
        ),
      ],
    );
  }
}
