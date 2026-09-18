import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/document_index.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/measurement_store.dart';
import 'package:night_reader/features/reader_v2/hybrid/paragraph/paragraph_cache.dart';
import 'package:night_reader/features/reader_v2/hybrid/view/cached_block_widget.dart';
import 'package:night_reader/features/reader_v2/hybrid/view/hybrid_scroll_view.dart';

/// A1 去 setState 化的守門員：放行新 block 只靠 DocumentIndex.revision →
/// RenderHybridBlockSliver.markNeedsLayout 直驅材料化，widget 樹零重建。
/// 若有人把 childCount 改回 build 時凍結（SliverChildBuilderDelegate 模式），
/// 本測試會失敗——新 block 在下一次 setState 前不可見。
void main() {
  StyleFingerprint fingerprint() {
    return const StyleFingerprint(
      viewportWidth: 800,
      viewportHeight: 600,
      contentWidth: 760,
      contentHeight: 560,
      fontSize: 18,
      lineHeight: 1.6,
      letterSpacing: 0,
      paragraphSpacing: 1,
      paddingTop: 8,
      paddingBottom: 8,
      paddingLeft: 16,
      paddingRight: 16,
      textIndent: 2,
      bold: false,
      justify: true,
      textScaleFactor: 1,
      fontFamilySignature: 'system',
      platformFontSignature: 'test',
    );
  }

  testWidgets('放行新 block 不經 setState 即可見（revision 直驅 relayout）', (
    tester,
  ) async {
    final index = DocumentIndex(
      centerKey: const BlockKey(chapterIndex: 0, blockIndex: 0),
    );
    final store = MeasurementStore();
    final cache = ParagraphCache();
    final namespace = MeasurementNamespace(
      epoch: LayoutEpoch.initial,
      fingerprint: fingerprint(),
    );
    const firstKey = BlockKey(chapterIndex: 0, blockIndex: 0);
    _putParagraph(cache, firstKey, '第一塊');
    index.admit(
      firstKey,
      const BlockMetrics(height: 100, lineCount: 1),
    );
    final centerKey = GlobalKey(debugLabel: 'center');

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: HybridScrollView(
          centerKey: centerKey,
          documentIndex: index,
          namespace: namespace,
          measurementStore: store,
          paragraphCache: cache,
          epoch: LayoutEpoch.initial,
          cacheExtent: 600,
        ),
      ),
    );
    expect(find.byType(CachedBlockWidget), findsOneWidget);

    // 不重建 widget 樹（無 pumpWidget/setState），直接放行後續 block：
    // 前向與後向各一，驗證雙 sliver 都被 revision 直驅。
    const secondKey = BlockKey(chapterIndex: 0, blockIndex: 1);
    _putParagraph(cache, secondKey, '第二塊');
    index.admit(
      secondKey,
      const BlockMetrics(height: 120, lineCount: 2),
    );
    await tester.pump();
    expect(find.byType(CachedBlockWidget), findsNWidgets(2));

    const thirdKey = BlockKey(chapterIndex: 1, blockIndex: 0);
    _putParagraph(cache, thirdKey, '第三塊');
    index.admit(
      thirdKey,
      const BlockMetrics(height: 80, lineCount: 1),
    );
    await tester.pump();
    expect(find.byType(CachedBlockWidget), findsNWidgets(3));

    cache.dispose();
  });

  testWidgets('reset 後既有 child 會改用新的 block key', (tester) async {
    final index = DocumentIndex(
      centerKey: const BlockKey(chapterIndex: 0, blockIndex: 0),
    );
    final store = MeasurementStore();
    final cache = ParagraphCache();
    final namespace = MeasurementNamespace(
      epoch: LayoutEpoch.initial,
      fingerprint: fingerprint(),
    );
    final centerKey = GlobalKey(debugLabel: 'center');
    Widget buildView() {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: HybridScrollView(
          centerKey: centerKey,
          documentIndex: index,
          namespace: namespace,
          measurementStore: store,
          paragraphCache: cache,
          epoch: LayoutEpoch.initial,
          cacheExtent: 600,
        ),
      );
    }

    for (var i = 0; i < 3; i += 1) {
      final key = BlockKey(chapterIndex: 0, blockIndex: i);
      _putParagraph(cache, key, '舊章第$i塊');
      index.admit(
        key,
        const BlockMetrics(height: 100, lineCount: 1),
      );
    }
    await tester.pumpWidget(buildView());
    expect(find.byType(CachedBlockWidget), findsNWidgets(3));

    const resetCenter = BlockKey(chapterIndex: 1, blockIndex: 0);
    index.reset(centerKey: resetCenter);
    // The reset can be observed by the mounted sliver before the next block
    // has been measured/admitted. Flutter's render implementation force-
    // unwraps itemExtentBuilder's result, so this transition must stay safe.
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(CachedBlockWidget), findsNothing);

    _putParagraph(cache, resetCenter, '新章');
    index.admit(resetCenter, const BlockMetrics(height: 90, lineCount: 1));
    // 結構性 reset 會由 screen 的 scheduleRebuild 觸發父層 rebuild；
    // generation 變更必須讓既有 sliver child 改用新 key。
    await tester.pumpWidget(buildView());
    expect(find.byType(CachedBlockWidget), findsOneWidget);
    expect(
      tester.widget<CachedBlockWidget>(find.byType(CachedBlockWidget)).blockKey,
      resetCenter,
    );
    expect(tester.takeException(), isNull);

    cache.dispose();
  });
}


void _putParagraph(ParagraphCache cache, BlockKey key, String text) {
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(textDirection: ui.TextDirection.ltr),
  )..addText(text);
  final paragraph = builder.build()
    ..layout(const ui.ParagraphConstraints(width: 760));
  cache.put(key, LayoutEpoch.initial, paragraph);
}
