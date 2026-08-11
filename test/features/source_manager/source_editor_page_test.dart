import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/features/source_manager/source_editor_page.dart';

void main() {
  testWidgets('editor validates trimmed required fields before saving', (
    tester,
  ) async {
    var saveCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SourceEditorPage(
          onSave: (_) async {
            saveCount += 1;
          },
        ),
      ),
    );

    await tester.enterText(find.widgetWithText(TextFormField, '書源名稱'), '  ');
    await tester.enterText(
      find.widgetWithText(TextFormField, '書源網址'),
      '  https://source.example.com  ',
    );
    await tester.tap(find.byTooltip('儲存書源'));
    await tester.pump();

    expect(saveCount, 0);
    expect(find.text('請輸入書源名稱'), findsOneWidget);
  });

  testWidgets('editor keeps the page open and reports save errors', (
    tester,
  ) async {
    final source = BookSource(
      bookSourceUrl: 'https://old.example.com',
      bookSourceName: '原名稱',
    );
    BookSource? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: SourceEditorPage(
          source: source,
          onSave: (editing) async {
            submitted = editing;
            throw StateError('database unavailable');
          },
        ),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '書源名稱'),
      '  新名稱  ',
    );

    await tester.tap(find.byTooltip('儲存書源'));
    await tester.pumpAndSettle();

    expect(find.text('編輯書源'), findsOneWidget);
    expect(find.text('儲存失敗，請稍後再試'), findsOneWidget);
    expect(source.bookSourceName, '原名稱');
    expect(submitted, isNot(same(source)));
    expect(submitted?.bookSourceName, '新名稱');
  });

  testWidgets('editor ignores repeated save taps while a save is pending', (
    tester,
  ) async {
    final completer = Completer<void>();
    var saveCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SourceEditorPage(
          source: BookSource(
            bookSourceUrl: 'https://source.example.com',
            bookSourceName: '書源',
          ),
          onSave: (_) {
            saveCount += 1;
            return completer.future;
          },
        ),
      ),
    );

    await tester.tap(find.byTooltip('儲存書源'));
    await tester.tap(find.byTooltip('儲存書源'));
    await tester.pump();

    expect(saveCount, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('successful save returns a changed result to the caller', (
    tester,
  ) async {
    bool? routeResult;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    routeResult = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => SourceEditorPage(onSave: (_) async {}),
                      ),
                    );
                  },
                  child: const Text('開啟編輯器'),
                ),
              ),
        ),
      ),
    );

    await tester.tap(find.text('開啟編輯器'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '書源名稱'), '書源');
    await tester.enterText(
      find.widgetWithText(TextFormField, '書源網址'),
      'https://source.example.com',
    );
    await tester.tap(find.byTooltip('儲存書源'));
    await tester.pumpAndSettle();

    expect(routeResult, isTrue);
    expect(find.text('開啟編輯器'), findsOneWidget);
  });
}
