import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';

import 'explore_book_details.dart';
import 'explore_show_provider.dart';
import 'widgets/explore_book_item.dart';
import 'widgets/explore_skeletons.dart';

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
      child: ExploreShowView(exploreName: exploreName),
    );
  }
}

/// 分類書單的畫面；[ExploreShowProvider] 由上層提供（[ExploreShowPage]）。
class ExploreShowView extends StatelessWidget {
  final String exploreName;

  const ExploreShowView({super.key, required this.exploreName});

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

  /// 書單讓出頁首與底部系統區。
  EdgeInsets _listPadding(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return EdgeInsets.only(
      top: padding.top,
      bottom: padding.bottom + AppSpacing.xl,
    );
  }

  /// 第一頁載入時顯示書單骨架，書到了以淡入取代。
  Widget _buildBody(BuildContext context, ExploreShowProvider provider) {
    return SkeletonSwitcher(
      loading: provider.isLoading && provider.books.isEmpty,
      skeleton: ExploreBookListSkeleton(padding: _listPadding(context)),
      builder: (_) => _buildLoaded(context, provider),
    );
  }

  Widget _buildLoaded(BuildContext context, ExploreShowProvider provider) {
    final padding = MediaQuery.paddingOf(context);
    Widget padState(Widget child) => Padding(
      padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
      child: child,
    );

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
        padding: _listPadding(context),
        itemCount: provider.books.length + (provider.hasMore ? 1 : 0),
        separatorBuilder: (_, _) =>
            const InsetSeparator(indent: ExploreBookItem.textIndent),
        itemBuilder: (context, index) {
          if (index == provider.books.length) {
            if (provider.errorMessage == null) {
              // loadMore 會同步通知監聽者，不能在排版途中呼叫。
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => provider.loadMore(),
              );
            }
            return _buildLoadMoreIndicator(context, provider);
          }
          final book = provider.books[index];
          return _ExploreBookRow(
            key: ValueKey(book.bookUrl),
            book: book,
            details: provider.details,
            source: provider.source,
            isInBookshelf: provider.isInBookshelf(book),
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

/// 書單的一列：建起來（畫到清單上）時，缺的封面與字數排進背景補，捲出
/// 清單時還沒開始的就不補。補到時只重建這一列的封面與那一行字
/// （[ExploreBookItem.extras]）。
class _ExploreBookRow extends StatefulWidget {
  const _ExploreBookRow({
    super.key,
    required this.book,
    required this.details,
    required this.source,
    required this.isInBookshelf,
    required this.sourceName,
  });

  final SearchBook book;
  final ExploreBookDetails details;
  final BookSource? source;
  final bool isInBookshelf;
  final String sourceName;

  @override
  State<_ExploreBookRow> createState() => _ExploreBookRowState();
}

class _ExploreBookRowState extends State<_ExploreBookRow> {
  @override
  void initState() {
    super.initState();
    _show();
  }

  @override
  void didUpdateWidget(_ExploreBookRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.book, widget.book) ||
        oldWidget.source != widget.source) {
      _show();
    }
  }

  void _show() {
    final source = widget.source;
    if (source != null) widget.details.shown(source, widget.book);
  }

  @override
  void dispose() {
    widget.details.hidden(widget.book.bookUrl);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExploreBookItem(
      book: widget.book,
      extras: widget.details.extrasOf(widget.book.bookUrl),
      isInBookshelf: widget.isInBookshelf,
      sourceName: widget.sourceName,
    );
  }
}
