import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/core/models/bookmark.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/highlight.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/core/services/highlight_export.dart';
import 'package:night_reader/features/reader_v2/features/bookmark/reader_v2_bookmarks.dart';
import 'package:night_reader/features/reader_v2/features/highlight/reader_v2_highlights.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/highlight_marks.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_open_target.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/shared/navigation/book_open_route.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_segmented.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/swipe_actions.dart';

/// 「我的 → 書籤與標註」：頂端分段切換書籤與標註，兩頁都是一本書一組
/// （最近留過的書在上），組裡照在書裡的先後排。點了開那本書、跳過去；書不
/// 在手機上時用書名搜尋。往左滑刪除，提示可「復原」。標註頁可以匯出。
///
/// 書籤、標註與每本書在這台的目錄在推入前讀好（[open]），骨架照真的內容
/// 畫、排序照這台目錄的章（ADR 0029、0042）；之後資料表一變（閱讀器裡
/// 新增、另一台同步過來）就跟著更新。
class BookmarksPage extends StatefulWidget {
  const BookmarksPage({
    super.key,
    required this.initial,
    this.initialHighlights = const [],
    this.tocs = const {},
  });

  final List<Bookmark> initial;
  final List<Highlight> initialHighlights;

  /// 每本書（[keyOf]）在這台的目錄；手機上沒有這本書或還沒抓目錄時沒有，
  /// 那本書的書籤與標註照記下的章節序號排。
  final Map<String, List<BookChapter>> tocs;

  static String keyOf(String bookName, String bookAuthor) =>
      '$bookName\t$bookAuthor';

