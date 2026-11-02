import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/highlight.dart';
import 'package:night_reader/features/reader_v2/features/highlight/reader_v2_highlight_sheet.dart';

void main() {
  final highlight = Highlight(
    id: 1,
    bookName: '書',
    chapterTitle: '第一章',
    quote: '燈下的字句',
  );

  Future<({List<Highlight> saved, List<Highlight> deleted})> pumpSheet(
    WidgetTester tester,
  ) async {
    final saved = <Highlight>[];
    final deleted = <Highlight>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => ReaderV2HighlightSheet(
                  highlight: highlight,
                  onChanged: saved.add,
                  onDelete: deleted.add,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return (saved: saved, deleted: deleted);
  }

  testWidgets('picking a color or style saves right away; the note is saved '
      'once when the sheet closes', (tester) async {
    final (:saved, :deleted) = await pumpSheet(tester);
    expect(find.text('燈下的字句'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('綠'));
    await tester.pump();
    expect(saved.single.color, HighlightColor.green);

    await tester.tap(find.text('底線'));
    await tester.pump();
    expect(saved.last.style, HighlightStyle.underline);
    expect(saved.last.color, HighlightColor.green);

    await tester.enterText(find.byType(TextField), ' 想起外婆的墨盒 ');
    await tester.pump();
    expect(saved, hasLength(2), reason: '打字時不存');

    Navigator.of(tester.element(find.text('燈下的字句'))).pop();
    await tester.pumpAndSettle();
    expect(saved, hasLength(3));
    expect(saved.last.note, '想起外婆的墨盒');
    expect(saved.last.style, HighlightStyle.underline);
    expect(deleted, isEmpty);
  });

  testWidgets('刪除 hands over the highlight and does not save it back', (
    tester,
  ) async {
    final (:saved, :deleted) = await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), '寫了一半');
    await tester.ensureVisible(find.text('刪除'));
    await tester.tap(find.text('刪除'));
    await tester.pumpAndSettle();
    expect(deleted.single.id, 1);
    expect(deleted.single.note, '寫了一半', reason: '復原時備忘也回來');
    expect(saved, isEmpty);
  });
}
