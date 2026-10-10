import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/search_field.dart';

void main() {
  testWidgets('tapping anywhere on the capsule focuses the field', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: SearchField(controller: controller, hintText: '搜尋'),
          ),
        ),
      ),
    );
    final field = tester.getRect(find.byType(SearchField));
    expect(field.height, SearchField.height);

    // 放大鏡。
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump();
    expect(tester.binding.focusManager.primaryFocus?.context, isNotNull);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    // 膠囊上緣（字高之外）。
    await tester.tapAt(Offset(field.center.dx, field.top + 3));
    await tester.pump();
    expect(
      tester.binding.focusManager.primaryFocus?.context?.widget,
      isA<Focus>(),
    );
    expect(tester.testTextInput.isVisible, isTrue);
  });
}
