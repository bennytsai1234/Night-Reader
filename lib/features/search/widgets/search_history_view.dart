import 'package:flutter/material.dart';
import 'package:night_reader/core/models/search_keyword.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

import '../search_provider.dart';

import 'package:night_reader/shared/widgets/glass.dart';

/// SearchHistoryView - 搜尋歷史顯示元件
/// (對標 Legado SearchActivity 的輸入輔助區域 + HistoryKeyAdapter)
///
/// 功能：
/// - 搜尋歷史關鍵字分組列（按最後使用時間排序）
/// - 長按單條刪除（對標 Legado HistoryKeyAdapter 長按刪除）
/// - 組標題旁「清除」清空全部歷史
class SearchHistoryView extends StatelessWidget {
  final SearchProvider provider;
  final TextEditingController controller;
  final Function(String) onSearch;

  /// 清單最上方的狀態列（篩選狀態、失敗書源等），跟著清單捲動。
  final List<Widget> leading;

  const SearchHistoryView({
    super.key,
    required this.provider,
    required this.controller,
    required this.onSearch,
    this.leading = const [],
  });

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
        ...leading,
        if (provider.historyKeywords.isNotEmpty)
          GroupedSection(
            topGap: AppSpacing.lg,
            header: '搜尋歷史',
            headerTrailing: PlainTextAction(
              label: '清除',
              small: true,
              onPressed: () => _confirmClearHistory(context),
            ),
            separatorIndent: _separatorIndent,
            footer: '長按單筆記錄可刪除。',
            children: [
              for (final keyword in provider.historyKeywords)
                GroupedRow(
                  title: keyword.word,
                  leading: Icon(
                    Icons.history_rounded,
                    size: 20,
                    color: chrome.sectionText,
                  ),
                  showChevron: false,
                  onTap: () {
                    controller.text = keyword.word;
                    onSearch(keyword.word);
                  },
                  onLongPress: () => _confirmDeleteKeyword(context, keyword),
                ),
            ],
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 80),
            child: Column(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 64,
                  color: chrome.sectionText.withValues(alpha: 0.35),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  '開始搜尋你想看的書吧',
                  style: AppTextStyles.bodyBase.copyWith(
                    color: chrome.sectionText,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _confirmDeleteKeyword(
    BuildContext context,
    SearchKeyword keyword,
  ) async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '刪除記錄',
      message: '確定要刪除「${keyword.word}」嗎？',
      confirmLabel: '刪除',
      destructive: true,
    );
    if (confirmed) provider.deleteHistoryKeyword(keyword);
  }

  Future<void> _confirmClearHistory(BuildContext context) async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '清空歷史',
      message: '確定要清空所有搜尋歷史嗎？',
      confirmLabel: '清空',
      destructive: true,
    );
    if (confirmed) provider.clearHistory();
  }
}
