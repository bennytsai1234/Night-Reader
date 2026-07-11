import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/document_index.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/measurement_store.dart';
import 'package:night_reader/features/reader_v2/hybrid/paragraph/paragraph_cache.dart';

import 'admission_controller.dart';
import 'cached_block_widget.dart';
import 'hybrid_block_sliver.dart';

final class HybridScrollView extends StatelessWidget {
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

  /// 呼叫端應跨 rebuild 持同一顆實例：`Scrollable` 只在 physics 的
  /// runtimeType 鏈變化時才重建 position，position 抱的是第一顆實例；
  /// 動態狀態（領先量摩擦）由 physics 內部即時查詢，不靠重建傳遞。
  final ScrollPhysics physics;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    // D4：原生 Scrollbar 停用；無回彈由 HybridScrollPhysics（Clamping 基底）保證。
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(
        context,
      ).copyWith(scrollbars: false, overscroll: false),
      child: CustomScrollView(
        controller: controller,
        center: centerKey,
        physics: physics,
        scrollCacheExtent:
            cacheExtent == null ? null : ScrollCacheExtent.pixels(cacheExtent!),
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
        if (key == null) return null;
        // extent 讀 DocumentIndex 的 admitted metrics，與 Fenwick 座標同源
        // （I1/I3：admit 時已是精確量測且座標凍結）。不可讀 MeasurementStore
        // ——epoch 換代或章節 invalidate 的過渡幀，store 可能已被清而 widget
        // 還抱著舊 namespace closure，會出現座標與 extent 失同步。
        final metrics = documentIndex.metricsFor(key);
        assert(
          metrics != null,
          'I1: Sliver itemExtentBuilder requires admitted metrics for $key.',
        );
        return metrics?.height;
      },
    );
  }
}

/// 即時讀 [DocumentIndex] 的 child delegate。
///
/// 取代 `SliverChildBuilderDelegate`：childCount 不在 build 時凍結，
/// 新放行 block 由 [DocumentIndex.revision] → render 層 markNeedsLayout
/// 直接材料化，不需要 setState 重建整棵滾動子樹（fling 幀 build 歸零）。
/// [RenderCachedBlock] 自身即 repaint boundary，故不再額外包
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
  int? get estimatedChildCount =>
      beforeCenter
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
  const HybridScrollPhysics({
    super.parent,
    this.admission,
    this.unreadyFriction = 0.45,
    this.deficitFlingFriction = 0.09,
    this.baseFlingFriction = 0.015,
  });

  final AdmissionController? admission;

  /// 領先量完全耗盡時拖曳位移的衰減倍率下限。
  final double unreadyFriction;

  /// 領先量完全耗盡時 fling 模擬的摩擦係數上限（框架預設 0.015 的 6 倍）。
  final double deficitFlingFriction;

  /// 框架 [ClampingScrollSimulation] 的預設摩擦，作為連續內插的下端。
  final double baseFlingFriction;

  @override
  HybridScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return HybridScrollPhysics(
      parent: buildParent(ancestor),
      admission: admission,
      unreadyFriction: unreadyFriction,
      deficitFlingFriction: deficitFlingFriction,
      baseFlingFriction: baseFlingFriction,
    );
  }

  /// 0=領先量充足、1=完全耗盡。admission 提供含遲滯的 smoothstep 曲線，
  /// 讓 admission 增長觸發 simulation 重建時，摩擦連續過渡而非二態跳變。
  double _scaleToward({required bool forward}) {
    return admission?.frictionScaleToward(forward: forward) ?? 0.0;
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    // offset 為指針位移：負值 = 內容前進（pixels 增加）。
    final scale = _scaleToward(forward: offset < 0);
    if (scale > 0) {
      return offset * (1.0 + (unreadyFriction - 1.0) * scale);
    }
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // velocity > 0 = pixels 增加 = 向前。行進方向領先量偏低時以連續加重
    // 的摩擦收斂；領先量充足或已到書首/書尾邊界則維持框架行為。
    if (!position.outOfRange &&
        velocity.abs() >= toleranceFor(position).velocity) {
      final scale = _scaleToward(forward: velocity > 0);
      if (scale > 0) {
        if (velocity > 0.0 && position.pixels >= position.maxScrollExtent) {
          return null;
        }
        if (velocity < 0.0 && position.pixels <= position.minScrollExtent) {
          return null;
        }
        return ClampingScrollSimulation(
          position: position.pixels,
          velocity: velocity,
          friction:
              baseFlingFriction +
              (deficitFlingFriction - baseFlingFriction) * scale,
          tolerance: toleranceFor(position),
        );
      }
    }
    return super.createBallisticSimulation(position, velocity);
  }
}
