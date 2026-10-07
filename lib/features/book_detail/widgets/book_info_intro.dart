import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/core/services/chinese_display.dart';

import '../book_detail_provider.dart';
import 'book_info_header.dart';

/// 書籍資訊分組：來源（含書源狀態）、分類、字數、最新章節。
class BookInfoDetails extends StatelessWidget {
  final Book book;
  final BookDetailProvider provider;
  final VoidCallback onShowSourceOptions;

  const BookInfoDetails({
    super.key,
    required this.book,
    required this.provider,
    required this.onShowSourceOptions,
  });

  @override
  Widget build(BuildContext context) {
    final kind = context.zh(book.kind ?? '').trim();
    final wordCount = (book.wordCount ?? '').trim();
    final latest = context.zh(book.latestChapterTitle ?? '').trim();
    return GroupedSection(
      children: [
        GroupedRow(
          title: '來源',
          value: book.originName,
          trailing: book.isLocal ? null : SourceStatusChip(provider: provider),
          showChevron: !book.isLocal,
          onTap: book.isLocal ? null : onShowSourceOptions,
        ),
        if (kind.isNotEmpty) GroupedRow(title: '分類', value: kind),
        if (wordCount.isNotEmpty) GroupedRow(title: '字數', value: wordCount),
        if (latest.isNotEmpty)
          GroupedRow(title: '最新章節', subtitle: latest, maxSubtitleLines: 1),
      ],
    );
  }
}

/// 簡介分組。
class BookInfoIntro extends StatelessWidget {
  final Book book;

  const BookInfoIntro({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    return GroupedSection(
      header: '簡介',
      children: [
        GroupedContent(
          child: Text(
            context.zh(book.intro ?? '暫無簡介'),
            style: AppTextStyles.bodyBase.copyWith(
              height: 1.6,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
