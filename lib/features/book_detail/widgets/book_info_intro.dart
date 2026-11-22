import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';
import 'package:night_reader/core/chinese/ui_language.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/utils/string_utils.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:night_reader/shared/widgets/skeleton/grouped_list_skeleton.dart';
import 'package:night_reader/core/chinese/chinese_display.dart';

import '../book_detail_provider.dart';

/// 書源有問題時資訊上方的一列：寫哪裡不能讀，要登入才讀得到時點了去登入
/// （ADR 0038）。沒有問題時 [of] 是 null。
class BookSourceIssue extends StatelessWidget implements GroupedSkeletonItem {
  const BookSourceIssue({
    super.key,
    required this.message,
    required this.loginRequired,
    this.onLogin,
  });

  static BookSourceIssue? of(
    BookDetailProvider provider, {
    VoidCallback? onLogin,
  }) {
    final message = provider.sourceIssueMessage ?? '';
    if (message.isEmpty) return null;
    return BookSourceIssue(
      message: message,
      loginRequired: provider.loginRequired,
      onLogin: onLogin,
    );
  }

  final String message;
  final bool loginRequired;
  final VoidCallback? onLogin;

  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) => GroupedItemShape.of(build(context), context: context, width: width);

  @override
  Widget build(BuildContext context) => GroupedSection(
    topGap: AppSpacing.xl,
    children: [
      GroupedRow(
        title: message,
        leading: const GroupedIconTile(
          Icons.warning_amber_rounded,
          tint: AppTint.tea,
        ),
        value: loginRequired ? '登入' : null,
        onTap: loginRequired ? onLogin : null,
      ),
    ],
  );
}

/// 書籍資訊分組：來源（含書源狀態）、分類、字數、最新章節。
class BookInfoDetails extends StatelessWidget implements GroupedSkeletonItem {
  final Book book;

  /// 來源那一列右側的書源狀態（本地書沒有）。
  final Widget statusChip;
  final VoidCallback? onShowSourceOptions;

  const BookInfoDetails({
    super.key,
    required this.book,
    required this.statusChip,
    this.onShowSourceOptions,
  });

  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) => GroupedItemShape.of(build(context), context: context, width: width);

  @override
  Widget build(BuildContext context) {
    final kind = StringUtils.kindLabels(context.zh(book.kind ?? '')).join('、');
    final wordCount = StringUtils.displayWordCount(book.wordCount, book.kind);
    final latest = context.zh(book.latestChapterTitle ?? '').trim();
    return GroupedSection(
      children: [
        GroupedRow(
          title: '來源',
          value: book.originName,
          translateValue: false,
          trailing: book.isLocal ? null : statusChip,
          showChevron: !book.isLocal,
          onTap: book.isLocal ? null : onShowSourceOptions,
        ),
        if (kind.isNotEmpty)
          GroupedRow(title: '分類', value: kind, translateValue: false),
        if (wordCount.isNotEmpty) GroupedRow(title: '字數', value: wordCount),
        if (latest.isNotEmpty)
          GroupedRow(title: '最新章節', value: latest, translateValue: false),
      ],
    );
  }
}

/// 簡介分組。
class BookInfoIntro extends StatelessWidget implements GroupedSkeletonItem {
  final Book book;

  const BookInfoIntro({super.key, required this.book});

  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) => GroupedItemShape.of(build(context), context: context, width: width);

  @override
  Widget build(BuildContext context) {
    // 使用者改過的簡介（customIntro）優先，書源更新不會蓋掉。
    final intro = book.getShownIntro();
    return GroupedSection(
      children: [
        GroupedContent(
          child: UiText(
            intro.isEmpty
                ? UiLanguageText.convert(context, '沒有簡介')
                : context.zh(intro),
            translate: false,
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
