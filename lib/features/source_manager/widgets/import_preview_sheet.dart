import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/ui_text.dart';

class ImportPreviewResult {
  final List<BookSource> newSources;

  /// 檔案裡比這台新的（更新時間較晚）：預設覆蓋。
  final List<BookSource> updatedSources;

  /// 檔案裡比這台舊的：這台的多半是改過或修好的，預設不覆蓋。
  final List<BookSource> olderSources;
  final List<BookSource> unchangedSources;

  ImportPreviewResult({
    required this.newSources,
    required this.updatedSources,
    this.olderSources = const <BookSource>[],
    required this.unchangedSources,
  });

  int get total =>
      newSources.length +
      updatedSources.length +
      olderSources.length +
      unchangedSources.length;
}

/// 匯入書源都走這一段：解析 [json]、開匯入預覽、匯入選的、從底部提示結果。
/// 書源管理的網址、本地檔、剪貼簿，與從外部打開的檔案、連結共用（同 Legado
/// 都開 ImportBookSourceDialog）。[importer] 給了就用它寫入（書源管理寫完要
/// 重讀清單）。解析或寫入出錯照樣丟出，由呼叫的地方提示。
Future<void> importSourcesWithPreview(
  BuildContext context,
  String json, {
  SourceImportService? service,
  Future<SourceImportCount> Function(List<BookSource> sources)? importer,
}) async {
  final importService = service ?? SourceImportService();
  final messenger = ScaffoldMessenger.of(context);
  final parsed = await importService.parseSourcesDetailedAsync(json);
  if (!context.mounted) return;
  if (parsed.allSources.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: UiText('未解析到有效書源')));
    return;
  }
  final preview = await importService.previewImport(parsed.allSources);
  if (!context.mounted) return;
  final chosen = await showImportPreviewSheet(context, preview);
  if (chosen == null || chosen.isEmpty) return;
  final count = await (importer ?? importService.importSources)(chosen);
  final unsupported = chosen
      .where((source) => source.sourceKind == BookSourceKind.unsupported)
      .length;
  messenger.showSnackBar(
    SnackBar(
      content: UiText(sourceImportMessage(count, unsupported: unsupported)),
    ),
  );
}

/// 匯入前的底部面板：新增、覆蓋已有的各一個開關，漫畫源、有聲源各一個，
/// 預設都開著，關掉的不匯入（ADR 0051）；檔案裡比這台舊的另一個開關，預設
/// 關著（同 Legado 不預先勾「已有」）。無變化與不支援的數量寫在卡片下方。
/// 回傳確認匯入的書源；關掉面板時回傳 null。
Future<List<BookSource>?> showImportPreviewSheet(
  BuildContext context,
  ImportPreviewResult preview,
) {
  var importNew = true;
  var importUpdated = true;
  var importOlder = false;
  var importComic = true;
  var importAudio = true;
  final incoming = [
    ...preview.newSources,
    ...preview.updatedSources,
    ...preview.olderSources,
  ];
  final comicCount = incoming
      .where((s) => s.sourceKind == BookSourceKind.comic)
      .length;
  final audioCount = incoming
      .where((s) => s.sourceKind == BookSourceKind.audio)
      .length;
  bool keptKind(BookSource source) => switch (source.sourceKind) {
    BookSourceKind.comic => importComic,
    BookSourceKind.audio => importAudio,
    _ => true,
  };
  List<BookSource> chosen() => [
    if (importNew) ...preview.newSources,
    if (importUpdated) ...preview.updatedSources,
    if (importOlder) ...preview.olderSources,
  ].where(keptKind).toList();
  return AppBottomSheet.showCustom<List<BookSource>>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setState) {
        final p = preview;
        final selected = chosen();
        final selectedCount = selected.length;
        final unsupported = selected
            .where((s) => s.sourceKind == BookSourceKind.unsupported)
            .length;
        final nothing = incoming.isEmpty;
        // 卡片下方的附註只放數量：跳過的與選了、以停用狀態匯入的。
        final footer = [
          if (p.unchangedSources.isNotEmpty)
            '無變化 ${p.unchangedSources.length} 個，跳過',
          if (unsupported > 0) '夜讀不支援的（影視、文件）$unsupported 個，以停用狀態匯入',
        ].join('\n');
        return AppBottomSheet(
          title: '匯入 ${p.total} 個書源',
          trailing: GlassTextButton(
            label: selectedCount == 0 ? '匯入' : '匯入 $selectedCount 個',
            emphasized: true,
            onPressed: selectedCount == 0
                ? null
                : () => Navigator.pop(sheetContext, chosen()),
          ),
          children: [
            GroupedSection(
              margin: EdgeInsets.zero,
              topGap: AppSpacing.md,
              footer: footer.isEmpty ? null : footer,
              children: [
                if (nothing)
                  const GroupedRow(title: '沒有需要匯入的變更', showChevron: false),
                if (p.newSources.isNotEmpty)
                  GroupedSwitchRow(
                    title: '新增 ${p.newSources.length} 個',
                    value: importNew,
                    onChanged: (v) => setState(() => importNew = v),
                  ),
                if (p.updatedSources.isNotEmpty)
                  GroupedSwitchRow(
                    title: '覆蓋已有的 ${p.updatedSources.length} 個',
                    value: importUpdated,
                    onChanged: (v) => setState(() => importUpdated = v),
                  ),
                if (p.olderSources.isNotEmpty)
                  GroupedSwitchRow(
                    title: '換成檔案裡較舊的 ${p.olderSources.length} 個',
                    value: importOlder,
                    onChanged: (v) => setState(() => importOlder = v),
                  ),
              ],
            ),
            if (comicCount > 0 || audioCount > 0)
              GroupedSection(
                margin: EdgeInsets.zero,
                header: '書源類型',
                children: [
                  if (comicCount > 0)
                    GroupedSwitchRow(
                      title: '漫畫源 $comicCount 個',
                      value: importComic,
                      onChanged: (v) => setState(() => importComic = v),
                    ),
                  if (audioCount > 0)
                    GroupedSwitchRow(
                      title: '有聲源 $audioCount 個',
                      value: importAudio,
                      onChanged: (v) => setState(() => importAudio = v),
                    ),
                ],
              ),
          ],
        );
      },
    ),
  );
}
