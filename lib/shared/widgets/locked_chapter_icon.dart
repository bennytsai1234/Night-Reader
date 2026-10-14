import 'package:flutter/material.dart';

import '../theme/app_chrome.dart';

/// 目錄列右側的鎖頭：書源標了付費、還沒買的章節，網站只會回付費提示，
/// 也不會下載。顏色同列尾的箭頭。
class LockedChapterIcon extends StatelessWidget {
  const LockedChapterIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '付費章節',
      child: Icon(
        Icons.lock_outline_rounded,
        size: 18,
        color: AppChrome.of(context).sectionText.withValues(alpha: 0.6),
      ),
    );
  }
}
