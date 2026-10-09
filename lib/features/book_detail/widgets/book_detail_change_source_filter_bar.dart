import 'package:flutter/material.dart';
import 'package:night_reader/features/book_detail/source/book_detail_change_source_provider.dart';
import 'package:night_reader/shared/widgets/group_filter_bar.dart';
import 'package:night_reader/shared/widgets/search_field.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

/// 換源面板的篩選列：書源分組篩選列，下方是結果內篩選框。
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
          if (provider.groups.isNotEmpty) ...[
            GroupFilterBar<String>(
              all: GroupFilterOption(
                BookDetailChangeSourceProvider.allGroups,
                BookDetailChangeSourceProvider.allGroups,
                count: provider.enabledSourceCount,
              ),
              groups: [
                for (final group in provider.groups)
                  GroupFilterOption(
                    group,
                    group,
                    count: provider.groupCounts[group],
                  ),
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
