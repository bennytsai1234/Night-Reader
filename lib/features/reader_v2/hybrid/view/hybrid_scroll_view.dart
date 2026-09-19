import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/document_index.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/measurement_store.dart';
import 'package:night_reader/features/reader_v2/hybrid/paragraph/paragraph_cache.dart';

import 'cached_block_widget.dart';
import 'hybrid_block_sliver.dart';

final class HybridScrollView extends StatelessWidget {
  /// Flutter's RenderSliverFixedExtentBoxAdaptor force-unwraps the result of
  /// itemExtentBuilder while laying out active children. DocumentIndex can be
  /// reset before the old sliver has been removed from the render tree, so the
  /// callback must remain total during that transition.
  ///
  /// 這個值不會污染滾動幾何：`scrollExtent`、`maxPaintExtent`、各 child 的
  /// `layoutOffset` 與 `firstIndex`/`targetLastIndex` 全部由
  /// [RenderHybridBlockSliver] 的 Fenwick 覆寫算出，那些路徑不呼叫
  /// itemExtentBuilder。它只會成為某個下一幀就會被回收的殘留 child 的
  /// BoxConstraints。真正可見的位移來自索引本身合法地變空（I3 漸進重建），
  /// 不是這個值。
  static const double _fallbackItemExtent = 1.0;

  const HybridScrollView({
    super.key,
    required this.centerKey,
    required this.documentIndex,
    required this.namespace,
    required this.measurementStore,
    required this.paragraphCache,
    required this.epoch,
    this.controller,
    this.cacheExtent,
    this.horizontalPadding = EdgeInsets.zero,
    this.physics = const HybridScrollPhysics(),
    this.textColor = const Color(0xFF000000),
  });

  /// center sliver 的 key。必須由呼叫端持有並跨 rebuild 穩定——
  /// 每次 build 換 key 會讓 CustomScrollView 整個 sliver 重掛。
  final GlobalKey centerKey;
  final DocumentIndex documentIndex;
  final MeasurementNamespace namespace;
  final MeasurementStore measurementStore;
  final ParagraphCache paragraphCache;
  final LayoutEpoch epoch;
  final ScrollController? controller;
  final double? cacheExtent;
  final EdgeInsets horizontalPadding;

  /// Native scroll physics. Materialization never scales pointer deltas or
  /// changes the ballistic trajectory based on paragraph readiness.
  final ScrollPhysics physics;
  final Color textColor;

  @override
  Widget build  @override
  Widget build(BuildContext context) {
    // D4：原生 Scrollbar 停用；無回彈由 HybridScrollPhysics（Clamping 基底）保證。
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context)
          .copyWith(scrollbars: false, overscroll: false),
      child: CustomScrollView(
        controller: controller,
        center: centerKey,
        physics: physics,
        scrollCacheExtent: cacheExtent == null
            ? null
            : ScrollCacheExtent.pixels(cacheExtent!),
        slivers: <Widget>[
          _buildSliver(beforeCenter: true),
          _buildSliver(key: centerKey, beforeCenter: false),
        ],
      ),
    );
  }

  Widget _buildSliver({Key? key, required bool beforeCenter}) {
    return HybridBlockSliver(
      key: key,
      documentIndex: documentIndex,
      beforeCenter: beforeCenter,
      delegate: HybridSliverChildDelegate(
        documentIndex: documentIndex,
        beforeCenter: beforeCenter,
        resetGeneration: documentIndex.resetGeneration,
        namespace: namespace,
        measurementStore: measurementStore,
        paragraphCache: paragraphCache,
        epoch: epoch,
        textColor: textColor,
        horizontalPadding: horizontalPadding,
      ),
      itemExtentBuilder: (index, dimensions) {
        final key = documentIndex.keyForSliverIndex(
          beforeCenter: beforeCenter,
          index: index,
        );
        if (key == null) {
          return _fallbackItemExtent;
        }
        // extent 讀 DocumentIndex 的 admitted metrics，與 Fenwick 座標同源
        // （I1/I3：admit 時已是精確量測且座標凍結）。不可讀 MeasurementStore
        // ——epoch 換代或章節 invalidate 的過渡幀，store 可能已被清而 widget
        // 還抱著舊 namespace closure，會出現座標與 extent 失同步。
        final metrics = documentIndex.metricsFor(key);
        final extent = metrics?.height;
        // 這一支目前結構上不可達：`_metrics` 與兩側清單在每個可觀察點都
        // 一致，且 BlockMetrics 保證 height > 0（兩個生產者都有 guard）。
        // 保留是因為 itemExtentBuilder 被框架強制解包，必須是全函式。
        if (extent == null || !extent.isFinite || extent <= 0) {
          return _fallbackItemExtent;
        }
        return extent;
      },
    );
  }
}

