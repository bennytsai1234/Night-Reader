import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'package:night_reader/features/reader_v2/hybrid/measure/document_index.dart';

/// [SliverVariedExtentList] 的 hybrid 特化版。
///
/// 框架基底 `RenderSliverFixedExtentBoxAdaptor` 在 `itemExtentBuilder` 模式
/// 下，offset↔index 與 index→layoutOffset 的換算全部從 index 0 線性累加：
/// 每個滾動幀 O(F×v)（F=視窗上方子項數）。DocumentIndex 只增不減，讀得越久
/// F 越大——這正是「越滾越卡」的來源。本類以 [DocumentIndex] 的 Fenwick
/// 前綴和覆寫這些查詢為 O(log n)，幾何結果與框架線性版本逐點一致，
/// I1（extent 只讀精確 metrics）不受影響。
final class HybridBlockSliver extends SliverVariedExtentList {
  const HybridBlockSliver({
    super.key,
    required super.delegate,
    required super.itemExtentBuilder,
    required this.documentIndex,
    required this.beforeCenter,
  });

  final DocumentIndex documentIndex;
  final bool beforeCenter;

  @override
  RenderHybridBlockSliver createRenderObject(BuildContext context) {
    final element = context as SliverMultiBoxAdaptorElement;
    return RenderHybridBlockSliver(
      childManager: element,
      itemExtentBuilder: itemExtentBuilder,
      documentIndex: documentIndex,
      beforeCenter: beforeCenter,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderHybridBlockSliver renderObject,
  ) {
    super.updateRenderObject(context, renderObject);
    renderObject
      ..documentIndex = documentIndex
      ..beforeCenter = beforeCenter;
  }
}

final class RenderHybridBlockSliver extends RenderSliverVariedExtentList {
  RenderHybridBlockSliver({
    required super.childManager,
    required super.itemExtentBuilder,
    required DocumentIndex documentIndex,
    required bool beforeCenter,
  }) : _documentIndex = documentIndex,
       _beforeCenter = beforeCenter;

  DocumentIndex _documentIndex;
  set documentIndex(DocumentIndex value) {
    if (identical(_documentIndex, value)) return;
    if (attached) _documentIndex.revision.removeListener(_handleRevision);
    _documentIndex = value;
    if (attached) _documentIndex.revision.addListener(_handleRevision);
    markNeedsLayout();
  }

  /// 放行/重建直驅重排：新 block 的材料化只需本 sliver relayout（extent、
  /// childCount 皆即時讀 [DocumentIndex]），widget 層不參與。
  void _handleRevision() => markNeedsLayout();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _documentIndex.revision.addListener(_handleRevision);
  }

  @override
  void detach() {
    _documentIndex.revision.removeListener(_handleRevision);
    super.detach();
  }

  bool _beforeCenter;
  set beforeCenter(bool value) {
    if (_beforeCenter == value) return;
    _beforeCenter = value;
    markNeedsLayout();
  }

  @override
  double indexToLayoutOffset(double itemExtent, int index) {
    return _documentIndex.sliverLayoutOffset(
      beforeCenter: _beforeCenter,
      index: index,
    );
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset, double itemExtent) {
    return _documentIndex.sliverIndexForScrollOffset(
      beforeCenter: _beforeCenter,
      scrollOffset: scrollOffset,
    );
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset, double itemExtent) {
    return _documentIndex.sliverIndexForScrollOffset(
      beforeCenter: _beforeCenter,
      scrollOffset: scrollOffset,
    );
  }

  @override
  double computeMaxScrollOffset(
    SliverConstraints constraints,
    double itemExtent,
  ) {
    return _documentIndex.sliverScrollExtent(beforeCenter: _beforeCenter);
  }

  /// 框架預設走 childManager 的外插估計；這裡有精確總 extent，直接回傳，
  /// 避免 fling 中 scrollExtent 估飄再回正造成的視覺跳動。
  @override
  double estimateMaxScrollOffset(
    SliverConstraints constraints, {
    int? firstIndex,
    int? lastIndex,
    double? leadingScrollOffset,
    double? trailingScrollOffset,
  }) {
    return _documentIndex.sliverScrollExtent(beforeCenter: _beforeCenter);
  }
}
