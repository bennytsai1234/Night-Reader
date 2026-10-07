import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import '../../change_cover_provider.dart';

class CoverHeader extends StatelessWidget {
  final String bookName;
  final String author;

  const CoverHeader({super.key, required this.bookName, required this.author});

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final error = Theme.of(context).colorScheme.error;
    return Consumer<ChangeCoverProvider>(
      builder:
          (context, provider, child) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: '更換封面',
                trailing: GlassIconButton(
                  tooltip: provider.isSearching ? '停止搜尋封面' : '重新搜尋封面',
                  icon:
                      provider.isSearching
                          ? Icons.stop_rounded
                          : Icons.refresh_rounded,
                  iconSize: 20,
                  color: provider.isSearching ? error : null,
                  onPressed:
                      !provider.isInitialized
                          ? null
                          : () =>
                              provider.isSearching
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
                    Text(
                      '搜尋關鍵字：$bookName $author',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySm.copyWith(
                        color: chrome.sectionText,
                      ),
                    ),
                    if (!provider.isInitialized || provider.isSearching) ...[
                      const SizedBox(height: AppSpacing.sm),
                      ClipRRect(
                        borderRadius: AppRadius.pillShape,
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          value:
                              provider.isInitialized ? provider.progress : null,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        provider.isInitialized ? '正在搜尋封面…' : '正在載入封面…',
                        style: AppTextStyles.labelXs.copyWith(
                          color: chrome.sectionText,
                        ),
                      ),
                    ] else if (provider.errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
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
