import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/measurement_store.dart';
import 'package:night_reader/features/reader_v2/hybrid/paragraph/paragraph_cache.dart';
import 'package:night_reader/features/reader_v2/hybrid/view/cached_block_widget.dart';

/// 自癒重繪的守門員：paint 撲空（段落未建或被 LRU 逐出）的 block 必須在
/// 段落補建（put）當下自動 markNeedsPaint，不得依賴 sliver 子項被回收再
/// materialize 才恢復——否則已放行 block 會停留在佔位空白。
void main() {
  const key = BlockKey(chapterIndex: 0, blockIndex: 0);
  const epoch = LayoutEpoch.initial;

  Future<void> pumpBlock(
    WidgetTester tester,
    MeasurementStore store,
    ParagraphCache cache,
  ) {
    return tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 200,
          height: 60,
          child: CachedBlockWidget(
            blockKey: key,
            epoch: epoch,
            namespace: MeasurementNamespace(
              epoch: epoch,
              fingerprint: _fingerprint(),
            ),
            measurementStore: store,
            paragraphCache: cache,
          ),
        ),
      ),
    );
  }

  testWidgets('paint 撲空的 block 在段落補建後自動重繪', (tester) async {
    final store = MeasurementStore();
    final cache = ParagraphCache();
    addTearDown(cache.dispose);

    await pumpBlock(tester, store, cache);
    final renderObject = tester.renderObject<RenderCachedBlock>(
      find.byType(CachedBlockWidget),
    );
    expect(renderObject, isNot(paints..paragraph()));

    cache.put(key, epoch, _paragraph('自癒重繪'));
    expect(
      renderObject.debugNeedsPaint,
      isTrue,
      reason: 'put 當下必須觸發 markNeedsPaint',
    );
    await tester.pump();
    expect(renderObject, paints..paragraph());
  });

  testWidgets('block 卸載後段落補建不得回呼已 detach 的 render object', (
    tester,
  ) async {
    final store = MeasurementStore();
    final cache = ParagraphCache();
    addTearDown(cache.dispose);

    await pumpBlock(tester, store, cache);
    await tester.pumpWidget(const SizedBox.shrink());

    // detach 必須取消 waiter：put 若打到已卸載的 render object 會炸 assert。
    cache.put(key, epoch, _paragraph('晚到的段落'));
    expect(tester.takeException(), isNull);
  });
}

ui.Paragraph _paragraph(String text) {
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(textDirection: ui.TextDirection.ltr),
  )..addText(text);
  return builder.build()..layout(const ui.ParagraphConstraints(width: 100));
}

StyleFingerprint _fingerprint() {
  return const StyleFingerprint(
    viewportWidth: 320,
    viewportHeight: 640,
    contentWidth: 288,
    contentHeight: 600,
    fontSize: 18,
    lineHeight: 1.5,
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
