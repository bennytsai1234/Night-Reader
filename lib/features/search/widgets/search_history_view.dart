import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';
import 'package:night_reader/core/models/search/ai_find_record.dart';
import 'package:night_reader/core/models/search/search_keyword.dart';
import 'package:night_reader/shared/layout/readable_width.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/popups/app_dialogs.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';

import '../ai_find/ai_find_page.dart';
import '../search_provider.dart';

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
      padding:
          EdgeInsets.only(
            top: padding.top,
            bottom: padding.bottom + AppGrouped.sectionGap,
          ) +
          ReadableWidth.insetOf(context),
      children: GroupedListView.itemsOf([
        ...leading,
        if (provider.pastFinds.isNotEmpty)
          GroupedSection(
            separatorIndent: _separatorIndent,
            children: [
              for (final find in provider.pastFinds)
                GroupedRow(
                  title: find.description,
                  translateTitle: false,
                  maxTitleLines: 1,
                  leading: Icon(
                    Icons.auto_awesome_outlined,
                    size: 20,
                    color: chrome.sectionText,
                  ),
                  // 同一筆在列的字沒變時不重建，報告照 id 拿最新讀到的。
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AiFindPage(
                        record: provider.pastFindById(find.id) ?? find,
                      ),
                    ),
                  ),
                  onLongPress: () => _confirmDeleteFind(context, find),
                ),
            ],
          ),
        if (provider.historyKeywords.isNotEmpty)
          GroupedSection(
            separatorIndent: _separatorIndent,
            children: [
              for (final keyword in provider.historyKeywords)
                GroupedRow(
                  translateTitle: false,
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
              GroupedRow(
                leading: Icon(
                  Icons.delete_sweep_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: '清除搜尋紀錄',
                accent: true,
                showChevron: false,
                onTap: () => _confirmClearHistory(context),
              ),
            ],
          )
        // 還在讀紀錄時不畫「沒有紀錄」的空頁（開 App 後還沒讀到就點進來）。
        else if (provider.historyLoaded && provider.pastFinds.isEmpty)
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
                UiText(
                  '開始搜尋你想看的書吧',
                  style: AppTextStyles.bodyBase.copyWith(
                    color: chrome.sectionText,
                  ),
                ),
              ],
            ),
          ),
      ]),
    );
  }

  Future<void> _confirmDeleteKeyword(
    BuildContext context,
    SearchKeyword keyword,
  ) async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '刪除搜尋紀錄「${keyword.word}」？',
      confirmLabel: '刪除',
      destructive: true,
    );
    if (confirmed) unawaited(provider.deleteHistoryKeyword(keyword));
  }

  Future<void> _confirmDeleteFind(
    BuildContext context,
    AiFindRecord find,
  ) async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '刪除這筆找書紀錄？',
      message: find.description,
      translateMessage: false,
      confirmLabel: '刪除',
      destructive: true,
    );
    if (confirmed) unawaited(provider.deletePastFind(find));
  }

  Future<void> _confirmClearHistory(BuildContext context) async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '清空所有搜尋紀錄？',
      confirmLabel: '清空',
      destructive: true,
    );
    if (confirmed) unawaited(provider.clearHistory());
  }
}
