import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:night_reader/features/book_detail/book_detail_provider.dart';
import 'package:night_reader/features/book_detail/change_cover_sheet.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/export_book_service.dart';
import 'package:night_reader/features/source_manager/source_editor_page.dart';
import 'package:night_reader/features/source_manager/source_debug_page.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_open_target.dart';
import 'package:night_reader/shared/navigation/book_open_route.dart';

import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import 'widgets/book_info_header.dart';
import 'widgets/book_info_intro.dart';
import 'widgets/book_info_toc_bar.dart';
import 'widgets/change_source_sheet.dart';

class BookDetailPage extends StatefulWidget {
  final Book? book;
  final AggregatedSearchBook? searchBook;

  const BookDetailPage({super.key, this.book, this.searchBook})
    : assert(book != null || searchBook != null);

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends State<BookDetailPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create:
          (_) => BookDetailProvider(
            widget.searchBook ??
                AggregatedSearchBook(book: widget.book!, sources: []),
          ),
      child: Consumer<BookDetailProvider>(
        builder: (context, provider, child) {
          final currentBook = provider.book;
          return Scaffold(
            appBar: _buildAppBar(context, provider),
            body:
                provider.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        if ((provider.sourceIssueMessage ?? '').isNotEmpty)
                          SliverToBoxAdapter(
                            child: Container(
                              margin: const EdgeInsets.fromLTRB(
                                AppSpacing.lg,
                                AppSpacing.lg,
                                AppSpacing.lg,
                                0,
                              ),
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: BoxDecoration(
                                color: context.warning.withValues(alpha: 0.08),
                                borderRadius: AppRadius.cardMd,
                                border: Border.all(
                                  color: context.warning.withValues(
                                    alpha: 0.25,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: context.warning,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(provider.sourceIssueMessage!),
                                  ),
                                  TextButton(
                                    onPressed:
                                        () => _showChangeSourceDialog(
                                          context,
                                          provider,
                                        ),
                                    child: const Text('換源'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        SliverToBoxAdapter(
                          child: BookInfoHeader(
                            book: currentBook,
                            provider: provider,
                            showPhotoView: _showPhotoView,
                            onEdit:
                                () =>
                                    _showEditBookInfoDialog(context, provider),
                            showSourceOptions: _showSourceOptions,
                            navigateToReader: _navigateToReader,
                            showChangeSource: _showChangeSourceDialog,
                            toggleBookshelf: _handleBookshelfToggle,
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: BookInfoIntro(book: currentBook),
                        ),
                        BookInfoTocBar(
                          provider: provider,
                          onSearch:
                              () => _showSearchTocDialog(context, provider),
                          onLocateCurrent:
                              () => _locateCurrentChapter(context, provider),
                        ),
                        SliverList(
                          delegate: SliverChildBuilderDelegate((ctx, i) {
                            final chapter = provider.filteredChapters[i];
                            final isCurrent =
                                chapter.index == currentBook.chapterIndex;
                            return ListTile(
                              selected: isCurrent,
                              leading:
                                  isCurrent
                                      ? const Icon(Icons.my_location, size: 18)
                                      : null,
                              title: Text(
                                chapter.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing:
                                  isCurrent
                                      ? const Text(
                                        '目前',
                                        style: AppTextStyles.labelSm,
                                      )
                                      : null,
                              onTap:
                                  () => _navigateToReader(
                                    context,
                                    currentBook,
                                    ReaderV2OpenTarget.chapterStart(
                                      chapter.index,
                                    ),
                                    provider.allChapters,
                                  ),
                            );
                          }, childCount: provider.filteredChapters.length),
                        ),
                      ],
                    ),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    BookDetailProvider provider,
  ) {
    return AppBar(
      title: const Text('書籍詳情'),
      actions: [
        IconButton(
          icon: Icon(
            provider.isInBookshelf
                ? Icons.library_add_check
                : Icons.library_add,
          ),
          onPressed: () => _handleBookshelfToggle(context, provider),
          tooltip: provider.isInBookshelf ? '移出書架' : '加入書架',
        ),
        PopupMenuButton<String>(
          onSelected: (v) => _handleMenuSelection(context, provider, v),
          itemBuilder:
              (ctx) => [
                const PopupMenuItem(value: 'check_update', child: Text('檢查更新')),
                const PopupMenuItem(value: 'download', child: Text('預下載章節')),
                const PopupMenuItem(value: 'change_cover', child: Text('換封面')),
                const PopupMenuItem(value: 'export', child: Text('匯出全書')),
                const PopupMenuItem(value: 'edit', child: Text('編輯資訊')),
              ],
        ),
      ],
    );
  }

  Future<void> _handleMenuSelection(
    BuildContext context,
    BookDetailProvider provider,
    String val,
  ) async {
    if (val == 'check_update') {
      await _handleCheckUpdate(context, provider);
    } else if (val == 'download') {
      _showDownloadSheet(context, provider);
    } else if (val == 'export') {
      await _handleExport(context, provider);
    } else if (val == 'edit') {
      _showEditBookInfoDialog(context, provider);
    } else if (val == 'change_cover') {
      _showChangeCoverSheet(context, provider);
    }
  }

  Future<void> _handleBookshelfToggle(
    BuildContext context,
    BookDetailProvider provider,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    if (provider.isInBookshelf) {
      final confirmed = await _confirmAction(
        context,
        title: '移出書架',
        message: '這本書會從書架移出，已快取正文不會被刪除。',
        confirmText: '移出',
      );
      if (!confirmed || !context.mounted) return;
      final result = await provider.setInBookshelf(false);
      if (!context.mounted) return;
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.message),
          duration: const Duration(seconds: 4),
          persist: false,
          action:
              result.success
                  ? SnackBarAction(
                    label: '撤銷',
                    onPressed: () => provider.setInBookshelf(true),
                  )
                  : null,
        ),
      );
      return;
    }

    final result = await provider.setInBookshelf(true);
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _handleCheckUpdate(
    BuildContext context,
    BookDetailProvider provider,
  ) async {
    final result = await provider.checkForUpdates();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _handleExport(
    BuildContext context,
    BookDetailProvider provider,
  ) async {
    if (provider.totalChapterCount == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('沒有可匯出的章節')));
      return;
    }
    await provider.refreshCacheStatus();
    if (!context.mounted) return;
    final status = provider.cacheStatus;
    var fetchMissingRemote = false;
    if (!provider.book.isLocal && status.missingChapterCount > 0) {
      final decision = await showDialog<String>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('匯出可能不完整'),
              content: Text(
                '目前只快取 ${status.storedChapterCount}/${status.totalChapterCount} 章，'
                '仍缺 ${status.missingChapterCount} 章正文。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'download'),
                  child: const Text('先下載缺失章節'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cached'),
                  child: const Text('只匯出已快取'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'export'),
                  child: const Text('補抓並匯出'),
                ),
              ],
            ),
      );
      if (!context.mounted || decision == null || decision == 'cancel') return;
      if (decision == 'download') {
        final result = await provider.queueDownloadMissing();
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message)));
        return;
      }
      fetchMissingRemote = decision == 'export';
    }

    try {
      await ExportBookService().exportToTxt(
        provider.book,
        fetchMissingRemote: fetchMissingRemote,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已建立匯出檔案')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('匯出失敗: $e')));
    }
  }

  Future<bool> _confirmAction(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmText,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmText),
              ),
            ],
          ),
    );
    return confirmed ?? false;
  }

  void _showDownloadSheet(BuildContext context, BookDetailProvider provider) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.playlist_add_outlined),
                  title: const Text('從目前章節起下載到結尾'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _queueDownload(
                      context,
                      provider.queueDownloadFromCurrent(),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.looks_one_outlined),
                  title: const Text('從目前章節起下載後 10 章'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _queueDownload(context, provider.queueDownloadNext(10));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.filter_5_outlined),
                  title: const Text('從目前章節起下載後 50 章'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _queueDownload(context, provider.queueDownloadNext(50));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.library_books_outlined),
                  title: const Text('下載全書'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _queueDownload(context, provider.queueDownloadAll());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.download_done_outlined),
                  title: const Text('下載全部未下載章節'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _queueDownload(context, provider.queueDownloadMissing());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.tune_outlined),
                  title: const Text('指定章節範圍'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showDownloadRangeDialog(context, provider);
                  },
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _queueDownload(
    BuildContext context,
    Future<StorageDownloadQueueResult> task,
  ) async {
    final result = await task;
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  void _showDownloadRangeDialog(
    BuildContext context,
    BookDetailProvider provider,
  ) {
    final start = TextEditingController(
      text: '${provider.book.chapterIndex + 1}',
    );
    final end = TextEditingController(text: '${provider.totalChapterCount}');
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('指定下載範圍'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: start,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '起始章節序號'),
                ),
                TextField(
                  controller: end,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '結束章節序號'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final startValue = int.tryParse(start.text.trim());
                  final endValue = int.tryParse(end.text.trim());
                  if (startValue == null ||
                      endValue == null ||
                      startValue <= 0 ||
                      endValue < startValue) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('請輸入有效章節範圍')));
                    return;
                  }
                  Navigator.pop(ctx);
                  _queueDownload(
                    context,
                    provider.queueDownloadRange(startValue - 1, endValue - 1),
                  );
                },
                child: const Text('加入佇列'),
              ),
            ],
          ),
    ).whenComplete(() {
      start.dispose();
      end.dispose();
    });
  }

  void _locateCurrentChapter(
    BuildContext context,
    BookDetailProvider provider,
  ) {
    provider.resetTocViewForCurrentChapter();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients || !context.mounted) return;
      final index = provider.displayIndexForChapter(provider.book.chapterIndex);
      if (index < 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('目前閱讀章節不在目錄中')));
        return;
      }
      final offset = 360.0 + index * 56.0;
      final maxOffset = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        math.min(offset, maxOffset),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _showPhotoView(BuildContext context, String url) {
    final isLocal = url.startsWith('local://') || url.startsWith('file://');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (ctx) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(backgroundColor: Colors.transparent),
              body: Center(
                child: Hero(
                  tag: 'book_cover',
                  child:
                      isLocal
                          ? Image.file(
                            url.startsWith('local://')
                                ? File(url.replaceFirst('local://', ''))
                                : File(Uri.parse(url).toFilePath()),
                          )
                          : CachedNetworkImage(imageUrl: url),
                ),
              ),
            ),
      ),
    );
  }

  void _showSourceOptions(BuildContext context, Book b) {
    final provider = context.read<BookDetailProvider>();
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(b.originName),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('狀態：${provider.sourceStatusLabel}'),
                const SizedBox(height: 8),
                Text(provider.sourceStatusDescription),
                const SizedBox(height: 8),
                Text(b.origin, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  final s = provider.currentSource;
                  Navigator.pop(ctx);
                  if (s != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SourceEditorPage(source: s),
                      ),
                    );
                  }
                },
                child: const Text('詳情'),
              ),
              TextButton(
                onPressed: () {
                  final s = provider.currentSource;
                  Navigator.pop(ctx);
                  if (s != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => SourceDebugPage(source: s, debugKey: b.name),
                      ),
                    );
                  }
                },
                child: const Text('調試'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('關閉'),
              ),
            ],
          ),
    );
  }

  void _navigateToReader(
    BuildContext context,
    Book b,
    ReaderV2OpenTarget openTarget,
    List<BookChapter> initialChapters,
  ) {
    Navigator.push(
      context,
      BookOpenRoute(
        book: b,
        openTarget: openTarget,
        initialChapters: initialChapters,
      ),
    );
  }

  void _showChangeSourceDialog(BuildContext context, BookDetailProvider p) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => ChangeSourceSheet(book: p.book, detailProvider: p),
      );

  void _showSearchTocDialog(BuildContext context, BookDetailProvider p) =>
      showDialog(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('搜尋目錄'),
              content: TextField(autofocus: true, onChanged: p.setSearchQuery),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('關閉'),
                ),
              ],
            ),
      );

  void _showEditBookInfoDialog(BuildContext context, BookDetailProvider p) {
    final n = TextEditingController(text: p.book.name),
        a = TextEditingController(text: p.book.author),
        i = TextEditingController(text: p.book.intro),
        c = TextEditingController(text: p.book.coverUrl),
        k = TextEditingController(text: p.book.kind ?? ''),
        tag = TextEditingController(text: p.book.customTag ?? ''),
        sourceName = TextEditingController(text: p.book.originName),
        toc = TextEditingController(text: p.book.tocUrl);
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('編輯'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: n,
                    decoration: const InputDecoration(labelText: '書名'),
                  ),
                  TextField(
                    controller: a,
                    decoration: const InputDecoration(labelText: '作者'),
                  ),
                  TextField(
                    controller: c,
                    decoration: const InputDecoration(labelText: '封面'),
                  ),
                  TextField(
                    controller: k,
                    decoration: const InputDecoration(labelText: '分類'),
                  ),
                  TextField(
                    controller: tag,
                    decoration: const InputDecoration(labelText: '自訂標籤'),
                  ),
                  TextField(
                    controller: sourceName,
                    decoration: const InputDecoration(labelText: '來源名稱'),
                  ),
                  TextField(
                    controller: toc,
                    decoration: const InputDecoration(labelText: '目錄 URL'),
                  ),
                  TextField(
                    controller: i,
                    decoration: const InputDecoration(labelText: '簡介'),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  p.updateBookInfo(
                    n.text,
                    a.text,
                    i.text,
                    c.text,
                    kind: k.text,
                    customTag: tag.text,
                    originName: sourceName.text,
                    tocUrl: toc.text,
                  );
                  Navigator.pop(ctx);
                },
                child: const Text('儲存'),
              ),
            ],
          ),
    ).whenComplete(() {
      n.dispose();
      a.dispose();
      i.dispose();
      c.dispose();
      k.dispose();
      tag.dispose();
      sourceName.dispose();
      toc.dispose();
    });
  }

  void _showChangeCoverSheet(BuildContext context, BookDetailProvider p) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder:
            (ctx) => ChangeNotifierProvider.value(
              value: p,
              child: ChangeCoverSheet(
                bookName: p.book.name,
                author: p.book.author,
              ),
            ),
      );
}
