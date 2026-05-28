import 'package:flutter/material.dart';
import 'reader_v2_menu_palette.dart';

class ReaderV2TopMenu extends StatelessWidget {
  const ReaderV2TopMenu({
    super.key,
    required this.controlsVisible,
    required this.menuBackgroundColor,
    required this.menuTextColor,
    required this.bookName,
    required this.chapterTitle,
    required this.chapterUrl,
    required this.originName,
    required this.showReadTitleAddition,
    required this.onBack,
    required this.onMore,
  });

  final bool controlsVisible;
  final Color menuBackgroundColor;
  final Color menuTextColor;
  final String bookName;
  final String chapterTitle;
  final String chapterUrl;
  final String originName;
  final bool showReadTitleAddition;
  final VoidCallback onBack;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final menuStyle = ReaderV2MenuStyle.resolve(
      context: context,
      backgroundColor: menuBackgroundColor,
      textColor: menuTextColor,
    );
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !controlsVisible,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          offset: controlsVisible ? Offset.zero : const Offset(0, -1.15),
          child: Container(
            decoration: BoxDecoration(
              color: menuStyle.background,
              border: Border(bottom: BorderSide(color: menuStyle.outline)),
              boxShadow: [
                BoxShadow(
                  color: menuStyle.scrim,
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildAppBar(menuStyle),
                if (showReadTitleAddition) _buildAdditionInfo(menuStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(ReaderV2MenuStyle menuStyle) {
    return Row(
      children: [
        IconButton(
          icon: Icon(Icons.arrow_back, color: menuStyle.foreground),
          onPressed: onBack,
        ),
        Expanded(
          child: Text(
            bookName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ).copyWith(color: menuStyle.foreground),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          icon: Icon(Icons.more_vert, color: menuStyle.foreground),
          onPressed: onMore,
        ),
      ],
    );
  }

  Widget _buildAdditionInfo(ReaderV2MenuStyle menuStyle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chapterTitle,
                  style: TextStyle(
                    color: menuStyle.mutedForeground,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (chapterUrl.isNotEmpty)
                  Text(
                    chapterUrl,
                    style: TextStyle(
                      color: menuStyle.mutedForeground,
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: menuStyle.accentMuted,
              border: Border.all(color: menuStyle.accent),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              originName,
              style: TextStyle(
                color: menuStyle.foreground,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
