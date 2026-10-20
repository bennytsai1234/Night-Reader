import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';
import 'package:night_reader/shared/navigation/book_open_route.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

/// 換頁轉場：返回不是開啟倒著播；往右拖返回照選的那一種跟著拖曳走、放開
/// 照 Telegram 的門檻與時長；Android 系統的預測返回跟手；「展開」從按下的
/// 卡片長出來。
void main() {
  late BuildContext home;

  /// 可以按、會開新頁的卡片範圍。
  const card = Rect.fromLTWH(600, 400, 120, 160);

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
              return Scaffold(
                body: Stack(
                  children: [
                    const Center(child: Text('主頁')),
                    Positioned.fromRect(
                      rect: card,
                      child: const TransitionSource(
                        radius: 8,
                        child: ColoredBox(color: Colors.brown),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

  Future<void> push(WidgetTester tester) async {
    Navigator.push(
      home,
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('新頁'))),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 新頁此刻的樣子：外層透明度（百分比）、裁切範圍與文字位置，攤成一串
  /// 長度固定的數字。
  List<double> pose(WidgetTester tester) {
    final page = find.text('新頁');
    final opacity = tester
        .widgetList<Opacity>(
          find.ancestor(of: page, matching: find.bySubtype<Opacity>()),
        )
        .fold(1.0, (product, w) => product * w.opacity);
    final clip =
        tester
            .widgetList<ClipRRect>(
              find.ancestor(of: page, matching: find.byType(ClipRRect)),
            )
            .map((w) => w.clipper?.getClip(const Size(800, 600)).outerRect)
            .nonNulls
            .firstOrNull ??
        const Rect.fromLTWH(0, 0, 800, 600);
    final rect = tester.getRect(page);
    return [
      100 * opacity,
      clip.left,
      clip.top,
      clip.width,
      rect.left,
      rect.top,
      rect.width,
    ];
  }

  /// 換頁的第一、二幀停在起點（第一幀花掉的時間不算進動畫），之後才照時間
  /// 走；量某個時間點的樣子前先推過這兩幀，第二幀只隔 1ms。
  Future<void> startTrip(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  }

  double distance(List<double> a, List<double> b) =>
      [for (var i = 0; i < a.length; i++) (a[i] - b[i]).abs()]
          .fold(0.0, (sum, d) => sum + d);

  bool samePose(List<double> a, List<double> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) (a[i] - b[i]).abs() < 0.5]
          .every((same) => same);

  for (final transition in AppPageTransition.values) {
    testWidgets('${transition.name}: closing is not opening played backwards', (
      tester,
    ) async {
      await pumpApp(tester, transition);
      await tester.tapAt(card.center);
      Navigator.push(
        home,
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Center(child: Text('新頁'))),
        ),
      );
      await startTrip(tester);
      final total = transition.duration;
      await tester.pump(total * 0.3);
      final opening = pose(tester);

      await tester.pumpAndSettle();
      // 開完不留轉場的痕跡。
      expect(tester.getCenter(find.text('新頁')), const Offset(400, 300));
      final settled = pose(tester);

      Navigator.pop(tester.element(find.text('新頁')));
      await startTrip(tester);
      await tester.pump(total * 0.7);
      final closing = pose(tester);

      // 倒著播的話，返回走到 70% 的樣子會跟開啟走到 30% 一模一樣。
      expect(samePose(opening, closing), isFalse);
      expect(samePose(closing, settled), isFalse);

      await tester.pumpAndSettle();
      expect(find.text('新頁'), findsNothing);
      expect(find.text('主頁'), findsOneWidget);
    });

    testWidgets('${transition.name}: closing moves most at the start', (
      tester,
    ) async {
      await pumpApp(tester, transition);
      await tester.tapAt(card.center);
      await push(tester);

      Navigator.pop(tester.element(find.text('新頁')));
      await startTrip(tester);
      final start = pose(tester);
      // 先快後慢：第一段時間變得比下一段多。俐落平移的彈簧從靜止起步、
      // 約 8.5% 時最快，所以比 20% 一段；其他比 10%。
      final step =
          transition.duration *
          (transition == AppPageTransition.slideCrisp ? 0.2 : 0.1);
      await tester.pump(step);
      final first = pose(tester);
      await tester.pump(step);
      final second = pose(tester);

      expect(distance(start, first), greaterThan(distance(first, second)));
      await tester.pumpAndSettle();
    });
  }

  for (final transition in AppPageTransition.values) {
    testWidgets('${transition.name}: neither page is rebuilt while moving', (
      tester,
    ) async {
      var homeBuilds = 0;
      var pageBuilds = 0;
      // 兩頁都依賴主題，和真的頁面一樣：被搬到別的位置時會跟著重建。
      Widget counted(String text, void Function() count) => Builder(
        builder: (context) {
          count();
          return ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Center(child: Text(text)),
          );
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(
            AppStyle.paper,
            Brightness.light,
            pageTransition: transition,
          ),
          home: Builder(
            builder: (context) {
              home = context;
              return counted('主頁', () => homeBuilds++);
            },
          ),
        ),
      );
      final homeBefore = homeBuilds;

      Navigator.push(
        home,
        MaterialPageRoute<void>(
          builder: (_) => counted('新頁', () => pageBuilds++),
        ),
      );
      await tester.pumpAndSettle();
      // 新頁只在推入時建一次；換頁的第一幀、途中與最後一幀都不重建。
      expect(pageBuilds, 1);

      Navigator.pop(tester.element(find.text('新頁')));
      await tester.pumpAndSettle();
      expect(pageBuilds, 1);
      expect(homeBuilds, homeBefore);
    });
  }

  testWidgets('a slow first frame does not make the page jump', (tester) async {
    await pumpApp(tester, AppPageTransition.slide);
    Navigator.push(
      home,
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('新頁'))),
      ),
    );
    await tester.pump();
    // 第一幀很重（新頁第一次建立）：下一幀晚了 100ms 才到。
    await tester.pump(const Duration(milliseconds: 100));
    double left() => tester.getRect(find.byType(Scaffold).last).left;
    // 還停在起點，那 100ms 不算進動畫；原本直接跳到 100ms 的位置（過半）。
    expect(left(), closeTo(800, 1));
    await tester.pump(const Duration(milliseconds: 16));
    final step = 800 - left();
    expect(step, greaterThan(0));
    expect(step, lessThan(200));
    // 和路由同時到位。
    await tester.pump(const Duration(milliseconds: 400));
    expect(left(), closeTo(0, 0.5));
    expect(ModalRoute.of(tester.element(find.text('新頁')))!.isCurrent, isTrue);
    await tester.pumpAndSettle();
    expect(left(), 0);

    // 返回也一樣：第一幀晚到的時間不算。
    Navigator.pop(tester.element(find.text('新頁')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(left(), closeTo(0, 1));
    await tester.pumpAndSettle();
    expect(find.text('新頁'), findsNothing);
  });

  testWidgets('slide closes fast first, then eases into place', (tester) async {
    await pumpApp(tester, AppPageTransition.slide);
    await push(tester);

    Navigator.pop(tester.element(find.text('新頁')));
    await startTrip(tester);
    await tester.pump(AppPageTransition.slide.duration * 0.2);
    // 時間才走 20%，頁面已經移出一半以上；倒著播的話還不到一成。
    expect(tester.getCenter(find.text('新頁')).dx, greaterThan(400 + 400 * 0.5));
  });

  testWidgets('routes take the duration of the chosen transition', (
    tester,
  ) async {
    await pumpApp(tester, AppPageTransition.glide);
    Navigator.push(
      home,
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('新頁'))),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    final route = ModalRoute.of(tester.element(find.text('新頁')))!;
    expect(route.transitionDuration, AppPageTransition.glide.duration);
    expect(route.reverseTransitionDuration, AppPageTransition.glide.duration);
  });

  testWidgets('expand grows out of the card that was pressed', (tester) async {
    await pumpApp(tester, AppPageTransition.expand);
    await tester.tapAt(card.center);
    Navigator.push(
      home,
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('新頁'))),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    // 彈簧起步很快，第一毫秒已經往整頁撐開約 1%。
    final clip = tester
        .widget<ClipRRect>(
          find.ancestor(of: find.text('新頁'), matching: find.byType(ClipRRect)),
        )
        .clipper!
        .getClip(const Size(800, 600));
    expect(clip.outerRect.left, closeTo(card.left, 12));
    expect(clip.outerRect.top, closeTo(card.top, 12));
    expect(clip.outerRect.width, closeTo(card.width, 24));
    expect(clip.tlRadius.x, lessThan(12));
  });

  testWidgets('a card can grow out of just part of itself', (tester) async {
    const tile = Rect.fromLTWH(100, 100, 120, 240);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(
          AppStyle.paper,
          Brightness.light,
          pageTransition: AppPageTransition.expand,
        ),
        builder: (context, child) => TransitionOriginRecorder(child: child!),
        home: Builder(
          builder: (context) {
            home = context;
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: tile,
                  child: TransitionSource(
                    // 像書架網格：上半是封面，下半是書名。
                    area: (card) => Rect.fromLTWH(
                      card.left,
                      card.top,
                      card.width,
                      card.height / 2,
                    ),
                    child: const ColoredBox(color: Colors.brown),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    await tester.tapAt(const Offset(160, 300)); // 點在下半的書名。
    Navigator.push(
      home,
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('新頁'))),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    final clip = tester
        .widget<ClipRRect>(
          find.ancestor(of: find.text('新頁'), matching: find.byType(ClipRRect)),
        )
        .clipper!
        .getClip(const Size(800, 600));
    expect(clip.outerRect.top, closeTo(tile.top, 12));
    expect(clip.outerRect.width, closeTo(tile.width, 24));
  });

  group('swiping back from the left edge', () {
    /// 從左緣慢慢往右拖 [distance]，每 100ms 移一小段（約 200px/s）。
    Future<void> slowDrag(WidgetTester tester, double distance) async {
      final gesture = await tester.startGesture(const Offset(5, 300));
      var moved = 0.0;
      while (moved < distance) {
        final step = (distance - moved).clamp(0.0, 20.0);
        await gesture.moveBy(Offset(step, 0));
        await tester.pump(const Duration(milliseconds: 100));
        moved += step;
      }
      await gesture.up();
    }

    /// 從左緣往右拖 220（頁寬 800 的 27.5%），手指不放。
    Future<TestGesture> holdDrag(WidgetTester tester) async {
      final gesture = await tester.startGesture(const Offset(5, 300));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      return gesture;
    }

    testWidgets('slide follows the finger', (tester) async {
      await pumpApp(tester, AppPageTransition.slide);
      await push(tester);
      final gesture = await holdDrag(tester);
      expect(tester.getCenter(find.text('新頁')).dx, closeTo(620, 1));
      expect(find.text('主頁'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('paper sinks and fades as far as the drag goes', (
      tester,
    ) async {
      await pumpApp(tester, AppPageTransition.paper);
      await push(tester);
      final gesture = await holdDrag(tester);
      // 照上浮的返回：不橫移，往下沉 4% × 27.5%，透明度剩 72.5%。
      final [opacity, ..., left, top, _] = pose(tester);
      expect(opacity, closeTo(72.5, 0.5));
      final settledTop = 300 - tester.getSize(find.text('新頁')).height / 2;
      expect(top - settledTop, closeTo(600 * 0.04 * 0.275, 0.5));
      expect(
        left + tester.getSize(find.text('新頁')).width / 2,
        closeTo(400, 0.5),
      );
      await gesture.up();
      await tester.pumpAndSettle();
    });

    for (final transition in AppPageTransition.values.where(
      (t) => t != AppPageTransition.slide && t != AppPageTransition.slideCrisp,
    )) {
      testWidgets('${transition.name}: dragging back looks like its return', (
        tester,
      ) async {
        await pumpApp(tester, transition);
        await tester.tapAt(card.center);
        await push(tester);
        final settled = pose(tester);
        final gesture = await holdDrag(tester);
        final dragged = pose(tester);
        // 不是平移（中心跟著手指到 620），但頁面確實跟著拖曳變了。
        expect(tester.getCenter(find.text('新頁')).dx, lessThan(600));
        expect(samePose(dragged, settled), isFalse);
        expect(find.text('主頁'), findsOneWidget);

        // 放回原處就回到整頁。
        await gesture.moveBy(const Offset(-220, 0));
        await tester.pump();
        expect(samePose(pose(tester), settled), isTrue);
        await gesture.up();
        await tester.pumpAndSettle();
      });
    }

    testWidgets('past a fifth of the width it goes back within 0.2s', (
      tester,
    ) async {
      await pumpApp(tester, AppPageTransition.slide);
      await push(tester);
      await slowDrag(tester, 800 * 0.25);
      await tester.pump(); // 收尾的動畫從這一格開始計時。
      // 0.2 秒後的下一格送完，路由再下一格移除。
      await tester.pump(const Duration(milliseconds: 200 + 16));
      await tester.pump();
      expect(find.text('新頁'), findsNothing);
      expect(find.text('主頁'), findsOneWidget);
    });

    testWidgets('short of a fifth it springs back', (tester) async {
      await pumpApp(tester, AppPageTransition.slide);
      await push(tester);
      await slowDrag(tester, 800 * 0.15);
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.text('新頁')), const Offset(400, 300));
    });

    testWidgets('a quick flick goes back even when short', (tester) async {
      await pumpApp(tester, AppPageTransition.slide);
      await push(tester);
      await tester.flingFrom(const Offset(5, 300), const Offset(80, 0), 1500);
      await tester.pumpAndSettle();
      expect(find.text('新頁'), findsNothing);
    });
  });

  group('Android predictive back', () {
    Future<void> send(
      WidgetTester tester,
      String method, [
      Map<String, Object?>? arguments,
    ]) => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.backGesture.name,
      SystemChannels.backGesture.codec.encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (_) {},
    );

    Map<String, Object?> event(double x, double progress) => {
      'touchOffset': [x, 300.0],
      'progress': progress,
      'swipeEdge': 0,
    };

    testWidgets('the page follows the system gesture and leaves on commit', (
      tester,
    ) async {
      await pumpApp(tester, AppPageTransition.forward);
      await push(tester);
      await send(tester, 'startBackGesture', event(0, 0));
      await send(tester, 'updateBackGestureProgress', event(200, 0.5));
      // 進度照觸控重新取樣晚 38ms 才畫到。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      // 照推進的返回：往右移 25% × 一半，淡到一半。
      expect(tester.getCenter(find.text('新頁')).dx, closeTo(500, 1));
      expect(pose(tester).first, closeTo(50, 0.5));
      expect(find.text('主頁'), findsOneWidget);

      await send(tester, 'commitBackGesture');
      await tester.pump(); // 收尾的動畫從這一格開始計時。
      // 0.2 秒後的下一格送完，路由再下一格移除。
      await tester.pump(const Duration(milliseconds: 200 + 16));
      await tester.pump();
      expect(find.text('新頁'), findsNothing);
    });

    testWidgets('a slow gesture moves the page every frame', (tester) async {
      await pumpApp(tester, AppPageTransition.slide);
      await push(tester);
      await send(tester, 'startBackGesture', event(0, 0));
      // 手指慢：系統每 32ms 才送一次，一次 1%（8px）；畫面每 8ms 一格。
      final xs = <double>[];
      for (var i = 1; i <= 12; i++) {
        await send(
          tester,
          'updateBackGestureProgress',
          event(8.0 * i, 0.01 * i),
        );
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 8));
          xs.add(tester.getCenter(find.text('新頁')).dx);
        }
      }
      // 開頭留一段給取樣延遲，之後每一格都往右移、步幅一樣。
      final steps = [for (var i = 8; i < xs.length; i++) xs[i] - xs[i - 1]];
      for (final step in steps) {
        expect(step, closeTo(8 / 4, 0.01));
      }
      await send(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
    });

    testWidgets('a cancelled gesture puts the page back', (tester) async {
      await pumpApp(tester, AppPageTransition.forward);
      await push(tester);
      await send(tester, 'startBackGesture', event(0, 0));
      await send(tester, 'updateBackGestureProgress', event(100, 0.3));
      await tester.pump();
      await send(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.text('新頁')), const Offset(400, 300));
    });

    for (final ending in ['cancelBackGesture', 'commitBackGesture']) {
      testWidgets('a page pushed mid-gesture ($ending) leaves the page whole', (
        tester,
      ) async {
        await pumpApp(tester, AppPageTransition.slide);
        await push(tester);
        final page = tester.element(find.text('新頁'));
        final route = ModalRoute.of(page)!;
        await send(tester, 'startBackGesture', event(0, 0));
        await send(tester, 'updateBackGestureProgress', event(100, 0.4));
        await tester.pump();

        Navigator.push(
          page,
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Center(child: Text('第三頁'))),
          ),
        );
        await tester.pump();
        await send(tester, ending);
        await tester.pumpAndSettle();
        Navigator.pop(tester.element(find.text('第三頁')));
        await tester.pumpAndSettle();

        // 回到這一頁時是整頁，也還能再拖曳返回。
        expect(tester.getCenter(find.text('新頁')), const Offset(400, 300));
        expect(route.animation!.value, 1);
        expect(route.popGestureEnabled, isTrue);
      });
    }

    testWidgets('closing the page in code mid-gesture ends the gesture', (
      tester,
    ) async {
      await pumpApp(tester, AppPageTransition.slide);
      await push(tester);
      await send(tester, 'startBackGesture', event(0, 0));
      await send(tester, 'updateBackGestureProgress', event(100, 0.4));
      await tester.pump();

      Navigator.pop(tester.element(find.text('新頁')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('新頁'), findsNothing);
      expect(Navigator.of(home).userGestureInProgress, isFalse);
    });
  });

  test('the reader cannot be swiped back', () {
    final route = BookOpenRoute(
      book: Book(bookUrl: 'https://a.example/1', origin: 'local', name: '書'),
    );
    expect(route.popGestureEnabled, isFalse);
  });

  test('an unknown or missing stored value falls back to slide', () {
    expect(AppPageTransition.fromStorage(null), AppPageTransition.slide);
    expect(AppPageTransition.fromStorage('fade'), AppPageTransition.slide);
    expect(AppPageTransition.fromStorage('glide'), AppPageTransition.glide);
  });
}
