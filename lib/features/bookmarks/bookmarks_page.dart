import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/bookmark.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/features/reader_v2/features/bookmark/reader_v2_bookmarks.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_open_target.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/shared/navigation/book_open_route.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/swipe_actions.dart';

/// 「我的 → 書籤」：所有書的書籤，一本書一組（最近留過書籤的書在上），
/// 組裡照在書裡的先後排。點了開那本書、跳到那一句；書不在手機上時用書名
/// 搜尋。往左滑刪除，提示可「復原」。
///
/// 書籤在推入前讀好（[open]），骨架照真的內容畫（ADR 0029）；之後書籤表
/// 一變（閱讀器裡新增、另一台同步過來）就跟著更新。
class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key, required this.initial});

  final List<Bookmark> initial;

  /// 讀好書籤再推入這一頁。
  static Future<void> open(BuildContext context) async {
    final items = await getIt<BookmarkDao>().getAll();
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => BookmarksPage(initial: items)),
    );
  }

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  late List<Bookmark> _items = widget.initial;
  StreamSubscription<List<Bookmark>>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = getIt<BookmarkDao>().watchAll().listen((items) {
      if (mounted) setState(() => _items = items);
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  /// 一本書（書名加作者）一組，最近留過書籤的書在上；組裡照在書裡的
  /// 先後排。
  List<List<Bookmark>> get _groups {
    final books = <String, List<Bookmark>>{};
    for (final item in _items) {
      (books['${item.bookName}\t${item.bookAuthor}'] ??= []).add(item);
    }
    int latest(List<Bookmark> group) =>
        group.map((b) => b.id).reduce((a, b) => a > b ? a : b);
    return [
      for (final group in books.values)
        group..sort(
          (a, b) => a.chapterIndex != b.chapterIndex
              ? a.chapterIndex.compareTo(b.chapterIndex)
              : a.charOffset.compareTo(b.charOffset),
        ),
    ]..sort((a, b) => latest(b).compareTo(latest(a)));
  }

  /// 書籤跟著書名加作者（ADR 0042）：手機上有這本書（書架上的優先，其次
  /// 最近讀的那本）就開它、跳到那一句；沒有就用書名搜尋。
  Future<void> _open(Bookmark bookmark) async {
    final candidates = await getIt<BookDao>().getByName(bookmark.bookName);
    Book? book;
    for (final candidate in candidates) {
      if (candidate.author != bookmark.bookAuthor) continue;
      if (book == null ||
          (candidate.isInBookshelf && !book.isInBookshelf) ||
          (candidate.isInBookshelf == book.isInBookshelf &&
              candidate.durChapterTime > book.durChapterTime)) {
        book = candidate;
      }
    }
    if (book == null) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => SearchPage(initialQuery: bookmark.bookName),
        ),
      );
      return;
    }
    final chapters = await getIt<ChapterDao>().getByBook(book.bookUrl);
    if (!mounted) return;
    await Navigator.push(
      context,
      BookOpenRoute(
        book: book,
        initialChapters: chapters,
        openTarget: ReaderV2OpenTarget.location(
          ReaderV2Bookmarks.locationOf(
            bookmark,
            chapterIndex: ReaderV2Bookmarks.chapterIndexIn(bookmark, chapters),
          ),
        ),
      ),
    );
  }

  void _delete(Bookmark bookmark) {
    final dao = getIt<BookmarkDao>();
    unawaited(dao.deleteByIds([bookmark.id]));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('已刪除書籤'),
          action: SnackBarAction(
            label: '復原',
            onPressed: () => unawaited(dao.upsertAll([bookmark])),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassNavHeader(title: '書籤'),
      body: _items.isEmpty
          ? Padding(
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
              child: const AppStateView(
                icon: Icons.bookmark_border_rounded,
                title: '沒有書籤',
              ),
            )
          : SwipeActionsGroup(
              child: GroupedListView(
                children: [
                  for (final group in _groups)
                    GroupedSection(
                      header: context.zh(group.first.bookName),
                      children: [
                        for (final bookmark in group)
                          SwipeActions(
                            key: ValueKey(bookmark.id),
                            trailing: [
                              SwipeAction(
                                label: '刪除',
                                icon: Icons.delete_outline_rounded,
                                color: AppTint.rust.color,
                                destructive: true,
                                onPressed: () => _delete(bookmark),
                              ),
                            ],
                            child: GroupedRow(
                              title: context.zh(bookmark.excerpt),
                              maxTitleLines: 2,
                              subtitle: context.zh(bookmark.chapterTitle),
                              maxSubtitleLines: 1,
                              showChevron: false,
                              onTap: () => unawaited(_open(bookmark)),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}
