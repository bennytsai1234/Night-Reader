import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reader/shared/theme/app_tokens.dart';
import 'package:reader/shared/theme/app_text_styles.dart';
import 'explore_show_provider.dart';
import 'widgets/explore_book_item.dart';

/// ExploreShowPage - 探索結果列表頁面
/// (對標 Android ExploreShowActivity)
///
/// 顯示某個書源的某個分類下的書籍列表，支援無限滾動加載。
class ExploreShowPage extends StatelessWidget {
  final String sourceUrl;
  final String exploreUrl;
  final String exploreName;

  const ExploreShowPage({
    super.key,
    required this.sourceUrl,
    required this.exploreUrl,
    required this.exploreName,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create:
          (_) => ExploreShowProvider(
            sourceUrl: sourceUrl,
            exploreUrl: exploreUrl,
            exploreName: exploreName,
          ),
      child: _ExploreShowContent(exploreName: exploreName),
    );
  }
}

class _ExploreShowContent extends StatelessWidget {
  final String exploreName;

  const _ExploreShowContent({required this.exploreName});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExploreShowProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(exploreName)),
      body: _buildBody(context, provider),
    );
  }

  Widget _buildBody(BuildContext context, ExploreShowProvider provider) {
    // 初始載入中
    if (provider.isLoading && provider.books.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // 錯誤且無數據
    if (provider.errorMessage != null && provider.books.isEmpty) {
      return _buildStatePanel(
        context,
        icon: Icons.error_outline,
        message: '分類載入失敗',
        detail: provider.errorMessage,
        actions: [
          TextButton.icon(
            onPressed:
                () => _showErrorDialog(context, provider.errorMessage ?? ''),
            icon: const Icon(Icons.info_outline),
            label: const Text('查看錯誤'),
          ),
          FilledButton.icon(
            onPressed: () => provider.refresh(),
            icon: const Icon(Icons.refresh),
            label: const Text('重試'),
          ),
        ],
      );
    }

    // 空數據
    if (provider.isEmpty) {
      return _buildStatePanel(
        context,
        icon: Icons.inbox_outlined,
        message: '暫無內容',
        actions: [
          FilledButton.icon(
            onPressed: () => provider.refresh(),
            icon: const Icon(Icons.refresh),
            label: const Text('重新整理'),
          ),
        ],
      );
    }

    // 書籍列表 (對標 Android ExploreShowActivity RecyclerView)
    return RefreshIndicator(
      onRefresh: () => provider.refresh(),
      child: ListView.builder(
        itemCount: provider.books.length + (provider.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == provider.books.length) {
            // LoadMore 指示器 (對標 Android LoadMoreView)
            provider.loadMore();
            return _buildLoadMoreIndicator(context, provider);
          }
          return ExploreBookItem(
            book: provider.books[index],
            isInBookshelf: provider.isInBookshelf(provider.books[index]),
            sourceName: exploreName,
          );
        },
      ),
    );
  }

  /// 載入更多指示器 (對標 Android LoadMoreView)
  Widget _buildLoadMoreIndicator(
    BuildContext context,
    ExploreShowProvider provider,
  ) {
    if (provider.errorMessage != null) {
      return InkWell(
        onTap: () => provider.loadMore(),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          alignment: Alignment.center,
          child: Text(
            '載入失敗，點擊重試',
            style: AppTextStyles.bodyXs.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      );
    }

    return const Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildStatePanel(
    BuildContext context, {
    required IconData icon,
    required String message,
    String? detail,
    required List<Widget> actions,
  }) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 52, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            if (detail != null && detail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('錯誤原因'),
            content: SelectableText(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('關閉'),
              ),
            ],
          ),
    );
  }
}
