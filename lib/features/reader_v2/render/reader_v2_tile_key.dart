import 'package:night_reader/features/reader_v2/render/reader_v2_page_cache.dart';

class ReaderV2TileKey {
  const ReaderV2TileKey({
    required this.chapterIndex,
    required this.tileIndex,
    required this.startOffset,
    required this.endOffset,
    required this.layoutRevision,
  });

  final int chapterIndex;
  final int tileIndex;
  final int startOffset;
  final int endOffset;
  final int layoutRevision;

  factory ReaderV2TileKey.fromPageCache(
    ReaderV2PageCache page, {
    required int layoutRevision,
    int? tileIndex,
  }) {
    return ReaderV2TileKey(
      chapterIndex: page.chapterIndex,
      tileIndex: tileIndex ?? page.pageIndexInChapter,
      startOffset: page.startCharOffset,
      endOffset: page.endCharOffset,
      layoutRevision: layoutRevision,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReaderV2TileKey &&
        other.chapterIndex == chapterIndex &&
        other.tileIndex == tileIndex &&
        other.startOffset == startOffset &&
        other.endOffset == endOffset &&
        other.layoutRevision == layoutRevision;
  }

  @override
  int get hashCode => Object.hash(
    chapterIndex,
    tileIndex,
    startOffset,
    endOffset,
    layoutRevision,
  );

  @override
  String toString() {
    return 'ReaderV2TileKey(c$chapterIndex t$tileIndex $startOffset-$endOffset r$layoutRevision)';
  }
}
