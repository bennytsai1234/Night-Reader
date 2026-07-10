import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/document_index.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/measurement_store.dart';
import 'package:night_reader/features/reader_v2/hybrid/paragraph/paragraph_cache.dart';

import 'cached_block_widget.dart';

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
    return SliverVariedExtentList.builder(
      key: key,
      itemCount: _itemCount(beforeCenter: beforeCenter),
      itemBuilder: (context, index) {
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
      },
      itemExtentBuilder: (index, dimensions) {
        final key = documentIndex.keyForSliverIndex(
          beforeCenter: beforeCenter,
          index: index,
        );
        if (key == null) return null;
        final metrics = measurementStore.get(namespace, key);
        assert(
          metrics != null,
          'I1: Sliver itemExtentBuilder requires exact metrics for $key.',
        );
        return metrics?.height;
      },
    );
  }

  int _itemCount({required bool beforeCenter}) {
    return beforeCenter
        ? documentIndex.beforeCount
        : documentIndex.centerAndAfterCount;
  }
}

final class HybridScrollPhysics extends ClampingScrollPhysics {
  const HybridScrollPhysics({
    super.parent,
    this.applyForwardFriction = false,
    this.applyBackwardFriction = false,
    this.unreadyFriction = 0.45,
  });

  final bool applyForwardFriction;
  final bool applyBackwardFriction;
  final double unreadyFriction;

  @override
  HybridScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return HybridScrollPhysics(
      parent: buildParent(ancestor),
      applyForwardFriction: applyForwardFriction,
      applyBackwardFriction: applyBackwardFriction,
      unreadyFriction: unreadyFriction,
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    final towardForward = offset < 0;
    if ((towardForward && applyForwardFriction) ||
        (!towardForward && applyBackwardFriction)) {
      return offset * unreadyFriction;
    }
    return super.applyPhysicsToUserOffset(position, offset);
  }
}
