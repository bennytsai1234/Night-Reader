import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_motion.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

const double _rowHeight = 50;

/// 和書架頁一樣：每次建構時把目前順序交給 [BookshelfLayoutMotion]，每本書包
/// 一層 [BookshelfMotionItem]。
class _Shelf extends StatefulWidget {
  const _Shelf({
    super.key,
    required this.urls,
    this.grid = false,
    this.animate = true,
    this.keyed = true,
  });

  final List<String> urls;
  final bool grid;
  final bool animate;

  /// true 時清單元素依 key 沿用（書卡換位）；false 時依索引重建（書卡重新建立）。
  final bool keyed;

  @override
  State<_Shelf> createState() => _ShelfState();
}

class _ShelfState extends State<_Shelf> with TickerProviderStateMixin {
  late final BookshelfLayoutMotion motion = BookshelfLayoutMotion(
    vsync: this,
    onRemovalsFaded: () => setState(() {}),
  );

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = motion.update(
      widget.urls,
      grid: widget.grid,
      animate: widget.animate,
    );
    Widget item(String url) => BookshelfMotionItem(
      key: widget.keyed ? ValueKey(url) : null,
      id: url,
      motion: motion,
      child: SizedBox(height: _rowHeight, child: Text(url)),
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: widget.keyed
          ? ListView(children: [for (final url in urls) item(url)])
          : ListView.builder(
              itemCount: urls.length,
              itemBuilder: (context, index) => item(urls[index]),
            ),
    );
  }
}

/// 每本書可點的書架，給點擊測試用。
class _TapShelf extends StatefulWidget {
  const _TapShelf({super.key, required this.urls, required this.onTap});

  final List<String> urls;
  final ValueChanged<String> onTap;

  @override
  State<_TapShelf> createState() => _TapShelfState();
}

class _TapShelfState extends State<_TapShelf> with TickerProviderStateMixin {
  late final BookshelfLayoutMotion motion = BookshelfLayoutMotion(
    vsync: this,
    onRemovalsFaded: () => setState(() {}),
  );

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = motion.update(widget.urls, grid: false, animate: true);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ListView(
        children: [
          for (final url in urls)
            BookshelfMotionItem(
              key: ValueKey(url),
              id: url,
              motion: motion,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onTap(url),
                child: SizedBox(height: _rowHeight, child: Text(url)),
              ),
            ),
        ],
      ),
    );
  }
}

