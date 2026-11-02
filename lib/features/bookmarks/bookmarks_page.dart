import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/bookmark.dart';
import 'package:night_reader/core/models/chapter.dart';
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
/// 書籤與每本書在這台的目錄在推入前讀好（[open]），骨架照真的內容畫、
/// 排序照這台目錄的章（ADR 0029、0042）；之後書籤表一變（閱讀器裡新增、
/// 另一台同步過來）就跟著更新。
class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key, required this.initial, this.tocs = const {}});

  final List<Bookmark> initial;

  /// 每本書（[keyOf]）在這台的目錄；手機上沒有這本書或還沒抓目錄時沒有，
  /// 那本書的書籤照記下的章節序號排。
  final Map<String, List<BookChapter>> tocs;

  static String keyOf(Bookmark bookmark) =>
      '${bookmark.bookName}\t${bookmark.bookAuthor}';

  /// 讀好書籤與各本書的目錄再推入這一頁。
  static Future<void> open(BuildContext context) async {
    final items = await getIt<BookmarkDao>().getAll();
    final tocs = <String, List<BookChapter>>{};
    for (final bookmark in items) {
      final key = keyOf(bookmark);
      if (tocs.containsKey(key)) continue;
      final book = await _findBook(bookmark);
      tocs[key] = book == null
          ? const []
          : await getIt<ChapterDao>().getByBook(book.bookUrl);
    }
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BookmarksPage(initial: items, tocs: tocs),
      ),
    );
  }

  /// 書籤跟著書名加作者（ADR 0042）：手機上的這本書，書架上的優先，其次
  /// 最近讀的那本（同閱讀統計）。
  static Future<Book?> _findBook(Bookmark bookmark) async {
    Book? book;
    for (final candidate in await getIt<BookDao>().getByName(
      bookmark.bookName,
    )) {
      if (candidate.author != bookmark.bookAuthor) continue;
      if (book == null ||
          (candidate.isInBookshelf && !book.isInBookshelf) ||
          (candidate.isInBookshelf == book.isInBookshelf &&
              candidate.durChapterTime > book.durChapterTime)) {
        book = candidate;
      }
    }
    return book;
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
  /// 先後排：章照這台目錄（書籤可能來自另一個書源，記下的序號是那邊的），
  /// 同一章照第幾個字。
  List<List<Bookmark>> get _groups {
    final books = <String, List<Bookmark>>{};
    for (final item in _items) {
      (books[BookmarksPage.keyOf(item)] ??= []).add(item);
    }
    int latest(List<Bookmark> group) =>
        group.map((b) => b.id).reduce((a, b) => a > b ? a : b);
    return [
      for (final MapEntry(:key, value: group) in books.entries)
        _inReadingOrder(group, widget.tocs[key] ?? const []),
    ]..sort((a, b) => latest(b).compareTo(latest(a)));
  }

  static List<Bookmark> _inReadingOrder(
    List<Bookmark> group,
    List<BookChapter> toc,
  ) {
    final chapterOf = {
      for (final bookmark in group)
        bookmark.id: ReaderV2Bookmarks.chapterIndexIn(bookmark, toc),
    };
    return group..sort((a, b) {
      final byChapter = chapterOf[a.id]!.compareTo(chapterOf[b.id]!);
      return byChapter != 0 ? byChapter : a.charOffset.compareTo(b.charOffset);
    });
  }

  /// 手機上有這本書就開它、跳到那一句；沒有就用書名搜尋。
  Future<void> _open(Bookmark bookmark) async {
    final book = await BookmarksPage._findBook(bookmark);
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
        // 目錄還沒抓時（剛還原、剛同步來的書），閱讀器讀到目錄後再照章名
        // 對一次章。
        openTarget: ReaderV2OpenTarget.location(
          ReaderV2Bookmarks.locationOf(
            bookmark,
            chapterIndex: ReaderV2Bookmarks.chapterIndexIn(bookmark, chapters),
          ),
          chapterTitle: bookmark.chapterTitle,
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
