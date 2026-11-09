import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/features/search/widgets/search_result_item.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

/// 同名的小說、漫畫、有聲書是不同的卡，漫畫、有聲書的封面角落放記號
/// （ADR 0053）。
void main() {
  Future<void> pumpResult(WidgetTester tester, int type) => tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(AppStyle.paper, Brightness.light),
      home: Scaffold(
        body: SearchResultItem(
          result: AggregatedSearchBook(
            book: SearchBook(
              bookUrl: 'u',
              name: '夜航',
              author: '江南',
              origin: 's',
              type: type,
            ),
            sources: const ['s'],
          ),
        ),
      ),
    ),
  );

  testWidgets('comic and audio cards carry a mark, novels do not', (
    tester,
  ) async {
    await pumpResult(tester, 2);
    expect(find.byIcon(Icons.auto_stories_outlined), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '漫畫',
      ),
      findsOneWidget,
    );

    await pumpResult(tester, 1);
    expect(find.byIcon(Icons.headphones_outlined), findsOneWidget);

    await pumpResult(tester, 0);
    expect(find.byIcon(Icons.auto_stories_outlined), findsNothing);
    expect(find.byIcon(Icons.headphones_outlined), findsNothing);
  });
}
