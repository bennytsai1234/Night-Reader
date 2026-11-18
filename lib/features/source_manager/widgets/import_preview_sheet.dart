import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

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

/// 匯入前的底部面板：新增、覆蓋已有的各一個開關，漫畫源、有聲源各一個，
/// 預設都開著，關掉的不匯入（ADR 0051）；無變化與不支援的數量寫在卡片下方。
/// 回傳確認匯入的書源；關掉面板時回傳 null。
Future<List<BookSource>?> showImportPreviewSheet(
  BuildContext context,
  ImportPreviewResult preview,
) {
  var importNew = true;
  var importUpdated = true;
  var importComic = true;
  var importAudio = true;
  final incoming = [...preview.newSources, ...preview.updatedSources];
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
  ].where(keptKind).toList();
  return AppBottomSheet.showCustom<List<BookSource>>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setState) {
        final p = preview;
        final selectedCount = chosen().length;
        final nothing = p.newSources.isEmpty && p.updatedSources.isEmpty;
        // 卡片下方的附註只放數量：跳過的與以停用狀態匯入的。
        final footer = [
          if (p.unchangedSources.isNotEmpty)
            '無變化 ${p.unchangedSources.length} 個，跳過',
          if (p.unsupportedSources.isNotEmpty)
            '夜讀不支援的（影視、文件）${p.unsupportedSources.length} 個，以停用狀態匯入',
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
