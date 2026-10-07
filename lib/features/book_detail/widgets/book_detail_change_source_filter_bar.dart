import 'package:flutter/material.dart';
import 'package:night_reader/features/book_detail/source/book_detail_change_source_provider.dart';
import 'package:night_reader/features/explore/widgets/folder_tabs.dart';
import 'package:night_reader/features/search/widgets/search_field.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

/// 換源面板的篩選列：書源分組以資料夾分頁切換，下方是結果內篩選框。
class BookDetailChangeSourceFilterBar extends StatelessWidget {
  const BookDetailChangeSourceFilterBar({
    super.key,
    required this.provider,
    required this.filterController,
  });

  final BookDetailChangeSourceProvider provider;
  final TextEditingController filterController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppGrouped.margin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (provider.groups.length > 1) ...[
            FolderTabs<String>(
              tabs: [
                for (final group in provider.groups) FolderTab(group, group),
              ],
              selected: provider.selectedGroup,
              onChanged: provider.updateSelectedGroup,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          SearchField(
            controller: filterController,
            hintText: '搜尋結果內篩選',
            textInputAction: TextInputAction.done,
            onChanged: provider.applyFilter,
          ),
        ],
      ),
    );
  }
}