  /// 讀好書籤、標註與各本書的目錄再推入這一頁。
  static Future<void> open(BuildContext context) async {
    final items = await getIt<BookmarkDao>().getAll();
    final highlights = await getIt<HighlightDao>().getAll();
    final tocs = <String, List<BookChapter>>{};
    for (final (name, author) in [
      for (final bookmark in items) (bookmark.bookName, bookmark.bookAuthor),
      for (final highlight in highlights)
        (highlight.bookName, highlight.bookAuthor),
    ]) {
      final key = keyOf(name, author);
      if (tocs.containsKey(key)) continue;
      final book = await _findBook(name, author);
      tocs[key] = book == null
          ? const []
          : await getIt<ChapterDao>().getByBook(book.bookUrl);
    }
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BookmarksPage(
          initial: items,
          initialHighlights: highlights,
          tocs: tocs,
        ),
      ),
    );
  }

  /// 書籤與標註跟著書名加作者（ADR 0042）：手機上的這本書，書架上的優先，
  /// 其次最近讀的那本（同閱讀統計）。[name] 是記錄裡的書名，帶類別前綴
  /// （ADR 0053）。
  static Future<Book?> _findBook(String name, String author) async {
    Book? book;
    for (final candidate in await getIt<BookDao>().getByRecordName(name)) {
      if (candidate.author != author) continue;
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

enum _Tab { bookmarks, highlights }

/// 一列要的東西：書籤與標註共用分組、排序與開書。
typedef _Entry = ({
  int id,
  String bookName,
  String bookAuthor,
  int chapterIndex,
  String chapterTitle,
  int charOffset,
});

class _BookmarksPageState extends State<BookmarksPage> {
  static const double _tabsHeight =
      GlassSegmented.trackHeight + AppSpacing.xs * 2;

  late List<Bookmark> _items = widget.initial;
  late List<Highlight> _highlights = widget.initialHighlights;
  StreamSubscription<List<Bookmark>>? _subscription;
  StreamSubscription<List<Highlight>>? _highlightSubscription;
  _Tab _tab = _Tab.bookmarks;

  @override
  void initState() {
    super.initState();
    _subscription = getIt<BookmarkDao>().watchAll().listen((items) {
      if (mounted) setState(() => _items = items);
    });
    _highlightSubscription = getIt<HighlightDao>().watchAll().listen((items) {
      if (mounted) setState(() => _highlights = items);
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_highlightSubscription?.cancel());
    super.dispose();
  }

  static _Entry _bookmarkEntry(Bookmark b) => (
    id: b.id,
    bookName: b.bookName,
    bookAuthor: b.bookAuthor,
    chapterIndex: b.chapterIndex,
    chapterTitle: b.chapterTitle,
    charOffset: b.charOffset,
  );

  static _Entry _highlightEntry(Highlight h) => (
    id: h.id,
    bookName: h.bookName,
    bookAuthor: h.bookAuthor,
    chapterIndex: h.chapterIndex,
    chapterTitle: h.chapterTitle,
    charOffset: h.charOffset,
  );

  /// 一本書（書名加作者）一組，最近留過的書在上；組裡照在書裡的先後排：
  /// 章照這台目錄（可能來自另一個書源，記下的序號是那邊的），同一章照第幾
  /// 個字。
  List<List<T>> _groups<T>(List<T> items, _Entry Function(T item) entryOf) {
    final books = <String, List<T>>{};
    for (final item in items) {
      final entry = entryOf(item);
      (books[BookmarksPage.keyOf(entry.bookName, entry.bookAuthor)] ??= []).add(
        item,
      );
    }
    int latest(List<T> group) =>
        group.map((item) => entryOf(item).id).reduce((a, b) => a > b ? a : b);
    return [
      for (final MapEntry(:key, value: group) in books.entries)
        _inReadingOrder(group, widget.tocs[key] ?? const [], entryOf),
    ]..sort((a, b) => latest(b).compareTo(latest(a)));
  }

  static List<T> _inReadingOrder<T>(
    List<T> group,
    List<BookChapter> toc,
    _Entry Function(T item) entryOf,
  ) {
    final chapterOf = {
      for (final item in group)
        entryOf(item).id: chapterIndexByTitle(
          chapterIndex: entryOf(item).chapterIndex,
          chapterTitle: entryOf(item).chapterTitle,
          chapters: toc,
        ),
    };
    return group..sort((x, y) {
      final a = entryOf(x);
      final b = entryOf(y);
      final byChapter = chapterOf[a.id]!.compareTo(chapterOf[b.id]!);
      return byChapter != 0 ? byChapter : a.charOffset.compareTo(b.charOffset);
    });
  }

  /// 手機上有這本書就開它、跳到 [locationOf] 給的位置；沒有就用書名搜尋。
  Future<void> _open(
    _Entry entry,
    ReaderV2Location Function(int chapterIndex) locationOf,
  ) async {
    final book = await BookmarksPage._findBook(
      entry.bookName,
      entry.bookAuthor,
    );
    if (book == null) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) {
            final record = BookSourceKind.splitRecordName(entry.bookName);
            return SearchPage(
              initialQuery: record.name,
              initialKind: record.kind,
            );
          },
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
          locationOf(
            chapterIndexByTitle(
              chapterIndex: entry.chapterIndex,
              chapterTitle: entry.chapterTitle,
              chapters: chapters,
            ),
          ),
          chapterTitle: entry.chapterTitle,
        ),
      ),
    );
  }

  void _showUndo(String message, VoidCallback undo) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(label: '復原', onPressed: undo),
        ),
      );
  }

  void _delete(Bookmark bookmark) {
    final dao = getIt<BookmarkDao>();
    unawaited(dao.deleteByIds([bookmark.id]));
    _showUndo('已刪除書籤', () => unawaited(dao.upsertAll([bookmark])));
  }

  void _deleteHighlight(Highlight highlight) {
    final dao = getIt<HighlightDao>();
    unawaited(dao.deleteByIds([highlight.id]));
    _showUndo('已刪除標註', () => unawaited(dao.upsertAll([highlight])));
  }

  /// 所有書的標註匯出成一個檔，照這頁的順序。
  void _exportHighlights() {
    unawaited(
      shareHighlights([
        for (final group in _groups(_highlights, _highlightEntry))
          (
            bookName: BookSourceKind.splitRecordName(group.first.bookName).name,
            bookAuthor: group.first.bookAuthor,
            items: group,
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassNavHeader(
        title: '書籤與標註',
        actions: [
          if (_tab == _Tab.highlights && _highlights.isNotEmpty)
            GlassIconButton(
              tooltip: '匯出標註',
              icon: Icons.ios_share_rounded,
              onPressed: _exportHighlights,
            ),
        ],
        bottomHeight: _tabsHeight,
        bottom: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppGrouped.margin,
            AppSpacing.xs,
            AppGrouped.margin,
            AppSpacing.xs,
          ),
          child: GlassSegmented<_Tab>(
            segments: const [
              GlassSegment(_Tab.bookmarks, '書籤'),
              GlassSegment(_Tab.highlights, '標註'),
            ],
            selected: _tab,
            onChanged: (tab) => setState(() => _tab = tab),
          ),
        ),
      ),
      body: switch (_tab) {
        _Tab.bookmarks => _buildBookmarks(context),
        _Tab.highlights => _buildHighlights(context),
      },
    );
  }

  Widget _empty(BuildContext context, IconData icon, String title) => Padding(
    padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
    child: AppStateView(icon: icon, title: title),
  );

  Widget _buildBookmarks(BuildContext context) {
    if (_items.isEmpty) {
      return _empty(context, Icons.bookmark_border_rounded, '沒有書籤');
    }
    return SwipeActionsGroup(
      key: const ValueKey(_Tab.bookmarks),
      child: GroupedListView(
        children: [
          for (final group in _groups(_items, _bookmarkEntry))
            GroupedSection(
              header: context.zh(
                BookSourceKind.splitRecordName(group.first.bookName).name,
              ),
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
                      onTap: () => unawaited(
                        _open(
                          _bookmarkEntry(bookmark),
                          (chapterIndex) => ReaderV2Bookmarks.locationOf(
                            bookmark,
                            chapterIndex: chapterIndex,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildHighlights(BuildContext context) {
    if (_highlights.isEmpty) {
      return _empty(context, Icons.border_color_outlined, '沒有標註');
    }
    return SwipeActionsGroup(
      key: const ValueKey(_Tab.highlights),
      child: GroupedListView(
        children: [
          for (final group in _groups(_highlights, _highlightEntry))
            GroupedSection(
              header: context.zh(
                BookSourceKind.splitRecordName(group.first.bookName).name,
              ),
              children: [
                for (final highlight in group)
                  SwipeActions(
                    key: ValueKey(highlight.id),
                    trailing: [
                      SwipeAction(
                        label: '刪除',
                        icon: Icons.delete_outline_rounded,
                        color: AppTint.rust.color,
                        destructive: true,
                        onPressed: () => _deleteHighlight(highlight),
                      ),
                    ],
                    child: GroupedRow(
                      leading: HighlightColorBar(color: highlight.color),
                      title: context.zh(highlight.quote),
                      maxTitleLines: 3,
                      // 章名一行，有備忘時接在下面（最多兩行）。備忘是
                      // 自己寫的，不做繁簡轉換。
                      subtitle: [
                        context.zh(highlight.chapterTitle),
                        if (highlight.note.isNotEmpty) highlight.note,
                      ].join('\n'),
                      maxSubtitleLines: highlight.note.isEmpty ? 1 : 3,
                      showChevron: false,
                      onTap: () => unawaited(
                        _open(
                          _highlightEntry(highlight),
                          (chapterIndex) => ReaderV2Highlights.locationOf(
                            highlight,
                            chapterIndex: chapterIndex,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
