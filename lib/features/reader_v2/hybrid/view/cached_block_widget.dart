import 'package:flutter/widgets.dart';

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/measurement_store.dart';
import 'package:night_reader/features/reader_v2/hybrid/paragraph/paragraph_cache.dart';

final class CachedBlockWidget extends LeafRenderObjectWidget {
  const CachedBlockWidget({
    super.key,
    required this.blockKey,
    required this.epoch,
    required this.namespace,
    required this.measurementStore,
    required this.paragraphCache,
  });

  final BlockKey blockKey;
  final LayoutEpoch epoch;
  final MeasurementNamespace namespace;
  final MeasurementStore measurementStore;
  final ParagraphCache paragraphCache;

  @override
  RenderCachedBlock createRenderObject(BuildContext context) {
    return RenderCachedBlock(
      blockKey: blockKey,
      epoch: epoch,
      namespace: namespace,
      measurementStore: measurementStore,
      paragraphCache: paragraphCache,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderCachedBlock renderObject,
  ) {
    renderObject
      ..blockKey = blockKey
      ..epoch = epoch
      ..namespace = namespace
      ..measurementStore = measurementStore
      ..paragraphCache = paragraphCache;
  }
}

final class RenderCachedBlock extends RenderBox {
  RenderCachedBlock({
    required BlockKey blockKey,
    required LayoutEpoch epoch,
    required MeasurementNamespace namespace,
    required MeasurementStore measurementStore,
    required ParagraphCache paragraphCache,
  }) : _blockKey = blockKey,
       _epoch = epoch,
       _namespace = namespace,
       _measurementStore = measurementStore,
       _paragraphCache = paragraphCache;

  BlockKey _blockKey;
  LayoutEpoch _epoch;
  MeasurementNamespace _namespace;
  MeasurementStore _measurementStore;
  ParagraphCache _paragraphCache;

  set blockKey(BlockKey value) {
    if (_blockKey == value) return;
    _blockKey = value;
    markNeedsLayout();
  }

  set epoch(LayoutEpoch value) {
    if (_epoch == value) return;
    _epoch = value;
    markNeedsPaint();
  }

  set namespace(MeasurementNamespace value) {
    if (_namespace == value) return;
    _namespace = value;
    markNeedsLayout();
  }

  set measurementStore(MeasurementStore value) {
    if (identical(_measurementStore, value)) return;
    _measurementStore = value;
    markNeedsLayout();
  }

  set paragraphCache(ParagraphCache value) {
    if (identical(_paragraphCache, value)) return;
    _paragraphCache = value;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    final metrics = _measurementStore.get(_namespace, _blockKey);
    assert(metrics != null, 'I1: RenderCachedBlock requires exact metrics.');
    final height = metrics?.height ?? 1.0;
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final paragraph = _paragraphCache.acquire(_blockKey, _epoch);
    if (paragraph == null) return;
    final canvas = context.canvas;
    canvas.saveLayer(offset & size, Paint());
    canvas.drawParagraph(paragraph, offset);
    canvas.restore();
  }

  @override
  bool get isRepaintBoundary => true;
}
