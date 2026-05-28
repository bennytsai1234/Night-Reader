import 'package:flutter/material.dart';
import 'package:night_reader/core/models/chapter.dart';

class ReaderV2ChaptersDrawer extends StatefulWidget {
  const ReaderV2ChaptersDrawer({
    super.key,
    required this.chapters,
    required this.currentChapterIndex,
    required this.titleFor,
    required this.onChapterTap,
    this.listenable,
  });

  final List<BookChapter> chapters;
  final int currentChapterIndex;
  final String Function(int index) titleFor;
  final Future<void> Function(int index) onChapterTap;
  final Listenable? listenable;

  @override
  State<ReaderV2ChaptersDrawer> createState() => _ReaderV2ChaptersDrawerState();
}

class _ReaderV2ChaptersDrawerState extends State<ReaderV2ChaptersDrawer> {
  static const double _tileExtent = 56.0;

  final ScrollController _scrollController = ScrollController();
  int _lastScrolledChapterIndex = -1;

  @override
  void initState() {
    super.initState();
    widget.listenable?.addListener(_handleChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleScrollToCurrentChapter();
  }

  @override
  void didUpdateWidget(covariant ReaderV2ChaptersDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable?.removeListener(_handleChanged);
      widget.listenable?.addListener(_handleChanged);
      _lastScrolledChapterIndex = -1;
    }
    _scheduleScrollToCurrentChapter();
  }

  @override
  void dispose() {
    widget.listenable?.removeListener(_handleChanged);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleChapterTap(int index) async {
    await widget.onChapterTap(index);
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  void _scrollToCurrentChapter() {
    if (!mounted || !_scrollController.hasClients) return;
    final currentChapterIndex = widget.currentChapterIndex;
    if (currentChapterIndex == _lastScrolledChapterIndex) return;
    _lastScrolledChapterIndex = currentChapterIndex;

    final maxExtent = _scrollController.position.maxScrollExtent;
    final viewportDimension = _scrollController.position.viewportDimension;
    final targetOffset =
        (currentChapterIndex * _tileExtent) -
        ((viewportDimension - _tileExtent) / 2);
    final safeOffset = targetOffset.clamp(0.0, maxExtent);
    _scrollController.jumpTo(safeOffset);
  }

  void _handleChanged() {
    _scheduleScrollToCurrentChapter();
  }

  void _scheduleScrollToCurrentChapter() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToCurrentChapter(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          AppBar(
            title: const Text('目錄'),
            automaticallyImplyLeading: false,
            elevation: 0,
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: widget.chapters.length,
              itemExtent: _tileExtent,
              itemBuilder: (context, index) {
                final isCurrentChapter = widget.currentChapterIndex == index;
                return ListTile(
                  title: Text(
                    widget.titleFor(index),
                    style: TextStyle(
                      color: isCurrentChapter ? Colors.blue : null,
                      fontWeight: isCurrentChapter ? FontWeight.bold : null,
                    ),
                  ),
                  onTap: () => _handleChapterTap(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
