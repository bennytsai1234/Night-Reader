import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/document_index.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/measurement_store.dart';
import 'package:night_reader/features/reader_v2/hybrid/paragraph/paragraph_cache.dart';

import 'cached_block_widget.dart';

final class HybridScrollView extends StatelessWidget {
  HybridScrollView({
    super.key,
    required this.documentIndex,
    required this.namespace,
    required this.measurementStore,
    required this.paragraphCache,
    required this.epoch,
    this.controller,
    this.cacheExtent,
  }) : _centerKey = GlobalKey(debugLabel: 'hybrid-center-sliver');

  final DocumentIndex documentIndex;
  final MeasurementNamespace namespace;
  final MeasurementStore measurementStore;
  final ParagraphCache paragraphCache;
  final LayoutEpoch epoch;
  final ScrollController? controller;
  final double? cacheExtent;
  final GlobalKey _centerKey;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      thumbVisibility: false,
      child: CustomScrollView(
        controller: controller,
        center: _centerKey,
        physics: const HybridScrollPhysics(),
        scrollCacheExtent:
            cacheExtent == null ? null : ScrollCacheExtent.pixels(cacheExtent!),
        slivers: <Widget>[
          _buildSliver(beforeCenter: true),
          _buildSliver(key: _centerKey, beforeCenter: false),
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
        return CachedBlockWidget(
          blockKey: key,
          epoch: epoch,
          namespace: namespace,
          measurementStore: measurementStore,
          paragraphCache: paragraphCache,
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
    var count = 0;
    while (documentIndex.keyForSliverIndex(
          beforeCenter: beforeCenter,
          index: count,
        ) !=
        null) {
      count += 1;
    }
    return count;
  }
}

final class HybridScrollPhysics extends ClampingScrollPhysics {
  const HybridScrollPhysics({
    super.parent,
    this.applyUnreadyFriction = false,
    this.unreadyFriction = 0.45,
  });

  final bool applyUnreadyFriction;
  final double unreadyFriction;

  @override
  HybridScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return HybridScrollPhysics(
      parent: buildParent(ancestor),
      applyUnreadyFriction: applyUnreadyFriction,
      unreadyFriction: unreadyFriction,
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (applyUnreadyFriction) return offset * unreadyFriction;
    return super.applyPhysicsToUserOffset(position, offset);
  }
}
