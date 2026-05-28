import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:reader/core/models/search_book.dart';
import 'package:reader/shared/theme/app_tokens.dart';
import '../../book_detail_provider.dart';

class CoverGridItem extends StatelessWidget {
  final AggregatedSearchBook result;

  const CoverGridItem({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final isDefault = result.book.bookUrl == 'use_default_cover';
    return GestureDetector(
      onTap: () {
        context.read<BookDetailProvider>().updateCover(
          isDefault ? '' : (result.book.coverUrl ?? ''),
        );
        Navigator.pop(context);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: AppRadius.cardSm,
              child:
                  isDefault
                      ? Container(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.1),
                        child: Center(
                          child: Icon(
                            Icons.settings_backup_restore,
                            color: Theme.of(context).colorScheme.primary,
                            size: 32,
                          ),
                        ),
                      )
                      : CachedNetworkImage(
                        imageUrl: result.book.coverUrl!,
                        fit: BoxFit.cover,
                        placeholder:
                            (context, url) => Container(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                        errorWidget:
                            (context, url, error) => Container(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                              child: Icon(
                                Icons.broken_image,
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                      ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isDefault ? '恢復預設' : (result.book.originName ?? '未知來源'),
            style: const TextStyle(fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
