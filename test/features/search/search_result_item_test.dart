import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/features/search/widgets/search_result_item.dart';

void main() {
  test('metadata 只串接有內容的欄位', () {
    expect(
      formatSearchResultMetadata(
        author: ' 作者甲 ',
        kind: null,
        wordCount: '12 萬字',
      ),
      '作者甲 · 12 萬字',
    );
    expect(formatSearchResultMetadata(), '資訊未提供');
  });

  testWidgets('缺少 metadata 時不顯示多餘分隔符，最新章節使用次要文字色', (tester) async {
    final result = AggregatedSearchBook(
      book: SearchBook(bookUrl: 'book://1', name: '測試書', origin: 'source://1'),
      sources: const ['測試書源'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SearchResultItem(result: result)),
      ),
    );

    expect(find.text('資訊未提供'), findsOneWidget);
    expect(find.textContaining('未知 · 未知 ·'), findsNothing);
    expect(find.text('來源：測試書源'), findsOneWidget);

    final latest = tester.widget<Text>(find.text('最新：暫無'));
    final context = tester.element(find.text('最新：暫無'));
    expect(latest.style?.color, Theme.of(context).colorScheme.onSurfaceVariant);
  });
}
