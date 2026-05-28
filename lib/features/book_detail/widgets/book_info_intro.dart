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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const Text('簡介', style: AppTextStyles.titleSm),
          const SizedBox(height: 8),
          Text(
            book.intro ?? '暫無簡介',
            style: const TextStyle(fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
