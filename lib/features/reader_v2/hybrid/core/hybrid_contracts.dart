import 'dart:ui' as ui;

import 'hybrid_types.dart';

abstract interface class HybridMeasurementStore {
  BlockMetrics? get(MeasurementNamespace namespace, BlockKey key);
  void put(MeasurementNamespace namespace, BlockKey key, BlockMetrics metrics);
  void invalidateNamespace(MeasurementNamespace namespace);
  void invalidateChapter(int chapterIndex);
}

abstract interface class HybridDocumentIndex {
  BlockKey? blockAtOffset(double offset);
  double? topOf(BlockKey key);
  double? bottomOf(BlockKey key);
  BlockKey? keyForSliverIndex({required bool beforeCenter, required int index});
  double chapterExtent(int chapterIndex);
}

abstract interface class HybridChapterTextRepository {
  Future<ChapterText> load(ChapterId id);
  void setPrefetchCenter(ChapterId id);
  Stream<ChapterEvent> get events;
}

abstract interface class HybridTextPreprocessor {
  Future<ChapterBlocks> process(ChapterText chapter, {int maxBlockChars});
}

abstract interface class HybridParagraphCache {
  ui.Paragraph? acquire(BlockKey key, LayoutEpoch epoch);
  void put(
    BlockKey key,
    LayoutEpoch epoch,
    ui.Paragraph paragraph, {
    ui.Color bakedColor,
  });
  void pinRange(BlockRange range);
  void unpinAll();
  void dispose();
}

/// I4: this is the only contract allowed to build and lay out [ui.Paragraph].
abstract interface class HybridLayoutPump {
  void submit(LayoutTask task);
  void onScrollStateChanged(PumpState state);
  Stream<BlockReady> get completed;
  void dispose();
}

abstract interface class HybridProgressCalculator {
  HybridProgressSnapshot progressForOffset(double offset);
}

final class HybridProgressSnapshot {
  const HybridProgressSnapshot({
    required this.chapterIndex,
    required this.chapterCount,
    required this.chapterPercent,
  }) : assert(chapterCount >= 0),
       assert(chapterPercent >= 0),
       assert(chapterPercent <= 100);

  final int chapterIndex;
  final int chapterCount;
  final double chapterPercent;

  String get chapterLabel {
    if (chapterCount <= 0) return '第 0 章';
    return '第 ${chapterIndex + 1}/$chapterCount 章';
  }

  String get percentLabel => '${chapterPercent.toStringAsFixed(1)}%';

  /// 這是資訊列的顯示模型；小於 0.1% 的 raw progress 變化不應觸發
  /// widget rebuild。
  @override
  bool operator ==(Object other) {
    return other is HybridProgressSnapshot &&
        other.chapterIndex == chapterIndex &&
        other.chapterCount == chapterCount &&
        other.percentLabel == percentLabel;
  }

  @override
  int get hashCode => Object.hash(chapterIndex, chapterCount, percentLabel);
}
