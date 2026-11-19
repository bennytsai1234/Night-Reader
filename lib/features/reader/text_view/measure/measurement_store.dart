import 'package:night_reader/features/reader/text_view/core/text_view_types.dart';

enum MetricsInvalidationCause { style, viewportWidth, content, platformFont }

final class MeasurementStore {
  final Map<MeasurementNamespace, Map<BlockKey, BlockMetrics>> _metrics =
      <MeasurementNamespace, Map<BlockKey, BlockMetrics>>{};

  BlockMetrics? get(MeasurementNamespace namespace, BlockKey key) {
    return _metrics[namespace]?[key];
  }

  void put(MeasurementNamespace namespace, BlockKey key, BlockMetrics metrics) {
    (_metrics[namespace] ??= <BlockKey, BlockMetrics>{})[key] = metrics;
  }

  void invalidateNamespace(MeasurementNamespace namespace) {
    _metrics.remove(namespace);
  }

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

  /// 取指定命名空間目前全部量測值的複本，供 DocumentIndex 重定中心後
  /// 一次性 re-admit（reset 會清掉 index 內的度量，store 仍是真相）。
  Map<BlockKey, BlockMetrics> snapshot(MeasurementNamespace namespace) {
    final entries = _metrics[namespace];
    if (entries == null) return <BlockKey, BlockMetrics>{};
    return Map<BlockKey, BlockMetrics>.of(entries);
  }
}
