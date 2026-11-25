import 'package:flutter/material.dart';

import '../../theme/app_chrome.dart';
import '../../theme/app_tokens.dart';

/// Telegram 編輯模式的圓形勾選：選中為主色實心圈加白勾，未選為髮絲空心圈。
class SelectionCircle extends StatelessWidget {
  const SelectionCircle({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedContainer(
        duration: AppMotion.menu,
        curve: AppMotion.menuCurve,
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? scheme.primary : Colors.transparent,
          border: Border.all(
            color: selected ? scheme.primary : chrome.sectionText,
            width: 1.5,
          ),
        ),
        child: selected
            ? Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary)
            : null,
      ),
    );
  }
}
