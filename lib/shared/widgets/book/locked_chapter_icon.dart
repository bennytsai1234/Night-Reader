import 'package:flutter/material.dart';

import '../../theme/app_chrome.dart';
import '../skeleton/grouped_list_skeleton.dart';

import 'package:night_reader/core/chinese/ui_language.dart';

/// 目錄列右側的鎖頭：書源標了付費、還沒買的章節，網站只會回付費提示，
/// 也不會下載。顏色同列尾的箭頭。
class LockedChapterIcon extends StatelessWidget implements GroupedSkeletonItem {
  const LockedChapterIcon({super.key});

  static const double _size = 18;

  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) => groupedGlyphShape(_size);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: UiLanguageText.convert(context, '付費章節'),
      child: Icon(
        Icons.lock_outline_rounded,
        size: _size,
        color: AppChrome.of(context).sectionText.withValues(alpha: 0.6),
      ),
    );
  }
}
