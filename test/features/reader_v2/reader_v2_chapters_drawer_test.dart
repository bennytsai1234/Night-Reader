import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_chapters_drawer.dart';

void main() {
  testWidgets('跳章成功後才關閉目錄', (tester) async {
    final result = Completer<bool>();
    final tappedIndices = <int>[];

    await tester.pumpWidget(
      _drawerRouteApp((index) {
        tappedIndices.add(index);
        return result.future;
      }),
    );
    await tester.tap(find.text('開啟目錄'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('第二章'));
    await tester.pump();

    expect(tappedIndices, <int>[1]);
    expect(find.text('第二章'), findsOneWidget);

    result.complete(true);
    await tester.pumpAndSettle();

    expect(find.text('首頁'), findsOneWidget);
    expect(find.text('第二章'), findsNothing);
  });

  testWidgets('跳章失敗時保留目錄並恢復操作', (tester) async {
    final result = Completer<bool>();

    await tester.pumpWidget(_drawerRouteApp((_) => result.future));
    await tester.tap(find.text('開啟目錄'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第一章'));
    await tester.pump();

    result.complete(false);
    await tester.pump();

    expect(find.text('第一章'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester
          .widgetList<ListTile>(find.byType(ListTile))
          .every((tile) => tile.onTap != null),
      isTrue,
    );
  });

  testWidgets('pending 時只顯示被點章節的語意進度並防止重複點擊', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final result = Completer<bool>();
      final tappedIndices = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _drawer((index) {
              tappedIndices.add(index);
              return result.future;
            }),
          ),
        ),
      );

      await tester.tap(find.text('第一章'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.bySemanticsLabel('正在跳轉至第一章'), findsOneWidget);
      expect(
        tester
            .widgetList<ListTile>(find.byType(ListTile))
            .every((tile) => tile.onTap == null),
        isTrue,
      );

      await tester.tap(find.text('第二章'));
      await tester.pump();

      expect(tappedIndices, <int>[0]);

      result.complete(false);
      await tester.pump();
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('dispose 後的延遲完成不會再更新或關閉界面', (tester) async {
    final result = Completer<bool>();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: _drawer((_) => result.future))),
    );
    await tester.tap(find.text('第一章'));
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    result.complete(true);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

Widget _drawerRouteApp(Future<bool> Function(int index) onChapterTap) {
  return MaterialApp(
    home: Builder(
      builder:
          (context) => Scaffold(
            body: Column(
              children: [
                const Text('首頁'),
                TextButton(
                  onPressed: () {
                    unawaited(
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(body: _drawer(onChapterTap)),
                        ),
                      ),
                    );
                  },
                  child: const Text('開啟目錄'),
                ),
              ],
            ),
          ),
    ),
  );
}

ReaderV2ChaptersDrawer _drawer(Future<bool> Function(int index) onChapterTap) {
  final chapters = <BookChapter>[
    BookChapter(title: '第一章'),
    BookChapter(title: '第二章'),
    BookChapter(title: '第三章'),
  ];
  return ReaderV2ChaptersDrawer(
    chapters: chapters,
    currentChapterIndex: 0,
    titleFor: (index) => chapters[index].title,
    onChapterTap: onChapterTap,
  );
}
