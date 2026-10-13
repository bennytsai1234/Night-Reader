import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_motion.dart';

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

class _ShelfState extends State<_Shelf> with SingleTickerProviderStateMixin {
  late final BookshelfLayoutMotion motion = BookshelfLayoutMotion(vsync: this);

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    motion.update(widget.urls, grid: widget.grid, animate: widget.animate);
    Widget item(String url) => BookshelfMotionItem(
      key: widget.keyed ? ValueKey(url) : null,
      id: url,
      motion: motion,
      child: SizedBox(height: _rowHeight, child: Text(url)),
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: widget.keyed
          ? ListView(children: [for (final url in widget.urls) item(url)])
          : ListView.builder(
              itemCount: widget.urls.length,
              itemBuilder: (context, index) => item(widget.urls[index]),
            ),
    );
  }
}

/// 每本書可點的書架，給點擊測試用。
class _TapShelf extends StatefulWidget {
  const _TapShelf({required this.urls, required this.onTap});

  final List<String> urls;
  final ValueChanged<String> onTap;

  @override
  State<_TapShelf> createState() => _TapShelfState();
}

class _TapShelfState extends State<_TapShelf>
    with SingleTickerProviderStateMixin {
  late final BookshelfLayoutMotion motion = BookshelfLayoutMotion(vsync: this);

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    motion.update(widget.urls, grid: false, animate: true);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ListView(
        children: [
          for (final url in widget.urls)
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
