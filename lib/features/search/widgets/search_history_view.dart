import 'package:flutter/material.dart';
import 'package:reader/shared/theme/app_tokens.dart';
import '../search_provider.dart';

/// SearchHistoryView - 搜尋歷史顯示元件
/// (對標 Legado SearchActivity 的輸入輔助區域 + HistoryKeyAdapter)
///
/// 功能：
/// - 搜尋歷史關鍵字展示（按最後使用時間排序）
/// - 長按單條刪除（對標 Legado HistoryKeyAdapter 長按刪除）
/// - 清空全部歷史
class SearchHistoryView extends StatelessWidget {
  final SearchProvider provider;
  final TextEditingController controller;
  final Function(String) onSearch;

  const SearchHistoryView({
    super.key,
    required this.provider,
    required this.controller,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (provider.historyKeywords.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '搜尋歷史',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              TextButton(
                onPressed: () => _confirmClearHistory(context),
                child: Text(
                  '清空',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                provider.historyKeywords.map((keyword) {
                  return GestureDetector(
                    onLongPress: () => _confirmDeleteKeyword(context, keyword),
                    child: ActionChip(
                      label: Text(keyword.word),
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      onPressed: () {
                        controller.text = keyword.word;
                        onSearch(keyword.word);
                      },
                    ),
                  );
                }).toList(),
          ),
        ],
        if (provider.historyKeywords.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Column(
                children: [
                  Icon(
                    Icons.search,
                    size: 64,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '開始搜尋你想看的書吧',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _confirmDeleteKeyword(BuildContext context, dynamic keyword) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('刪除記錄'),
            content: Text('確定要刪除「${keyword.word}」嗎？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  provider.deleteHistoryKeyword(keyword);
                  Navigator.pop(ctx);
                },
                child: const Text('刪除'),
              ),
            ],
          ),
    );
  }

  void _confirmClearHistory(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('清空歷史'),
            content: const Text('確定要清空所有搜尋歷史嗎？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  provider.clearHistory();
                  Navigator.pop(ctx);
                },
                child: const Text('確定'),
              ),
            ],
          ),
    );
  }
}
