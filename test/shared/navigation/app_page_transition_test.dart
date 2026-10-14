import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';
import 'package:night_reader/shared/navigation/book_open_route.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

/// 換頁轉場：每一種的返回都是開啟倒著播，時長照選擇；「展開」從按下的
/// 位置長出來。
void main() {
  late BuildContext home;

  Future<void> pumpApp(WidgetTester tester, AppPageTransition transition) =>
      tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(
            AppStyle.paper,
            Brightness.light,
            pageTransition: transition,
          ),
          builder: (context, child) => TransitionOriginRecorder(child: child!),
          home: Builder(
            builder: (context) {
              home = context;
              return const Scaffold(body: Center(child: Text('主頁')));
            },
          ),
        ),
      );

  void push() => Navigator.push(
    home,
    MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Center(child: Text('新頁'))),
    ),
  );

  /// 新頁此刻的樣子：透明度、位移、裁切範圍與位置，攤成一串數字。
  List<double> pose(WidgetTester tester) {
    final page = find.text('新頁');
    Object? first<T extends Widget>(Object? Function(T) read) {
      final found = find.ancestor(of: page, matching: find.byType(T));
      return found.evaluate().isEmpty
          ? null
          : read(tester.widget<T>(found.first));
    }

    final opacity = first<FadeTransition>((w) => w.opacity.value) as double?;
    final slide = first<SlideTransition>((w) => w.position.value) as Offset?;
    final clip = first<ClipRRect>(
      (w) => w.clipper?.getClip(const Size(800, 600)).outerRect,
    ) as Rect?;
    final topLeft = tester.getTopLeft(page);
    return [
      ?opacity,
      if (slide != null) ...[slide.dx, slide.dy],
      if (clip != null) ...[clip.left, clip.top, clip.right, clip.bottom],
      topLeft.dx,
      topLeft.dy,
    ];
  }

  Rect clipOf(WidgetTester tester) => tester
      .widget<ClipRRect>(
        find.ancestor(of: find.text('新頁'), matching: find.byType(ClipRRect)),
      )
      .clipper!
      .getClip(const Size(800, 600))
      .outerRect;

  for (final transition in AppPageTransition.values) {
    testWidgets('${transition.name}: closing mirrors opening', (tester) async {
      await pumpApp(tester, transition);
      await tester.tapAt(const Offset(700, 500));
      push();
      await tester.pump();

      final total = transition.duration;
      final probe = total * 0.3;
      await tester.pump(probe);
      final opening = pose(tester);

      await tester.pumpAndSettle();
      final settled = pose(tester);
      expect(find.text('主頁'), findsNothing);
      // 開完不留轉場的痕跡。
      expect(tester.getCenter(find.text('新頁')), const Offset(400, 300));

      Navigator.pop(tester.element(find.text('新頁')));
      await tester.pump();
      await tester.pump(total - probe);
      final closing = pose(tester);
      expect(closing, hasLength(opening.length));
      for (var i = 0; i < opening.length; i++) {
        expect(closing[i], closeTo(opening[i], 0.01), reason: 'pose[$i]');
      }
      // 量的是半路的樣子，不是已經到位的樣子。
      final moving = [
        for (var i = 0; i < opening.length && i < settled.length; i++)
          (opening[i] - settled[i]).abs() > 0.01,
      ];
      expect(moving, contains(true));

      await tester.pumpAndSettle();
      expect(find.text('新頁'), findsNothing);
      expect(find.text('主頁'), findsOneWidget);
    });
  }

  testWidgets('routes take the duration of the chosen transition', (
    tester,
  ) async {
    await pumpApp(tester, AppPageTransition.slide);
    push();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    final route = ModalRoute.of(tester.element(find.text('新頁')))!;
    expect(route.transitionDuration, AppPageTransition.slide.duration);
    expect(route.reverseTransitionDuration, AppPageTransition.slide.duration);
  });

  testWidgets('expand grows out of where the finger went down', (tester) async {
    await pumpApp(tester, AppPageTransition.expand);
    const tap = Offset(700, 500);
    await tester.tapAt(tap);
    push();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    final clip = clipOf(tester);
    expect(clip.width, lessThan(800));
    expect(clip.contains(tap), isTrue);
  });

  test('the reader cannot be swiped back', () {
    final route = BookOpenRoute(
      book: Book(bookUrl: 'https://a.example/1', origin: 'local', name: '書'),
    );
    expect(route.popGestureEnabled, isFalse);
  });

  test('an unknown or missing stored value falls back to paper', () {
    expect(AppPageTransition.fromStorage(null), AppPageTransition.paper);
    expect(AppPageTransition.fromStorage('zoom'), AppPageTransition.paper);
    expect(AppPageTransition.fromStorage('expand'), AppPageTransition.expand);
  });
}
