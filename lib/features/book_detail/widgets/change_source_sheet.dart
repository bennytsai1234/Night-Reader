import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reader/core/models/book.dart';
import 'package:reader/features/book_detail/book_detail_provider.dart';
import 'package:reader/features/book_detail/source/book_detail_change_source_provider.dart';
import 'package:reader/features/book_detail/widgets/book_detail_change_source_filter_bar.dart';
import 'package:reader/features/book_detail/widgets/book_detail_change_source_item.dart';
import 'package:reader/shared/theme/app_text_styles.dart';
import 'package:reader/shared/theme/app_tokens.dart';

class ChangeSourceSheet extends StatelessWidget {
  final Book book;
  final BookDetailProvider detailProvider;

  const ChangeSourceSheet({
    super.key,
    required this.book,
    required this.detailProvider,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BookDetailChangeSourceProvider(book),
      child: _ChangeSourceContent(
        originalBook: book,
        detailProvider: detailProvider,
      ),
    );
  }
}

class _ChangeSourceContent extends StatefulWidget {
  final Book originalBook;
  final BookDetailProvider detailProvider;

  const _ChangeSourceContent({
    required this.originalBook,
    required this.detailProvider,
  });

  @override
  State<_ChangeSourceContent> createState() => _ChangeSourceContentState();
}

class _ChangeSourceContentState extends State<_ChangeSourceContent> {
  final TextEditingController _filterController = TextEditingController();

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BookDetailChangeSourceProvider>();
    final sources =
        provider.filteredResults
            .where((result) => result.name == widget.originalBook.name)
            .toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: Theme.of(context).canvasColor,
        borderRadius: AppRadius.topSheetLg,
      ),
      child: Column(
        children: [
          _buildHeader(provider),
          const Divider(height: 1),
          BookDetailChangeSourceFilterBar(
            provider: provider,
            filterController: _filterController,
          ),
          if (provider.isSearching) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    provider.status,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (sources.isNotEmpty)
                  Text(
                    '共 ${sources.length} 個來源',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child:
                sources.isEmpty && !provider.isSearching
                    ? const Center(child: Text('未找到其他來源'))
                    : ListView.separated(
                      itemCount: sources.length,
                      separatorBuilder: (ctx, i) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final result = sources[i];
                        return BookDetailChangeSourceItem(
                          searchBook: result,
                          isCurrent:
                              result.origin == widget.originalBook.origin,
                          onTap:
                              result.origin == widget.originalBook.origin
                                  ? null
                                  : () async {
                                    final outcome = await widget.detailProvider
                                        .changeSource(result);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(outcome.message)),
                                    );
                                    if (outcome.success) Navigator.pop(context);
                                  },
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BookDetailChangeSourceProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '更換來源 (${provider.filteredResults.length})',
              style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: Icon(
              provider.checkAuthor ? Icons.person : Icons.person_off,
              size: 20,
            ),
            onPressed: provider.toggleCheckAuthor,
            tooltip: '校驗作者',
          ),
          if (provider.isSearching)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: provider.startSearch,
              tooltip: '重新搜尋',
            ),
        ],
      ),
    );
  }
}
