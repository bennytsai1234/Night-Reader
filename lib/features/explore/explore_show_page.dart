import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

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
      create: (_) => ExploreShowProvider(
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
      extendBodyBehindAppBar: true,
      appBar: GlassNavHeader(title: exploreName),
      // 從 Scaffold 內取內距，top 才包含延伸到下方的頁首高度。
      body: Builder(
        builder: (bodyContext) => _buildBody(bodyContext, provider),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ExploreShowProvider provider) {
    final padding = MediaQuery.paddingOf(context);
    Widget padState(Widget child) => Padding(
      padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
      child: child,
    );

    if (provider.isLoading && provider.books.isEmpty) {
      return padState(const Center(child: CircularProgressIndicator()));
    }

    if (provider.errorMessage != null && provider.books.isEmpty) {
      return padState(
        AppStateView(
          icon: Icons.error_outline,
          title: '分類載入失敗',
          description: provider.errorMessage,
          tone: AppStateTone.error,
          primaryAction: AppStateAction(
            label: '重試',
            icon: Icons.refresh,
            onPressed: provider.refresh,
          ),
          secondaryAction: AppStateAction(
            label: '查看錯誤',
            icon: Icons.info_outline,
            onPressed: () =>
                _showErrorDialog(context, provider.errorMessage ?? ''),
          ),
        ),
      );
    }

    if (provider.isEmpty) {
      return padState(
        AppStateView(
          icon: Icons.inbox_outlined,
          title: '這個分類目前沒有內容',
          description: '書源可能尚未提供資料，也可以稍後再試。',
          primaryAction: AppStateAction(
            label: '重新整理',
            icon: Icons.refresh,
            onPressed: provider.refresh,
          ),
        ),
      );
    }

    return RefreshIndicator(
      edgeOffset: padding.top,
      onRefresh: () => provider.refresh(),
      child: ListView.separated(
        padding: EdgeInsets.only(
          top: padding.top,
          bottom: padding.bottom + AppSpacing.xl,
        ),
        itemCount: provider.books.length + (provider.hasMore ? 1 : 0),
        separatorBuilder: (_, _) =>
            const InsetSeparator(indent: ExploreBookItem.textIndent),
        itemBuilder: (context, index) {
          if (index == provider.books.length) {
            if (provider.errorMessage == null) {
              provider.loadMore();
            }
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

  void _showErrorDialog(BuildContext context, String message) {
    showAppAlert<void>(
      context: context,
      title: '錯誤原因',
      content: SelectableText(message, style: AppTextStyles.bodySm),
      actions: const [
        AppAlertAction(label: '關閉', value: null, isDefault: true),
      ],
    );
  }
}
