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
    index.admit(
      const BlockKey(chapterIndex: 0, blockIndex: 0),
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
    index.admit(
      const BlockKey(chapterIndex: 0, blockIndex: 1),
      const BlockMetrics(height: 120, lineCount: 2),
    );
    await tester.pump();
    expect(find.byType(CachedBlockWidget), findsNWidgets(2));

    index.admit(
      const BlockKey(chapterIndex: 1, blockIndex: 0),
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
      index.admit(
        BlockKey(chapterIndex: 0, blockIndex: i),
        const BlockMetrics(height: 100, lineCount: 1),
      );
    }
    await tester.pumpWidget(buildView());
    expect(find.byType(CachedBlockWidget), findsNWidgets(3));

    const resetCenter = BlockKey(chapterIndex: 1, blockIndex: 0);
    index.reset(centerKey: resetCenter);
    index.admit(resetCenter, const BlockMetrics(height: 90, lineCount: 1));
    // 結構性 reset 會由 screen 的 scheduleRebuild 觸發父層 rebuild；
    // generation 變更必須讓既有 sliver child 改用新 key。
    await tester.pumpWidget(buildView());
    expect(find.byType(CachedBlockWidget), findsOneWidget);
    expect(
      tester.widget<CachedBlockWidget>(find.byType(CachedBlockWidget)).blockKey,
      resetCenter,
    );

    cache.dispose();
  });
}
