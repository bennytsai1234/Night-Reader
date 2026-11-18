import 'package:flutter/material.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/core/services/ui_language.dart';
import 'package:night_reader/shared/widgets/ui_text.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

import '../../change_cover_provider.dart';

import 'package:night_reader/shared/widgets/drag_overflow_text.dart';

class CoverHeader extends StatelessWidget {
  final String bookName;
  final String author;

  const CoverHeader({super.key, required this.bookName, required this.author});

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final error = Theme.of(context).colorScheme.error;
    return Consumer<ChangeCoverProvider>(
      builder: (context, provider, child) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左右各一顆：右邊有動作時關閉在左邊（docs/design/components.md）。
          SheetHeader(
            title: '更換封面',
            leading: GlassIconButton(
              tooltip: '關閉',
              icon: Icons.close_rounded,
              iconSize: 20,
              onPressed: () => Navigator.maybePop(context),
            ),
            trailing: GlassIconButton(
              tooltip: provider.isSearching ? '結束搜尋封面' : '重新搜尋封面',
              icon: provider.isSearching
                  ? Icons.stop_rounded
                  : Icons.refresh_rounded,
              iconSize: 20,
              color: provider.isSearching ? error : null,
              onPressed: !provider.isInitialized
                  ? null
                  : () => provider.isSearching
                        ? provider.stopSearch()
                        : provider.search(bookName, author),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppGrouped.margin + AppGrouped.rowPadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DragOverflowText(
                  // 書名、作者照閱讀偏好，標籤照介面語言（ADR 0066）。
                  child: UiText(
                    '${context.ui('搜尋關鍵字：')}'
                    '${context.zh(bookName)} ${context.zh(author)}',
                    translate: false,
                    maxLines: 1,
                    style: AppTextStyles.bodySm.copyWith(
                      color: chrome.sectionText,
                    ),
                  ),
                ),
                if (!provider.isInitialized || provider.isSearching) ...[
                  const SizedBox(height: AppSpacing.sm),
                  ClipRRect(
                    borderRadius: AppRadius.pillShape,
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      value: provider.isInitialized ? provider.progress : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  UiText(
                    provider.isInitialized ? '正在搜尋封面…' : '正在載入封面…',
                    style: AppTextStyles.labelXs.copyWith(
                      color: chrome.sectionText,
                    ),
                  ),
                ] else if (provider.errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  UiText(
                    provider.errorMessage!,
                    style: AppTextStyles.labelXs.copyWith(color: error),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