void main() {
  double topOf(WidgetTester tester, String url) =>
      tester.getTopLeft(find.text(url)).dy;

  int opacityLayers(WidgetTester tester) =>
      tester.layers.whereType<OpacityLayer>().length;

  for (final keyed in [true, false]) {
    final variant = keyed ? '沿用書卡' : '重建書卡';

    testWidgets('換順序後書卡從舊位置移到新位置，結束時沒有殘留位移（$variant）', (tester) async {
      await tester.pumpWidget(
        _Shelf(urls: const ['a', 'b', 'c'], keyed: keyed),
      );
      expect(topOf(tester, 'c'), _rowHeight * 2);

      await tester.pumpWidget(
        _Shelf(urls: const ['c', 'a', 'b'], keyed: keyed),
      );

      // 第一幀還畫在舊位置。
      expect(topOf(tester, 'c'), moreOrLessEquals(_rowHeight * 2));
      expect(topOf(tester, 'a'), moreOrLessEquals(0));

      await tester.pump(const Duration(milliseconds: 100));
      final midway = topOf(tester, 'c');
      expect(midway, lessThan(_rowHeight * 2));
      expect(midway, greaterThan(0));

      await tester.pumpAndSettle();
      expect(topOf(tester, 'c'), 0);
      expect(topOf(tester, 'a'), _rowHeight);
      expect(topOf(tester, 'b'), _rowHeight * 2);
    });
  }

  testWidgets('新加入的書淡入，結束後不再有透明圖層', (tester) async {
    await tester.pumpWidget(const _Shelf(urls: ['a', 'b']));
    expect(opacityLayers(tester), 0);

    await tester.pumpWidget(const _Shelf(urls: ['new', 'a', 'b']));
    await tester.pump(const Duration(milliseconds: 50));
    expect(opacityLayers(tester), 1);

    await tester.pumpAndSettle();
    expect(opacityLayers(tester), 0);
    expect(topOf(tester, 'new'), 0);
    expect(topOf(tester, 'b'), _rowHeight * 2);
  });

  testWidgets('移出的書先在原位淡出，淡完其他書卡才補位', (tester) async {
    await tester.pumpWidget(const _Shelf(urls: ['a', 'b', 'c']));

    await tester.pumpWidget(const _Shelf(urls: ['a', 'c']));
    await tester.pump(AppMotion.fade ~/ 2);
    // 淡出中：b 還在原位、半透明，c 還沒移動。
    expect(find.text('b'), findsOneWidget);
    expect(topOf(tester, 'b'), _rowHeight);
    expect(topOf(tester, 'c'), _rowHeight * 2);
    final fading = tester.layers.whereType<OpacityLayer>().single.alpha!;
    expect(fading, inExclusiveRange(0, 255));

    // 淡完才拿掉 b，c 從原位置往上補位。
    await tester.pump(AppMotion.fade ~/ 2);
    expect(topOf(tester, 'c'), _rowHeight * 2);
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('b'), findsNothing);
    await tester.pump(const Duration(milliseconds: 50));
    expect(topOf(tester, 'c'), inExclusiveRange(_rowHeight, _rowHeight * 2));

    await tester.pumpAndSettle();
    expect(topOf(tester, 'c'), _rowHeight);
    expect(opacityLayers(tester), 0);
  });

  testWidgets('淡出途中又移出一本，先淡的那本從當下接著淡', (tester) async {
    await tester.pumpWidget(const _Shelf(urls: ['a', 'b', 'c']));
    await tester.pumpWidget(const _Shelf(urls: ['b', 'c']));
    await tester.pump(AppMotion.fade ~/ 2);
    final half = tester.layers.whereType<OpacityLayer>().single.alpha!;

    await tester.pumpWidget(const _Shelf(urls: ['c']));
    await tester.pump(const Duration(milliseconds: 16));
    final alphas = tester.layers.whereType<OpacityLayer>().map((l) => l.alpha!);
    // a 不會跳回不透明，b 剛開始淡。
    expect(alphas.reduce((x, y) => x < y ? x : y), lessThanOrEqualTo(half));

    await tester.pumpAndSettle();
    expect(find.text('a'), findsNothing);
    expect(find.text('b'), findsNothing);
    expect(topOf(tester, 'c'), 0);
  });

  testWidgets('換位途中移出一本，移動中的書卡從當下的位置接著移', (tester) async {
    await tester.pumpWidget(const _Shelf(urls: ['a', 'b', 'c']));
    await tester.pumpWidget(const _Shelf(urls: ['c', 'a', 'b']));
    await tester.pump(const Duration(milliseconds: 80));
    final moving = topOf(tester, 'c');
    expect(moving, inExclusiveRange(0, _rowHeight * 2));

    await tester.pumpWidget(const _Shelf(urls: ['c', 'b']));
    // 時間沒有前進：c 還畫在原本的半路，不會先跳到終點。
    expect(topOf(tester, 'c'), moreOrLessEquals(moving));
    await tester.pump(const Duration(milliseconds: 40));
    expect(topOf(tester, 'c'), inExclusiveRange(0, moving));

    await tester.pumpAndSettle();
    expect(find.text('a'), findsNothing);
    expect(topOf(tester, 'c'), 0);
    expect(topOf(tester, 'b'), _rowHeight);
    expect(opacityLayers(tester), 0);
  });

  testWidgets('補位途中再移出一本，補位的書卡從當下的位置接著移', (tester) async {
    await tester.pumpWidget(const _Shelf(urls: ['a', 'b', 'c', 'd']));
    await tester.pumpWidget(const _Shelf(urls: ['a', 'c', 'd']));
    await tester.pump(AppMotion.fade);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 60));
    final moving = topOf(tester, 'c');
    expect(moving, inExclusiveRange(_rowHeight, _rowHeight * 2));

    await tester.pumpWidget(const _Shelf(urls: ['c', 'd']));
    expect(topOf(tester, 'c'), moreOrLessEquals(moving));

    await tester.pumpAndSettle();
    expect(topOf(tester, 'c'), 0);
    expect(topOf(tester, 'd'), _rowHeight);
    expect(opacityLayers(tester), 0);
  });

  testWidgets('淡入途中又換位，淡入從當下的濃淡接著淡', (tester) async {
    await tester.pumpWidget(const _Shelf(urls: ['a', 'b']));
    await tester.pumpWidget(const _Shelf(urls: ['new', 'a', 'b']));
    await tester.pump(const Duration(milliseconds: 50));
    final fading = tester.layers.whereType<OpacityLayer>().single.alpha!;
    expect(fading, inExclusiveRange(0, 255));

    await tester.pumpWidget(const _Shelf(urls: ['new', 'b', 'a']));
    final alphas = tester.layers.whereType<OpacityLayer>().map((l) => l.alpha!);
    // 沒有一下變成不透明，也沒有跳回全透明。
    expect(alphas.single, closeTo(fading, 1));

    await tester.pumpAndSettle();
    expect(opacityLayers(tester), 0);
    expect(topOf(tester, 'b'), _rowHeight);
  });

  testWidgets('淡出途中書又回來，從當下的濃淡淡回來，之後照常可點', (tester) async {
    final tapped = <String>[];
    Widget shelf(List<String> urls) => _TapShelf(urls: urls, onTap: tapped.add);

    await tester.pumpWidget(shelf(const ['a', 'b', 'c']));
    await tester.pumpWidget(shelf(const ['b', 'c']));
    await tester.pump(AppMotion.fade ~/ 2);
    final fading = tester.layers.whereType<OpacityLayer>().single.alpha!;
    expect(fading, inExclusiveRange(0, 255));

    await tester.pumpWidget(shelf(const ['a', 'b', 'c']));
    expect(
      tester.layers.whereType<OpacityLayer>().single.alpha,
      closeTo(fading, 1),
    );
    await tester.pump(AppMotion.fade ~/ 2);
    expect(
      tester.layers.whereType<OpacityLayer>().single.alpha,
      greaterThan(fading),
    );

    await tester.pumpAndSettle();
    expect(opacityLayers(tester), 0);
    expect(topOf(tester, 'a'), 0);
    await tester.tapAt(const Offset(10, _rowHeight / 2));
    expect(tapped, ['a']);
  });

  testWidgets('一起淡出的書只回來一本，其他的照常淡完拿掉', (tester) async {
    final tapped = <String>[];
    Widget shelf(List<String> urls) => _TapShelf(urls: urls, onTap: tapped.add);

    await tester.pumpWidget(shelf(const ['a', 'b', 'c']));
    await tester.pumpWidget(shelf(const ['c']));
    await tester.pump(AppMotion.fade ~/ 2);

    // 圖層照書的順序：第一個是 a。a 回來後從當下的濃淡變濃，b 繼續變淡。
    List<int> alphas() => [
      for (final l in tester.layers.whereType<OpacityLayer>()) l.alpha!,
    ];
    final before = alphas();
    expect(before, hasLength(2));
    await tester.pumpWidget(shelf(const ['a', 'c']));
    await tester.pump(AppMotion.fade ~/ 4);
    final after = alphas();
    expect(after, hasLength(2));
    expect(after.first, greaterThan(before.first));
    expect(after.last, lessThan(before.last));

    await tester.pumpAndSettle();
    expect(find.text('b'), findsNothing);
    expect(topOf(tester, 'a'), 0);
    expect(topOf(tester, 'c'), _rowHeight);
    expect(opacityLayers(tester), 0);
    await tester.tapAt(const Offset(10, _rowHeight / 2));
    expect(tapped, ['a']);
  });

  testWidgets('淡完才回來的書也會淡回來', (tester) async {
    final tapped = <String>[];
    final shelf = GlobalKey<_TapShelfState>();
    Widget build(List<String> urls) =>
        _TapShelf(key: shelf, urls: urls, onTap: tapped.add);

    await tester.pumpWidget(build(const ['a', 'b']));
    await tester.pumpWidget(build(const ['b']));
    // 淡完的那一幀資料又恢復：淡完的回呼重建時，資料裡已經有 a。
    await tester.pump(AppMotion.fade);
    await tester.pumpWidget(build(const ['a', 'b']));
    await tester.pumpAndSettle();

    expect(opacityLayers(tester), 0);
    await tester.tapAt(const Offset(10, _rowHeight / 2));
    expect(tapped, ['a']);
  });

  testWidgets('關閉系統動畫時移出的書直接消失', (tester) async {
    await tester.pumpWidget(const _Shelf(urls: ['a', 'b']));
    await tester.pumpWidget(const _Shelf(urls: ['b'], animate: false));
    expect(find.text('a'), findsNothing);
    expect(topOf(tester, 'b'), 0);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('第一次載入不播動畫', (tester) async {
    await tester.pumpWidget(const _Shelf(urls: []));
    await tester.pumpWidget(const _Shelf(urls: ['a', 'b']));

    expect(opacityLayers(tester), 0);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('網格與列表互換、或關閉系統動畫時直接到位', (tester) async {
    await tester.pumpWidget(const _Shelf(urls: ['a', 'b']));

    await tester.pumpWidget(const _Shelf(urls: ['b', 'a'], grid: true));
    expect(topOf(tester, 'b'), 0);
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(
      const _Shelf(urls: ['a', 'b'], grid: true, animate: false),
    );
    expect(topOf(tester, 'a'), 0);
    expect(tester.hasRunningAnimations, isFalse);
  });

  for (final (label, grid, animate) in [
    ('換檢視', true, true),
    ('關閉系統動畫', false, false),
  ]) {
    testWidgets('換位途中$label，進行中的換位停在終點', (tester) async {
      await tester.pumpWidget(const _Shelf(urls: ['a', 'b', 'c']));
      await tester.pumpWidget(const _Shelf(urls: ['c', 'a', 'b']));
      await tester.pump(const Duration(milliseconds: 100));
      expect(topOf(tester, 'c'), greaterThan(0));

      await tester.pumpWidget(
        _Shelf(urls: const ['c', 'a', 'b'], grid: grid, animate: animate),
      );

      expect(tester.hasRunningAnimations, isFalse);
      expect(topOf(tester, 'c'), 0);
      expect(topOf(tester, 'a'), _rowHeight);
    });
  }

  testWidgets('換位中的書卡不接點擊，到位後恢復', (tester) async {
    final tapped = <String>[];
    Widget shelf(List<String> urls) => _TapShelf(urls: urls, onTap: tapped.add);

    await tester.pumpWidget(shelf(const ['a', 'b', 'c']));
    await tester.pumpWidget(shelf(const ['c', 'a', 'b']));
    await tester.pump(const Duration(milliseconds: 100));

    // c 的版面已在第一格，但還畫在半路；點第一格不會點到別的書。
    await tester.tapAt(const Offset(10, _rowHeight / 2));
    expect(tapped, isEmpty);

    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, _rowHeight / 2));
    expect(tapped, ['c']);
  });

  testWidgets('拖曳排序採用的新順序不再播一次', (tester) async {
    final shelf = GlobalKey<_ShelfState>();
    await tester.pumpWidget(_Shelf(key: shelf, urls: const ['a', 'b']));

    shelf.currentState!.motion.accept(const ['b', 'a']);
    await tester.pumpWidget(_Shelf(key: shelf, urls: const ['b', 'a']));

    expect(topOf(tester, 'b'), 0);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
