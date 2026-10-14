import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

import '../search_provider.dart';

/// 打字時取代結果或搜尋歷史的建議清單：搜尋紀錄與書架上的書名，點一下
/// 就以那個詞搜尋。
class SearchSuggestionView extends StatelessWidget {
  const SearchSuggestionView({
    super.key,
    required this.suggestions,
    required this.onSelected,
  });

  final List<SearchSuggestion> suggestions;
  final ValueChanged<String> onSelected;

  /// 列首圖示寬度 20，文字從 16 + 20 + 14 開始。
  static const double _separatorIndent =
      AppGrouped.rowPadding + 20 + AppGrouped.iconGap;

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final padding = MediaQuery.paddingOf(context);
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(
        top: padding.top,
        bottom: padding.bottom + AppSpacing.xxl,
      ),
      children: [
        GroupedSection(
          topGap: AppSpacing.lg,
          separatorIndent: _separatorIndent,
          children: [
            for (final suggestion in suggestions)
              GroupedRow(
                title: suggestion.word,
                leading: Icon(
                  suggestion.fromBookshelf
                      ? Icons.auto_stories_outlined
                      : Icons.history_rounded,
                  size: 20,
                  color: chrome.sectionText,
                ),
                showChevron: false,
                onTap: () => onSelected(suggestion.word),
              ),
          ],
        ),
      ],
    );
  }
}
