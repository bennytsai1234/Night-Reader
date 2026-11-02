import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/book_detail/widgets/book_read_capsule.dart';
import 'package:night_reader/shared/layout/readable_width.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

void main() {
  const row = Key('row');
  const back = Key('back');
  const more = Key('more');
  const below = Key('below');

  Future<void> pumpPage(
    WidgetTester tester,
    Size size, {
    bool readable = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: GlassNavHeader(
            readable: readable,
            title: '閱讀偏好',
            leading: GlassIconButton(
              key: back,
              icon: Icons.arrow_back_ios_new_rounded,
              onPressed: () {},
            ),
            actions: [
              GlassIconButton(
                key: more,
                icon: Icons.more_horiz_rounded,
                onPressed: () {},
              ),
            ],
            bottomHeight: 40,
            bottom: const SizedBox.expand(key: below),
          ),
          body: const GroupedListView(
            children: [SizedBox(key: row, height: 44)],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  test('the column is as wide as a bottom sheet and only narrows on wide '
      'screens', () {
    expect(ReadableWidth.sideOf(400), 0);
    expect(ReadableWidth.sideOf(640), 0);
    expect(ReadableWidth.sideOf(880), 120);
    expect(ReadableWidth.sideOf(1280), 320);
  });

  testWidgets('a phone keeps the list and header buttons where they were', (
    tester,
  ) async {
    await pumpPage(tester, const Size(400, 800));

    expect(tester.getRect(find.byKey(row)).left, 0);
    expect(tester.getRect(find.byKey(row)).right, 400);
    expect(tester.getRect(find.byKey(back)).left, 16);
    expect(tester.getRect(find.byKey(more)).right, 400 - 16);
    expect(tester.getRect(find.byKey(below)).width, 400);
  });

  testWidgets('a landscape tablet centres the list in a 640 column and lines '
      'the header buttons up with the cards', (tester) async {
    await pumpPage(tester, const Size(1280, 880));

    final list = tester.getRect(find.byKey(row));
    expect(list.left, 320);
    expect(list.width, 640);
    // 卡片在內容欄裡左右各留 16，按鈕外緣和卡片邊切齊。
    expect(tester.getRect(find.byKey(back)).left, 320 + 16);
    expect(tester.getRect(find.byKey(more)).right, 960 - 16);
    final bottom = tester.getRect(find.byKey(below));
    expect(bottom.left, 320);
    expect(bottom.width, 640);
  });

  testWidgets('a portrait tablet centres the header buttons in the narrower '
      'margins', (tester) async {
    await pumpPage(tester, const Size(880, 1280));

    expect(tester.getRect(find.byKey(row)).left, 120);
    // 留白 120，按鈕中心在 60。
    expect(tester.getCenter(find.byKey(back)).dx, 60);
    expect(tester.getCenter(find.byKey(more)).dx, 880 - 60);
  });

  for (final (size, left) in [
    (const Size(400, 800), 16.0),
    (const Size(1280, 880), 336.0),
    (const Size(880, 1280), 136.0),
  ]) {
    testWidgets('the read capsule lines up with the cards at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: Scaffold(
            extendBody: true,
            body: const SizedBox.expand(),
            bottomNavigationBar: BookReadCapsule(
              started: true,
              visible: true,
              onPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final capsule = tester.getRect(
        find.descendant(
          of: find.byType(BookReadCapsule),
          matching: find.byType(GlassSurface),
        ),
      );
      expect(capsule.left, left);
      expect(capsule.right, size.width - left);
    });
  }

  testWidgets('a page that fills the screen keeps its header at the edges', (
    tester,
  ) async {
    await pumpPage(tester, const Size(1280, 880), readable: false);

    expect(tester.getRect(find.byKey(back)).left, 16);
    expect(tester.getRect(find.byKey(more)).right, 1280 - 16);
    expect(tester.getRect(find.byKey(below)).width, 1280);
  });
}
