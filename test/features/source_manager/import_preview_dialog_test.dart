import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/features/source_manager/widgets/import_preview_dialog.dart';

void main() {
  test('preview total does not count unsupported sources twice', () {
    final unsupported = BookSource(
      bookSourceUrl: 'https://audio.example.com',
      bookSourceName: '有聲源',
      bookSourceType: 1,
    );
    final preview = ImportPreviewResult(
      newSources: <BookSource>[unsupported],
      updatedSources: const <BookSource>[],
      unchangedSources: const <BookSource>[],
      unsupportedSources: <BookSource>[unsupported],
    );

    expect(preview.total, 1);
    expect(preview.unsupportedCount, 1);
  });

  testWidgets('preview disables import when there is no selected change', (
    tester,
  ) async {
    final unchanged = BookSource(
      bookSourceUrl: 'https://same.example.com',
      bookSourceName: '未變更書源',
    );
    final preview = ImportPreviewResult(
      newSources: const <BookSource>[],
      updatedSources: const <BookSource>[],
      unchangedSources: <BookSource>[unchanged],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => TextButton(
                onPressed: () => showImportPreviewDialog(context, preview),
                child: const Text('開啟'),
              ),
        ),
      ),
    );
    await tester.tap(find.text('開啟'));
    await tester.pumpAndSettle();

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '匯入 (0)'),
    );
    expect(button.onPressed, isNull);
    expect(find.text('沒有需要匯入的變更'), findsOneWidget);
  });
}
