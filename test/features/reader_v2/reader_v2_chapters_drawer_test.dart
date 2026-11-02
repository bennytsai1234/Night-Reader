import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/bookmark.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/highlight.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_chapters_drawer.dart';
import 'package:night_reader/shared/widgets/locked_chapter_icon.dart';

void main() {
  testWidgets('paid chapters not bought yet show a lock, except the current '
      'one, which keeps its check mark', (tester) async {
    final chapters = [
      BookChapter(url: '/c/1', title: '第一章'),
      BookChapter(url: '/c/2', title: '第二章', isVip: true),
      BookChapter(url: '/c/3', title: '第三章', isVip: true, isPay: true),
      BookChapter(url: '/c/4', title: '第四章', isVip: true),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderV2ChaptersDrawer(
            chapters: chapters,
            currentChapter: ValueNotifier(3),
            titleFor: (index) => chapters[index].title,
            onChapterTap: (_) {},
          ),
        ),
      ),
    );

    Finder lockIn(String title) => find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(Row)).first,
      matching: find.byType(LockedChapterIcon),
    );

    expect(lockIn('第一章'), findsNothing);
    expect(lockIn('第二章'), findsOneWidget);
    expect(lockIn('第三章'), findsNothing);
    expect(lockIn('第四章'), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('the bookmarks tab lists each bookmark with its chapter; tapping '
      'one jumps, swiping it away deletes it', (tester) async {
    final chapters = [
      BookChapter(url: '/c/1', title: '第一章'),
      BookChapter(url: '/c/2', title: '第二章'),
    ];
    final bookmarks = ValueNotifier<List<Bookmark>>([
      Bookmark(
        id: 1,
        bookName: '書',
        chapterIndex: 1,
        chapterTitle: '第二章',
        excerpt: '燈下的字句彷彿活了過來',
      ),
    ]);
    Bookmark? tapped;
    Bookmark? deleted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderV2ChaptersDrawer(
            chapters: chapters,
            currentChapter: ValueNotifier(0),
            titleFor: (index) => chapters[index].title,
            onChapterTap: (_) {},
            bookmarks: bookmarks,
            bookmarkChapter: (bookmark) => bookmark.chapterIndex,
            onBookmarkTap: (bookmark) => tapped = bookmark,
            onBookmarkDelete: (bookmark) => deleted = bookmark,
          ),
        ),
      ),
    );

    expect(find.text('共 2 章'), findsOneWidget);
    expect(find.text('燈下的字句彷彿活了過來'), findsNothing);

    await tester.tap(find.text('書籤'));
    await tester.pumpAndSettle();
    expect(find.text('燈下的字句彷彿活了過來'), findsOneWidget);
    expect(find.text('1 個'), findsOneWidget);
    // 列上寫書籤在哪一章；目錄那一頁還留著，切回來不用重新捲。
    expect(
      find.descendant(
        of: find.byType(GroupedRow).last,
        matching: find.text('第二章'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('燈下的字句彷彿活了過來'));
    expect(tapped?.id, 1);

    await tester.drag(find.text('燈下的字句彷彿活了過來'), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(deleted?.id, 1);

    bookmarks.value = const [];
    await tester.pumpAndSettle();
    expect(find.text('沒有書籤'), findsOneWidget);
  });

  testWidgets('the highlights tab lists highlights in reading order; tapping '
      'one jumps, swiping deletes, 匯出 hands over the list', (tester) async {
    final chapters = [
      BookChapter(url: '/c/1', title: '第一章'),
      BookChapter(url: '/c/2', title: '第二章'),
    ];
    final highlights = ValueNotifier<List<Highlight>>([
      Highlight(
        id: 2,
        bookName: '書',
        chapterIndex: 1,
        chapterTitle: '第二章',
        quote: '後面畫的字',
      ),
      Highlight(
        id: 1,
        bookName: '書',
        chapterIndex: 0,
        chapterTitle: '第一章',
        charOffset: 5,
        quote: '前面畫的字',
        note: '自己寫的備忘',
      ),
    ]);
    Highlight? tapped;
    Highlight? deleted;
    List<Highlight>? exported;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderV2ChaptersDrawer(
            chapters: chapters,
            currentChapter: ValueNotifier(0),
            titleFor: (index) => chapters[index].title,
            onChapterTap: (_) {},
            bookmarks: ValueNotifier(const []),
            highlights: highlights,
            highlightChapter: (highlight) => highlight.chapterIndex,
            onHighlightTap: (highlight) => tapped = highlight,
            onHighlightDelete: (highlight) => deleted = highlight,
            onHighlightExport: (items) => exported = items,
          ),
        ),
      ),
    );

    expect(find.text('目錄'), findsOneWidget);
    expect(find.text('書籤'), findsOneWidget);
    await tester.tap(find.text('標註'));
    await tester.pumpAndSettle();
    expect(find.text('2 個'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('前面畫的字')).dy,
      lessThan(tester.getTopLeft(find.text('後面畫的字')).dy),
    );

    expect(find.text('第一章\n自己寫的備忘'), findsOneWidget);

    await tester.tap(find.byTooltip('匯出'));
    expect(exported?.map((h) => h.id), [1, 2]);

    await tester.tap(find.text('前面畫的字'));
    expect(tapped?.id, 1);

    await tester.drag(find.text('後面畫的字'), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(deleted?.id, 2);

    highlights.value = const [];
    await tester.pumpAndSettle();
    expect(find.text('沒有標註'), findsOneWidget);
  });

  testWidgets('volumes read before the current one open collapsed; tapping a '
      'volume collapses or expands it, and the scrollbar counts rows', (
    tester,
  ) async {
    final chapters = [
      BookChapter(url: '/v1', title: '第一卷 雨夜書鋪', isVolume: true),
      BookChapter(url: '/c/1', title: '第1章 開門'),
      BookChapter(url: '/c/2', title: '第2章 雨'),
      BookChapter(url: '/v2', title: '第二卷 夜讀', isVolume: true),
      BookChapter(url: '/c/3', title: '第3章 少年'),
      BookChapter(url: '/c/4', title: '第4章 匣蓋'),
    ];
    final tapped = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderV2ChaptersDrawer(
            chapters: chapters,
            currentChapter: ValueNotifier(4),
            titleFor: (index) => chapters[index].title,
            onChapterTap: tapped.add,
          ),
        ),
      ),
    );

    expect(find.text('共 4 章'), findsOneWidget);
    expect(find.text('2 章'), findsNWidgets(2));
    expect(find.text('第1章 開門'), findsNothing);
    expect(find.text('第3章 少年'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.tap(find.text('第一卷 雨夜書鋪'));
    await tester.pump();
    expect(find.text('第1章 開門'), findsOneWidget);
    expect(tapped, isEmpty, reason: '點分卷只收起或展開，不跳過去');

    await tester.tap(find.text('第二卷 夜讀'));
    await tester.pump();
    expect(find.text('第3章 少年'), findsNothing);

    // 卷內的章往右縮一個字：比卷名的字往右。
    final volumeLeft = tester.getTopLeft(find.text('第一卷 雨夜書鋪')).dx;
    final chapterLeft = tester.getTopLeft(find.text('第1章 開門')).dx;
    expect(chapterLeft - volumeLeft, closeTo(15, 0.5));

    await tester.tap(find.text('第1章 開門'));
    expect(tapped, [1]);
  });

  testWidgets('moving to a volume row expands it; a new copy of the table of '
      'contents with chapters added at the end keeps what was collapsed', (
    tester,
  ) async {
    BookChapter chapter(String title, {bool volume = false}) =>
        BookChapter(url: '/$title', title: title, isVolume: volume);
    var chapters = [
      chapter('第一卷', volume: true),
      chapter('第1章'),
      chapter('第二卷', volume: true),
      chapter('第2章'),
    ];
    final current = ValueNotifier(1);
    Widget drawer() => MaterialApp(
      home: Scaffold(
        body: ReaderV2ChaptersDrawer(
          chapters: chapters,
          currentChapter: current,
          titleFor: (index) => chapters[index].title,
          onChapterTap: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(drawer());

    await tester.tap(find.text('第二卷'));
    await tester.pump();
    expect(find.text('第2章'), findsNothing);
    current.value = 2;
    await tester.pump();
    expect(find.text('第2章'), findsOneWidget);

    await tester.tap(find.text('第一卷'));
    await tester.pump();
    expect(find.text('第1章'), findsNothing);
    chapters = [...chapters, chapter('第3章')];
    await tester.pumpWidget(drawer());
    expect(find.text('第1章'), findsNothing);
    expect(find.text('第3章'), findsOneWidget);
    expect(find.text('共 3 章'), findsOneWidget);
  });
}
