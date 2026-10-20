import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/shared/navigation/transition_settled.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/cover_reveal.dart';
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
class ExploreShowPage extends StatefulWidget {
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
  State<ExploreShowPage> createState() => _ExploreShowPageState();
}

class _ExploreShowPageState extends State<ExploreShowPage> {
  /// 進場動畫播完時完成；書單等它才開始載入（ADR 0018）。
  Future<void>? _entrance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _entrance ??= TransitionSettled.entered(context);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ExploreShowProvider(
        sourceUrl: widget.sourceUrl,
        exploreUrl: widget.exploreUrl,
        exploreName: widget.exploreName,
        entrance: _entrance!,
      ),
      child: ExploreShowView(exploreName: widget.exploreName),
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

  /// 第一頁載入時顯示書單骨架，書到了以淡入取代。書列在骨架底下一格建一
  /// 列（[CoverRevealSlot]）、畫面上的封面解碼好才換場：原本書單到的那一格
  /// 一次建出畫面上的九本，電腦上就要 45–65ms（ADR 0029）。
  Widget _buildBody(BuildContext context, ExploreShowProvider provider) {
    return SkeletonSwitcher(
      loading: provider.isLoading && provider.books.isEmpty,
      waitForCovers: true,
      // 書單直接畫在頁面底色上：換場只遮骨架一層（ADR 0029）。
      backdrop: Theme.of(context).scaffoldBackgroundColor,
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
          return CoverRevealSlot(
            key: ValueKey(book.bookUrl),
            placeholder: const SizedBox(
              height: ExploreBookItem.coverHeight + AppSpacing.md * 2,
            ),
            child: _ExploreBookRow(
              book: book,
              details: provider.details,
              source: provider.source,
              isInBookshelf: provider.isInBookshelf(book),
              sourceName: exploreName,
            ),
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
  /// 清單會先建好畫面外附近的列、捲走後也留著一陣子；列建起來不等於使用者
  /// 看得到。照它在捲動區裡實際的位置決定排不排隊。
  ScrollPosition? _position;
  bool _visible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_scheduleCheck);
      _position = position?..addListener(_scheduleCheck);
    }
    _scheduleCheck();
  }

  bool _checkScheduled = false;

  /// 捲動位置變的當下這一格還沒重新排版，量到的是上一格的位置；等這一格
  /// 畫完再量，同一格只量一次。
  void _scheduleCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      _checkVisible();
    });
  }

  @override
  void didUpdateWidget(_ExploreBookRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.book, widget.book) ||
        oldWidget.source != widget.source) {
      if (_visible) widget.details.hidden(oldWidget.book.bookUrl);
      _visible = false;
      _scheduleCheck();
    }
  }

  void _checkVisible() {
    if (!mounted) return;
    final box = context.findRenderObject();
    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox ||
        viewport is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        !viewport.hasSize) {
      return;
    }
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final visible = top < viewport.size.height && top + box.size.height > 0;
    if (visible == _visible) return;
    _visible = visible;
    final source = widget.source;
    if (visible && source != null) {
      widget.details.shown(source, widget.book);
    } else if (!visible) {
      widget.details.hidden(widget.book.bookUrl);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_scheduleCheck);
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
