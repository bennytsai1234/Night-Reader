import 'package:flutter/material.dart';
import 'package:night_reader/core/fonts/app_font.dart';
import 'package:night_reader/core/fonts/font_library.dart';

import 'app_dialogs.dart';
import 'grouped_list.dart';
import 'grouped_list_skeleton.dart';

/// 選字型的一列（ADR 0045）：右側寫目前的字型，下載中寫進度、失敗寫
/// 「下載失敗」。點開是字型清單，還沒下載的寫出要下載多大；選了由
/// [onChanged] 存下並開始下載（[FontLibrary.ensure]）。「閱讀偏好」的正文字型
/// 與「外觀與主題」的介面字型共用。
class AppFontPickerRow extends StatelessWidget implements GroupedSkeletonItem {
  const AppFontPickerRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.library,
  });

  final String title;
  final AppFont value;
  final ValueChanged<AppFont> onChanged;

  /// null 時用 [FontLibrary.instance]。
  final FontLibrary? library;

  FontLibrary get _library => library ?? FontLibrary.instance;

  GroupedRow _row(BuildContext context, FontStatus status) => GroupedRow(
    title: title,
    value: switch (status) {
      FontDownloading(:final progress) =>
        '${value.label}　下載中 ${(progress * 100).floor()}%',
      FontFailed() => '${value.label}　下載失敗',
      FontMissing() || FontReady() => value.label,
    },
    onTap: () => _showPicker(context),
  );

  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) => _row(
    context,
    _library.status(value).value,
  ).skeletonShape(context, width: width);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<FontStatus>(
    valueListenable: _library.status(value),
    builder: (context, status, _) => _row(context, status),
  );

  Future<void> _showPicker(BuildContext context) async {
    final picked = await showAppActionSheet<AppFont>(
      context: context,
      title: title,
      actions: [
        for (final font in AppFont.values)
          AppSheetAction(
            label: font.label,
            value: font,
            subtitle: switch ((font.file, _library.status(font).value)) {
              (null, _) || (_, FontReady()) => null,
              (_, FontDownloading()) => '下載中',
              (final file?, _) => '選了會下載 ${file.sizeLabel}',
            },
            selected: font == value,
          ),
      ],
    );
    if (picked == null) return;
    // 同一套再選一次：上次下載失敗時再試。
    if (picked == value) {
      if (_library.status(picked).value is FontFailed) {
        await _library.ensure(picked);
      }
      return;
    }
    onChanged(picked);
  }
}
