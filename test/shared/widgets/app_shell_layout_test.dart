import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_book_tiles.dart';
import 'package:night_reader/main.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';

class _Broken extends StatelessWidget {
  const _Broken();

  @override
  Widget build(BuildContext context) => throw StateError('壞掉的列');
}

void main() {
  testWidgets('a broken list row is replaced without breaking the list', (
    tester,
  ) async {
    final previous = ErrorWidget.builder;
    ErrorWidget.builder = (details) =>
        buildFlutterErrorWidget(details, releaseNativeSplash: () {});
    final errors = <Object>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.exception);
    addTearDown(() => FlutterError.onError = previousOnError);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: const [
              Text('上一列'),
              Row(children: [_Broken()]),
              _Broken(),
              Text('下一列'),
            ],
          ),
        ),
      ),
    );

    FlutterError.onError = previousOnError;
    ErrorWidget.builder = previous;
    // 只有兩列本身的 build 例外，沒有因替代元件尺寸無限而產生的排版例外。
    expect(errors, hasLength(2));
    expect(errors, everyElement(isStateError));
    expect(find.text('上一列'), findsOneWidget);
    expect(find.text('下一列'), findsOneWidget);
  });

  testWidgets('grid tiles fit two title lines at a large text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    const scaler = TextScaler.linear(2);
    const cellWidth = (360 - 16 * 2 - 14 * 2) / 3;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 780), textScaler: scaler),
          child: Scaffold(
            body: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisExtent: BookshelfGridTile.heightFor(cellWidth, scaler),
                crossAxisSpacing: 14,
                mainAxisSpacing: 10,
              ),
              itemCount: 3,
              itemBuilder: (_, i) => BookshelfGridTile(
                book: Book(
                  bookUrl: 'https://b$i.example',
                  name: '一本書名很長很長很長很長很長很長的小說第$i部',
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('screen readers can switch tabs', (tester) async {
    final handle = tester.ensureSemantics();
    final taps = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Scaffold(
          bottomNavigationBar: FloatingTabBar(
            currentIndex: 0,
            onTap: taps.add,
            items: const [
              FloatingTabItem(
                icon: Icons.book_outlined,
                selectedIcon: Icons.book,
                label: '書架',
              ),
              FloatingTabItem(
                icon: Icons.explore_outlined,
                selectedIcon: Icons.explore,
                label: '發現',
              ),
              FloatingTabItem(
                icon: Icons.person_outline,
                selectedIcon: Icons.person,
                label: '我的',
              ),
            ],
          ),
        ),
      ),
    );

    tester.semantics.tap(find.semantics.byLabel('我的'));
    expect(taps, [2]);
    handle.dispose();
  });
}
