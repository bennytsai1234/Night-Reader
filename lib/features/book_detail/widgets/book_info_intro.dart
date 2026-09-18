import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

class BookInfoIntro extends StatelessWidget {
  final Book book;

  const BookInfoIntro({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Text(
            '簡介',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              height: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            book.intro ?? '暫無簡介',
            style: AppTextStyles.bodyBase.copyWith(height: 1.55),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}