/// 即時讀 [DocumentIndex] 的 child delegate。
///
/// 取代 `SliverChildBuilderDelegate`：childCount 不在 build 時凍結，
/// 新放行 block 由 [DocumentIndex.revision] → render 層 markNeedsLayout
/// 直接材料化，不需要 setState 重建整棵滾動子樹（fling 幀 build 歸零）。
/// [RenderCachedBlock] 不建立獨立 repaint boundary，讓共用的 scroll surface
/// 在滾動時以較少的 layer composition 成本重繪；故不再額外包
/// RepaintBoundary / AutomaticKeepAlive。
final class HybridSliverChildDelegate extends SliverChildDelegate {
  const HybridSliverChildDelegate({
    required this.documentIndex,
    required this.beforeCenter,
    required this.resetGeneration,
    required this.namespace,
    required this.measurementStore,
    required this.paragraphCache,
    required this.epoch,
    required this.textColor,
    required this.horizontalPadding,
  });

  final DocumentIndex documentIndex;
  final bool beforeCenter;
  final int resetGeneration;
  final MeasurementNamespace namespace;
  final MeasurementStore measurementStore;
  final ParagraphCache paragraphCache;
  final LayoutEpoch epoch;
  final Color textColor;
  final EdgeInsets horizontalPadding;

  @override
  Widget? build(BuildContext context, int index) {
    final key = documentIndex.keyForSliverIndex(
      beforeCenter: beforeCenter,
      index: index,
    );
    if (key == null) return null;
    return Padding(
      padding: horizontalPadding,
      child: CachedBlockWidget(
        blockKey: key,
        epoch: epoch,
        namespace: namespace,
        measurementStore: measurementStore,
        paragraphCache: paragraphCache,
        textColor: textColor,
      ),
    );
  }

  @override
  int? get estimatedChildCount => beforeCenter
      ? documentIndex.beforeCount
      : documentIndex.centerAndAfterCount;

  @override
  bool shouldRebuild(covariant HybridSliverChildDelegate oldDelegate) {
    return !identical(documentIndex, oldDelegate.documentIndex) ||
        beforeCenter != oldDelegate.beforeCenter ||
        resetGeneration != oldDelegate.resetGeneration ||
        namespace != oldDelegate.namespace ||
        !identical(measurementStore, oldDelegate.measurementStore) ||
        !identical(paragraphCache, oldDelegate.paragraphCache) ||
        epoch != oldDelegate.epoch ||
        textColor != oldDelegate.textColor ||
        horizontalPadding != oldDelegate.horizontalPadding;
  }
}

/// Clamping 基底的閱讀器捲動物理。
///
/// [admission] 供**即時**查詢領先量狀態——`Scrollable` 只有 physics
/// runtimeType 鏈改變才會重建 position，用建構參數傳布林旗標的話，
/// position 永遠抱著第一顆實例、旗標永不更新（死代碼）。因此這裡持
/// controller 參考，於 [applyPhysicsToUserOffset] / [createBallisticSimulation]
/// 呼叫當下讀取現值。
final class HybridScrollPhysics extends ClampingScrollPhysics {
  const HybridScrollPhysics({super.parent});
  @override
  HybridScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      HybridScrollPhysics(parent: buildParent(ancestor));
}
