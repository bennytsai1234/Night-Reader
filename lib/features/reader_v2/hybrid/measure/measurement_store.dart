import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

enum MetricsInvalidationCause { style, viewportWidth, content, platformFont }

final class MeasurementStore implements HybridMeasurementStore {
  final Map<MeasurementNamespace, Map<BlockKey, BlockMetrics>> _metrics =
      <MeasurementNamespace, Map<BlockKey, BlockMetrics>>{};

  @override
  BlockMetrics? get(MeasurementNamespace namespace, BlockKey key) {
    return _metrics[namespace]?[key];
  }

  @override
  void put(MeasurementNamespace namespace, BlockKey key, BlockMetrics metrics) {
    (_metrics[namespace] ??= <BlockKey, BlockMetrics>{})[key] = metrics;
  }

  @override
  void invalidateNamespace(MeasurementNamespace namespace) {
    _metrics.remove(namespace);
  }

  @override
  void invalidateChapter(int chapterIndex) {
    for (final namespace in _metrics.values) {
      namespace.removeWhere((key, _) => key.chapterIndex == chapterIndex);
    }
  }

  void invalidateFor({
    required MetricsInvalidationCause cause,
    int? chapterIndex,
  }) {
    switch (cause) {
      case MetricsInvalidationCause.content:
        assert(chapterIndex != null);
        if (chapterIndex != null) invalidateChapter(chapterIndex);
      case MetricsInvalidationCause.style:
      case MetricsInvalidationCause.viewportWidth:
      case MetricsInvalidationCause.platformFont:
        _metrics.clear();
    }
  }

  int count(MeasurementNamespace namespace) => _metrics[namespace]?.length ?? 0;
}
