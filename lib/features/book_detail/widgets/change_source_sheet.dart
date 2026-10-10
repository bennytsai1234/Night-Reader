import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/features/book_detail/book_detail_provider.dart';
import 'package:night_reader/features/book_detail/source/book_detail_change_source_provider.dart';
import 'package:night_reader/features/book_detail/widgets/book_detail_change_source_filter_bar.dart';
import 'package:night_reader/features/book_detail/widgets/book_detail_change_source_item.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

/// 換源面板選源後的處理結果（成功/失敗 + 提示訊息）。
typedef ChangeSourceOutcome = ({bool success, String message});

/// 換源面板選源回呼。
///
/// 詳情頁情境不傳，沿用 [BookDetailProvider.changeSource]；閱讀器情境傳入走
/// [SourceSwitchService] 的回呼。回呼負責執行換源並回傳結果，由面板顯示
/// SnackBar、成功時 pop。
typedef OnSelectSource = Future<ChangeSourceOutcome> Function(
  SearchBook selected,
);

class ChangeSourceSheet extends StatelessWidget {
  final Book book;

  /// 詳情頁情境：提供 detailProvider，走既有 changeSource 行為。
  final BookDetailProvider? detailProvider;

  /// 閱讀器情境：提供自訂選源回呼（走 SourceSwitchService）。
  final OnSelectSource? onSelectSource;

  const ChangeSourceSheet({
    super.key,
    required this.book,
    this.detailProvider,
    this.onSelectSource,
  }) : assert(
         detailProvider != null || onSelectSource != null,
         'ChangeSourceSheet 需要 detailProvider 或 onSelectSource 其中之一',
       );

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BookDetailChangeSourceProvider(book),
      child: _ChangeSourceContent(
        originalBook: book,
        detailProvider: detailProvider,
        onSelectSource: onSelectSource,
      ),
    );
  }
}

class _ChangeSourceContent extends StatefulWidget {
  final Book originalBook;
  final BookDetailProvider? detailProvider;
  final OnSelectSource? onSelectSource;

  const _ChangeSourceContent({
    required this.originalBook,
    required this.detailProvider,
    required this.onSelectSource,
  });

  @override
  State<_ChangeSourceContent> createState() => _ChangeSourceContentState();
}

class _ChangeSourceContentState extends State<_ChangeSourceContent> {
  final TextEditingController _filterController = TextEditingController();
  bool _isSwitchingSource = false;

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BookDetailChangeSourceProvider>();
    final sources = provider.filteredResults
        .where((result) => result.name == widget.originalBook.name)
        .toList();

    final chrome = AppChrome.of(context);
    final count = sources.length;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: chrome.groupedBackground,
        borderRadius: AppRadius.topSheetLg,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(provider),
          BookDetailChangeSourceFilterBar(
            provider: provider,
            filterController: _filterController,
          ),
          SizedBox(
            height: 2,
            child: provider.isSearching || _isSwitchingSource
                ? const LinearProgressIndicator(minHeight: 2)
                : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppGrouped.margin + AppGrouped.rowPadding,
              AppSpacing.sm,
              AppGrouped.margin + AppGrouped.rowPadding,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: GroupedSectionHeader(
                    _isSwitchingSource ? '正在切換來源…' : provider.status,
                  ),
                ),
                if (count > 0) GroupedSectionHeader('共 $count 個來源'),
              ],
            ),
          ),
          Expanded(
            child: IgnorePointer(
              ignoring: _isSwitchingSource,
              child: sources.isEmpty && !provider.isSearching
                  ? Center(
                      child: Text(
                        provider.allResults.isNotEmpty
                            ? '沒有符合篩選的來源'
                            : '未找到其他來源',
                        style: AppTextStyles.bodyBase.copyWith(
                          color: chrome.sectionText,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.only(
                        bottom:
                            MediaQuery.paddingOf(context).bottom +
                            AppSpacing.xl,
                      ),
                      itemCount: count,
                      itemBuilder: (ctx, i) {
                        final result = sources[i];
                        final isCurrent =
                            result.origin == widget.originalBook.origin;
                        return GroupedSliceItem(
                          index: i,
                          count: count,
                          child: BookDetailChangeSourceItem(
                            searchBook: result,
                            isCurrent: isCurrent,
                            onTap: isCurrent
                                ? null
                                : () => _handleSelect(context, result),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSelect(BuildContext context, SearchBook result) async {
    if (_isSwitchingSource) return;
    setState(() => _isSwitchingSource = true);
    try {
      final select = widget.onSelectSource;
      final ChangeSourceOutcome outcome;
      if (select != null) {
        outcome = await select(result);
      } else {
        final detailOutcome = await widget.detailProvider!.changeSource(result);
        outcome = (
          success: detailOutcome.success,
          message: detailOutcome.message,
        );
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(outcome.message)));
      if (outcome.success) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSwitchingSource = false);
    }
  }

  Widget _buildHeader(BookDetailChangeSourceProvider provider) {
    final primary = Theme.of(context).colorScheme.primary;
    return SheetHeader(
      title: '更換來源',
      leading: GlassIconButton(
        icon: provider.checkAuthor
            ? Icons.person_rounded
            : Icons.person_off_outlined,
        iconSize: 20,
        color: provider.checkAuthor ? primary : null,
        tooltip: provider.checkAuthor ? '校驗作者：開' : '校驗作者：關',
        onPressed: _isSwitchingSource ? null : provider.toggleCheckAuthor,
      ),
      trailing: provider.isSearching
          ? const SizedBox.square(
              dimension: AppGlass.buttonSize,
              child: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : GlassIconButton(
              icon: Icons.refresh_rounded,
              iconSize: 20,
              tooltip: '重新搜尋',
              onPressed: _isSwitchingSource ? null : provider.startSearch,
            ),
    );
  }
}
