import 'package:flutter/material.dart';
import 'package:reader/features/book_detail/source/book_detail_change_source_provider.dart';
import 'package:reader/shared/theme/app_text_styles.dart';
import 'package:reader/shared/theme/app_tokens.dart';

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
    return Column(
      children: [
        if (provider.groups.length > 1)
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              itemCount: provider.groups.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, index) {
                final group = provider.groups[index];
                final isSelected = provider.selectedGroup == group;
                return FilterChip(
                  label: Text(
                    group,
                    style: AppTextStyles.labelSm.copyWith(
                      color: isSelected ? Colors.white : null,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (val) => provider.updateSelectedGroup(group),
                  selectedColor: Theme.of(context).colorScheme.primary,
                  showCheckmark: false,
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: TextField(
            controller: filterController,
            decoration: InputDecoration(
              hintText: '搜尋結果內篩選...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                vertical: AppSpacing.sm,
              ),
              border: OutlineInputBorder(borderRadius: AppRadius.cardMd),
            ),
            onChanged: provider.applyFilter,
          ),
        ),
      ],
    );
  }
}
