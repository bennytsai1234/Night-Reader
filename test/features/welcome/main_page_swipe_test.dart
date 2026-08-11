import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:night_reader/features/welcome/main_page.dart';

MainDestination _fake(String label) => MainDestination(
  icon: Icons.circle_outlined,
  selectedIcon: Icons.circle,
  label: label,
  page: SizedBox.expand(key: Key('page-$label')),
);

void main() {
  setUpAll(() {
    WidgetController.hitTestWarningShouldBeFatal = true;
  });

  tearDownAll(() {
    WidgetController.hitTestWarningShouldBeFatal = false;
  });

  testWidgets('renders first destination by default', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(destinations: [_fake('書架'), _fake('發現'), _fake('我的')]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page-書架')), findsOneWidget);
  });

  testWidgets('swipe left advances tab and syncs NavigationBar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(destinations: [_fake('書架'), _fake('發現'), _fake('我的')]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('page-發現')), findsOneWidget);
    final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar.selectedIndex, 1);
  });

  testWidgets('tap NavigationBar destination switches to target tab', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(destinations: [_fake('書架'), _fake('發現'), _fake('我的')]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('發現'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('page-發現')), findsOneWidget);
    final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar.selectedIndex, 1);
  });

  testWidgets('double tap current destination triggers callback', (
    tester,
  ) async {
    final calls = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          destinations: [_fake('書架'), _fake('發現'), _fake('我的')],
          onDestinationDoubleTap: (_, idx) => calls.add(idx),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('書架'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(calls, isEmpty);

    await tester.tap(find.text('書架'));
    await tester.pump();
    expect(calls, [0]);
  });

  testWidgets('swipe back to first tab does NOT trigger double-tap callback', (
    tester,
  ) async {
    final calls = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          destinations: [_fake('書架'), _fake('發現'), _fake('我的')],
          onDestinationDoubleTap: (_, idx) => calls.add(idx),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(400, 0));
    await tester.pumpAndSettle();

    expect(calls, isEmpty);
  });

  testWidgets('tab content preserves state via KeepAlive', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          destinations: [
            MainDestination(
              icon: Icons.book_outlined,
              selectedIcon: Icons.book,
              label: '書架',
              page: const _CounterPage(key: Key('counter')),
            ),
            _fake('發現'),
            _fake('我的'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('counter-inc')));
    await tester.tap(find.byKey(const Key('counter-inc')));
    await tester.tap(find.byKey(const Key('counter-inc')));
    await tester.pump();
    expect(find.text('count: 3'), findsOneWidget);

    await tester.tap(find.text('發現'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('書架'));
    await tester.pumpAndSettle();

    expect(find.text('count: 3'), findsOneWidget);
  });

  testWidgets('back from non-first tab returns to first tab via animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(destinations: [_fake('書架'), _fake('發現'), _fake('我的')]),
      ),
    );
    await tester.pumpAndSettle();

    // 切到我的
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page-我的')), findsOneWidget);

    // 直接 invoke PopScope 的 callback 模擬系統返回
    final popScope = tester.widget<PopScope<void>>(find.byType(PopScope<void>));
    popScope.onPopInvokedWithResult!.call(false, null);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('page-書架')), findsOneWidget);
    final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar.selectedIndex, 0);
  });

  testWidgets(
    'slow shelf hands off to a non-blocking semantic overlay after 2 seconds',
    (tester) async {
      final shelf = _ControllableShelfProvider();
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          ChangeNotifierProvider<BookshelfProvider>.value(
            value: shelf,
            child: MaterialApp(
              home: MainPage(
                destinations: [_fake('書架'), _fake('發現'), _fake('我的')],
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();

        expect(
          find.byKey(const ValueKey('startup-loading-overlay')),
          findsOneWidget,
        );
        final overlaySemantics = tester.widget<Semantics>(
          find
              .descendant(
                of: find.byKey(const ValueKey('startup-loading-overlay')),
                matching: find.byType(Semantics),
              )
              .first,
        );
        expect(overlaySemantics.properties.label, '正在載入書架');
        expect(overlaySemantics.properties.liveRegion, isTrue);

        await tester.drag(find.byType(PageView), const Offset(-500, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byKey(const Key('page-發現')), findsOneWidget);

        shelf.completeLoading();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          find.byKey(const ValueKey('startup-loading-overlay')),
          findsNothing,
        );
      } finally {
        semantics.dispose();
      }
    },
  );
}

class _ControllableShelfProvider extends Fake implements BookshelfProvider {
  final List<VoidCallback> _listeners = <VoidCallback>[];
  bool _isLoading = true;

  @override
  bool get isLoading => _isLoading;

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void completeLoading() {
    _isLoading = false;
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }
}

class _CounterPage extends StatefulWidget {
  const _CounterPage({super.key});
  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int _count = 0;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('count: $_count'),
          ElevatedButton(
            key: const Key('counter-inc'),
            onPressed: () => setState(() => _count++),
            child: const Text('+'),
          ),
        ],
      ),
    );
  }
}
