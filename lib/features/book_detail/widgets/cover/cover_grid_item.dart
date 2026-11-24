import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';
import 'package:night_reader/core/models/search/search_book.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/book/book_cover_widget.dart';
import 'package:night_reader/shared/widgets/glass/glass.dart';

import '../../change_cover_sheet.dart';

import 'package:night_reader/shared/widgets/text/drag_overflow_text.dart';

class CoverGridItem extends StatelessWidget {
  final AggregatedSearchBook result;

  const CoverGridItem({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final isDefault = result.book.bookUrl == 'use_default_cover';
    final chrome = AppChrome.of(context);
    return PressScale(
      scale: 0.95,
      onTap: () => applyCoverFromSheet(
        context,
        isDefault ? '' : (result.book.coverUrl ?? ''),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: isDefault
                ? ClipRRect(
                    borderRadius: AppRadius.cardSm,
                    child: Container(
                      color: Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.1),
                      child: Center(
                        child: Icon(
                          Icons.settings_backup_restore,
                          color: Theme.of(context).colorScheme.primary,
                          size: 32,
                        ),
                      ),
                    ),
                  )
                // 同 App 其他封面：載入中鋪骨架的底色、到了淡入，載不到畫
                // 預設封面（Legado 換封面的候選也是）。
                : BookCoverWidget(
                    coverUrl: result.book.coverUrl,
                    origin: result.book.origin,
                    bookName: result.book.name,
                    author: result.book.author,
                    kind: result.book.bookKind,
                    width: double.infinity,
                    height: double.infinity,
                    borderRadius: AppRadius.cardSm,
                  ),
          ),
          const SizedBox(height: 4),
          DragOverflowText(
            child: UiText(
              isDefault ? '恢復預設' : (result.book.originName ?? '未知來源'),
              // 書源名稱照原文（ADR 0066）。
              translate: isDefault || result.book.originName == null,
              style: AppTextStyles.labelXs.copyWith(color: chrome.sectionText),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
