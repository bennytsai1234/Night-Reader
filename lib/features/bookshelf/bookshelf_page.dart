import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/local_book/local_book_formats.dart';
import 'package:night_reader/core/services/bookshelf_exchange_service.dart';
import 'package:night_reader/core/services/restore_service.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:night_reader/features/book_detail/book_detail_page.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_open_target.dart';
import 'package:night_reader/shared/navigation/book_open_route.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';

class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  bool _isMultiSelect = false;
  final Set<String> _selectedUrls = {};

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BookshelfProvider>();
    return PopScope<void>(
      canPop: !_isMultiSelect,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_isMultiSelect) return;
        setState(() {
          _isMultiSelect = false;
          _selectedUrls.clear();
        });
      },
      child: Scaffold(
        appBar: AppBar(
          title:
              _isMultiSelect
                  ? Text('已選擇 ${_selectedUrls.length} 本')
                  : const Text('書架'),
          leading:
              _isMultiSelect
                  ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed:
                        () => setState(() {
                          _isMultiSelect = false;
                          _selectedUrls.clear();
                        }),
                  )
                  : null,
          actions:
              _isMultiSelect
                  ? [
                    IconButton(
                      icon: const Icon(Icons.download_outlined),
                      tooltip: '批次下載',
                      onPressed:
                          _selectedUrls.isEmpty
                              ? null
                              : () => _batchDownload(context, provider),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cloud_download_outlined),
                      tooltip: '整本書補下載',
                      onPressed:
                          _selectedUrls.isEmpty
                              ? null
                              : () => _batchEnsureComplete(context, provider),
                    ),
                    IconButton(
                      icon: const Icon(Icons.update),
                      tooltip: '批次檢查更新',
                      onPressed:
                          _selectedUrls.isEmpty
                              ? null
                              : () => _batchCheckUpdate(context, provider),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '刪除',
                      onPressed: () => _showDeleteConfirm(context, provider),
                    ),
                    IconButton(
                      icon: const Icon(Icons.select_all),
                      tooltip: '全選',
                      onPressed:
                          () => setState(() {
                            if (_selectedUrls.length == provider.books.length) {
                              _selectedUrls.clear();
                            } else {
                              _selectedUrls.addAll(
                                provider.books.map((b) => b.bookUrl),
                              );
                            }
                          }),
                    ),
                  ]
                  : [
                    IconButton(
                      icon: const Icon(Icons.search),
                      onPressed:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SearchPage(),
                            ),
                          ),
                    ),

                    PopupMenuButton<String>(
                      itemBuilder:
                          (context) => [
                            PopupMenuItem(
                              value: 'grid',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.view_quilt_outlined,
                                    size: 20,
                                    color: Theme.of(context).iconTheme.color,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(provider.isGridView ? '列表視圖' : '網格視圖'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'add_local',
                              child: Row(
                                children: [
                                  Icon(Icons.file_open_outlined, size: 20),
                                  SizedBox(width: 12),
                                  Text('添加本地'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'sort',
                              child: Row(
                                children: [
                                  Icon(Icons.sort, size: 20),
                                  SizedBox(width: 12),
                                  Text('排序'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'manage',
                              child: Row(
                                children: [
                                  Icon(Icons.format_list_bulleted, size: 20),
                                  SizedBox(width: 12),
                                  Text('書架管理'),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'import_url',
                              child: Row(
                                children: [
                                  Icon(Icons.file_download_outlined, size: 20),
                                  SizedBox(width: 12),
                                  Text('從網址匯入書架'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'import',
                              child: Row(
                                children: [
                                  Icon(Icons.file_download_outlined, size: 20),
                                  SizedBox(width: 12),
                                  Text('從檔案匯入書架'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'export',
                              child: Row(
                                children: [
                                  Icon(Icons.file_upload_outlined, size: 20),
                                  SizedBox(width: 12),
                                  Text('匯出書架'),
                                ],
                              ),
                            ),
                          ],
                      onSelected: (value) async {
                        switch (value) {
                          case 'grid':
                            provider.setGridView(!provider.isGridView);
                            break;
                          case 'add_local':
                            final result = await FilePicker.pickFiles(
                              type: FileType.custom,
                              allowedExtensions:
                                  kSupportedLocalBookExtensions.toList()
                                    ..sort(),
                            );
                            if (result != null &&
                                result.files.single.path != null) {
                              if (!context.mounted) break;
                              await _importLocalBook(
                                context,
                                provider,
                                result.files.single.path!,
                              );
                            }
                            break;
                          case 'sort':
                            await _showSortSheet(context, provider);
                            break;
                          case 'manage':
                            setState(() {
                              _isMultiSelect = true;
                            });
                            break;
                          case 'import':
                            await _handleBookshelfImport(context);
                            break;
                          case 'import_url':
                            await _showImportBookshelfUrlDialog(
                              context,
                              provider,
                            );
                            break;
                          case 'export':
                            await _handleBookshelfExport(context, provider);
                            break;
                        }
                      },
                    ),
                  ],
        ),
        body: Column(
          children: [
            Expanded(
              child:
                  provider.isLoading && provider.books.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : provider.books.isEmpty
                      ? const Center(child: Text('書架空空如也，去搜尋看看吧'))
                      : RefreshIndicator(
                        onRefresh: () => provider.refreshBookshelf(),
                        child:
                            provider.isGridView
                                ? _buildGridView(provider)
                                : _buildListView(provider),
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importLocalBook(
    BuildContext context,
    BookshelfProvider provider,
    String path,
  ) async {
    try {
      final ok = await provider.importLocalBookPath(path);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ok ? '匯入成功' : '匯入失敗')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('匯入失敗: $e')));
    }
  }

  Future<void> _showImportBookshelfUrlDialog(
    BuildContext context,
    BookshelfProvider provider,
  ) async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('從網址匯入書架'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: '輸入書架 JSON 網址'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('匯入'),
              ),
            ],
          ),
    );
    if (url == null || url.isEmpty || !context.mounted) return;
    try {
      await provider.importBookshelfFromUrl(url);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('書架網址匯入完成')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('書架網址匯入失敗: $e')));
    }
  }

  Future<void> _handleBookshelfImport(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'zip'],
    );
    if (result == null ||
        result.files.single.path == null ||
        !context.mounted) {
      return;
    }
    final path = result.files.single.path!;
    try {
      if (path.toLowerCase().endsWith('.zip')) {
        final restored = await RestoreService().restoreFromZip(File(path));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(restored ? '備份還原完成，請重新開啟相關頁面確認資料' : '備份還原失敗')),
        );
      } else {
        final imported = await BookshelfExchangeService().importFromFile(
          File(path),
        );
        if (!context.mounted) return;
        context.read<BookshelfProvider>().loadBooks();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已匯入 ${imported.books} 本書、${imported.chapters} 個章節、${imported.sources} 個書源'
              '${imported.contents > 0 ? '，${imported.contents} 份正文快取' : ''}',
            ),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('匯入失敗: $e')));
    }
  }

  Future<void> _handleBookshelfExport(
    BuildContext context,
    BookshelfProvider provider,
  ) async {
    try {
      await BookshelfExchangeService().shareBookshelf(books: provider.books);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('書架已匯出')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('匯出失敗: $e')));
    }
  }

  Future<void> _showSortSheet(
    BuildContext context,
    BookshelfProvider provider,
  ) async {
    final selected = await showModalBottomSheet<BookshelfSortMode>(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: RadioGroup<BookshelfSortMode>(
              groupValue: provider.sortMode,
              onChanged: (value) => Navigator.pop(ctx, value),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final mode in BookshelfSortMode.values)
                    ListTile(
                      leading: Radio<BookshelfSortMode>(value: mode),
                      title: Text(mode.label),
                      onTap: () => Navigator.pop(ctx, mode),
                    ),
                ],
              ),
            ),
          ),
    );
    if (selected != null) {
      await provider.setSortMode(selected);
    }
  }

  Future<void> _batchDownload(
    BuildContext context,
    BookshelfProvider provider,
  ) async {
    try {
      final result = await provider.batchDownload(_selectedUrls);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已加入 ${result.queuedBooks} 本、${result.queuedChapters} 章；略過 ${result.skippedBooks} 本',
          ),
        ),
      );
      setState(() {
        _isMultiSelect = false;
        _selectedUrls.clear();
      });
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('批次下載失敗: $e')));
    }
  }

  Future<void> _batchEnsureComplete(
    BuildContext context,
    BookshelfProvider provider,
  ) async {
    try {
      final result = await provider.batchEnsureComplete(_selectedUrls);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.queuedBooks > 0
                ? '已加入 ${result.queuedBooks} 本、${result.queuedChapters} 章補下載；略過 ${result.skippedBooks} 本'
                : '所有選取書籍已下載完整',
          ),
        ),
      );
      setState(() {
        _isMultiSelect = false;
        _selectedUrls.clear();
      });
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('整本書補下載失敗: $e')));
    }
  }

  Future<void> _batchCheckUpdate(
    BuildContext context,
    BookshelfProvider provider,
  ) async {
    try {
      final results = await provider.batchCheckUpdate(_selectedUrls);
      final updated = results.where((result) => result.hasUpdate).length;
      final chapters = results.fold<int>(
        0,
        (sum, result) => sum + result.newChapterCount,
      );
      final failed = results.where((result) => result.failed).length;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('檢查完成：$updated 本有更新、$chapters 個新章節、$failed 本失敗'),
        ),
      );
      setState(() {
        _isMultiSelect = false;
        _selectedUrls.clear();
      });
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('批次檢查更新失敗: $e')));
    }
  }

  Widget _buildListView(BookshelfProvider provider) {
    if (!_isMultiSelect && provider.sortMode == BookshelfSortMode.custom) {
      return ReorderableListView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: provider.books.length,
        onReorderItem: provider.reorderBooks,
        itemBuilder:
            (context, index) => Padding(
              key: ValueKey(provider.books[index].bookUrl),
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _buildBookItem(context, provider.books[index]),
            ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: provider.books.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder:
          (context, index) => _buildBookItem(context, provider.books[index]),
    );
  }

  Widget _buildGridView(BookshelfProvider provider) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.55,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: provider.books.length,
      itemBuilder:
          (context, index) => _buildGridItem(context, provider.books[index]),
    );
  }

  Widget _buildGridItem(BuildContext context, Book book) {
    final isSelected = _selectedUrls.contains(book.bookUrl);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final borderColor =
        isSelected
            ? theme.colorScheme.primary
            : (isDark ? const Color(0x1EF4EDD7) : const Color(0x16241C10));
    final fgPrimary = isDark ? AppPalette.ink50 : AppPalette.ink700;

    return InkWell(
      onLongPress: _isMultiSelect ? null : () => _openDetail(context, book),
      onTap: () {
        if (_isMultiSelect) {
          setState(() {
            isSelected
                ? _selectedUrls.remove(book.bookUrl)
                : _selectedUrls.add(book.bookUrl);
          });
        } else {
          _openBook(context, book);
        }
      },
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 0.72,
                child: Hero(
                  tag: 'book_cover_${book.bookUrl}',
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: borderColor,
                        width: isSelected ? 2 : 1,
                      ),
                      borderRadius: AppRadius.cardXs,
                      boxShadow:
                          theme.cardTheme.shadowColor != null
                              ? [
                                BoxShadow(
                                  color: theme.cardTheme.shadowColor!,
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                              : [],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.xs - 1),
                      child: BookCoverWidget(
                        bookName: book.name,
                        coverUrl: book.getDisplayCover(),
                        width: double.infinity,
                        height: double.infinity,
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                book.name,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamilySerif,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  color: fgPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Container(
                height: 2,
                decoration: BoxDecoration(
                  color: borderColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor:
                        book.totalChapterNum > 0
                            ? (book.chapterIndex / book.totalChapterNum).clamp(
                              0.0,
                              1.0,
                            )
                            : 0.0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_isMultiSelect)
            Positioned(
              right: 4,
              top: 4,
              child: Icon(
                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isSelected ? theme.colorScheme.primary : Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBookItem(BuildContext context, Book book) {
    final isSelected = _selectedUrls.contains(book.bookUrl);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final borderColor =
        isSelected
            ? theme.colorScheme.primary
            : (isDark ? const Color(0x1EF4EDD7) : const Color(0x16241C10));
    final fgPrimary = isDark ? AppPalette.ink50 : AppPalette.ink700;
    final fgSecondary = isDark ? AppPalette.ink200 : AppPalette.ink300;
    final fgTertiary = isDark ? const Color(0xFF847B68) : AppPalette.ink200;

    return InkWell(
      onLongPress: _isMultiSelect ? null : () => _openDetail(context, book),
      onTap: () {
        if (_isMultiSelect) {
          setState(() {
            isSelected
                ? _selectedUrls.remove(book.bookUrl)
                : _selectedUrls.add(book.bookUrl);
          });
        } else {
          _openBook(context, book);
        }
      },
      child: Container(
        height: 120,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: AppRadius.cardLg,
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
          boxShadow:
              theme.cardTheme.shadowColor != null
                  ? [
                    BoxShadow(
                      color: theme.cardTheme.shadowColor!,
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                  : [],
        ),
        child: Row(
          children: [
            Hero(
              tag: 'book_cover_${book.bookUrl}',
              child: BookCoverWidget(
                bookName: book.name,
                coverUrl: book.getDisplayCover(),
                width: 72,
                height: 100,
                borderRadius: AppRadius.cardSm,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.name,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamilySerif,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: fgPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    book.author,
                    style: TextStyle(fontSize: 11, color: fgTertiary),
                    maxLines: 1,
                  ),
                  const Spacer(),
                  Text(
                    '讀至: ${book.durChapterTitle}',
                    style: TextStyle(fontSize: 11, color: fgSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '最新: ${book.latestChapterTitle}',
                    style: TextStyle(fontSize: 10, color: fgTertiary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 2,
                    decoration: BoxDecoration(
                      color: borderColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor:
                            book.totalChapterNum > 0
                                ? (book.chapterIndex / book.totalChapterNum)
                                    .clamp(0.0, 1.0)
                                : 0.0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_isMultiSelect)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, Book book) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BookDetailPage(book: book)),
    );
  }

  void _openBook(BuildContext context, Book book) {
    if (book.type == 2) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('有聲書播放功能已移除，請選擇文本書籍。')));
      return;
    }
    Navigator.push(
      context,
      BookOpenRoute(book: book, openTarget: ReaderV2OpenTarget.resume(book)),
    );
  }

  void _showDeleteConfirm(BuildContext context, BookshelfProvider p) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('確認刪除'),
            content: Text('是否從書架刪除這 ${_selectedUrls.length} 本書？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  for (var url in _selectedUrls) {
                    await p.removeFromBookshelf(url);
                  }
                  setState(() {
                    _isMultiSelect = false;
                    _selectedUrls.clear();
                  });
                },
                child: const Text('刪除'),
              ),
            ],
          ),
    );
  }
}
