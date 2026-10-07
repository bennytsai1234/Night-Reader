import 'package:flutter/material.dart';

import '../theme/app_chrome.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_tokens.dart';
import 'glass.dart';

/// Telegram 式圓角搜尋框：左側放大鏡、有字時右側出現清除鈕。
///
/// 預設為淡墨填色底（放在面板、頁首玻璃上）；浮在捲動內容上方時傳
/// `glass: true` 改用玻璃底。
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    this.hintText = '搜尋',
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.textInputAction = TextInputAction.search,
    this.glass = false,
  });

  static const double height = 36.0;

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;
  final TextInputAction textInputAction;

  /// 以玻璃膠囊取代填色底。
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    final muted = chrome.sectionText;
    final content = Row(
      children: [
        const SizedBox(width: AppSpacing.md),
        Icon(Icons.search_rounded, size: 19, color: muted),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: autofocus,
            textInputAction: textInputAction,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            style: AppTextStyles.bodyBase.copyWith(
              height: 1.25,
              color: scheme.onSurface,
            ),
            decoration: InputDecoration(
              isCollapsed: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: hintText,
              hintStyle: AppTextStyles.bodyBase.copyWith(
                height: 1.25,
                color: muted.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            if (value.text.isEmpty) {
              return const SizedBox(width: AppSpacing.md);
            }
            return Semantics(
              button: true,
              label: '清除',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  controller.clear();
                  onChanged?.call('');
                },
                child: SizedBox(
                  width: height,
                  height: height,
                  child: Icon(Icons.cancel_rounded, size: 17, color: muted),
                ),
              ),
            );
          },
        ),
      ],
    );
    return SizedBox(
      height: height,
      child:
          glass
              ? GlassSurface(
                borderRadius: AppRadius.pillShape,
                shadow: false,
                child: content,
              )
              : DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(
                    alpha:
                        Theme.of(context).brightness == Brightness.dark
                            ? 0.1
                            : 0.07,
                  ),
                  borderRadius: AppRadius.pillShape,
                ),
                child: content,
              ),
    );
  }
}
