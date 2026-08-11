import 'dart:async';

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
  final Future<bool> Function(int index) onChapterTap;
  final Listenable? listenable;

  @override
  State<ReaderV2ChaptersDrawer> createState() => _ReaderV2ChaptersDrawerState();
}

class _ReaderV2ChaptersDrawerState extends State<ReaderV2ChaptersDrawer> {
  static const double _tileExtent = 56.0;

  final ScrollController _scrollController = ScrollController();
  int _lastScrolledChapterIndex = -1;
  int? _pendingChapterIndex;

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
    if (_pendingChapterIndex != null) return;
    setState(() => _pendingChapterIndex = index);

    late final bool succeeded;
    try {
      succeeded = await widget.onChapterTap(index);
    } finally {
      if (mounted) {
        setState(() => _pendingChapterIndex = null);
      }
    }

    if (!mounted || !succeeded || !Navigator.canPop(context)) return;
    Navigator.pop(context);
  }

  Widget _buildPendingIndicator(String chapterTitle) {
    return Semantics(
      container: true,
      label: '正在跳轉至$chapterTitle',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  VoidCallback? _chapterTapHandler(int index) {
    if (_pendingChapterIndex != null) return null;
    return () {
      unawaited(_handleChapterTap(index));
    };
  }

  Widget _buildChapterTile(int index) {
    final chapterTitle = widget.titleFor(index);
    final isCurrentChapter = widget.currentChapterIndex == index;
    final isPending = _pendingChapterIndex == index;
    return ListTile(
      title: Text(
        chapterTitle,
        style: TextStyle(
          color:
              isCurrentChapter ? Theme.of(context).colorScheme.primary : null,
          fontWeight: isCurrentChapter ? FontWeight.bold : null,
        ),
      ),
      trailing: isPending ? _buildPendingIndicator(chapterTitle) : null,
      onTap: _chapterTapHandler(index),
    );
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
              itemBuilder: (context, index) => _buildChapterTile(index),
            ),
          ),
        ],
      ),
    );
  }
}
