import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/chapter.dart';
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
            currentChapterIndex: 3,
            titleFor: (index) => chapters[index].title,
            onChapterTap: (_) async => false,
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
}
