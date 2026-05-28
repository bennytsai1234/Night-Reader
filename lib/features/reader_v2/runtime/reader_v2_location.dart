class ReaderV2Location {
  static const double minVisualOffsetPx = -80.0;
  static const double maxVisualOffsetPx = 120.0;

  const ReaderV2Location({
    required this.chapterIndex,
    required this.charOffset,
    this.visualOffsetPx = 0.0,
  });

  final int chapterIndex;
  final int charOffset;
  final double visualOffsetPx;

  static double normalizeVisualOffsetPx(double value) {
    if (!value.isFinite || value.isNaN) return 0.0;
    return value.clamp(minVisualOffsetPx, maxVisualOffsetPx).toDouble();
  }

  factory ReaderV2Location.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic value) {
      if (value is int) return value;
      if (value is double) return value.round();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    double asDouble(dynamic value) {
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    return ReaderV2Location(
      chapterIndex: asInt(json['chapterIndex']),
      charOffset: asInt(json['charOffset']),
      visualOffsetPx: asDouble(json['visualOffsetPx']),
    ).normalized();
  }

  ReaderV2Location normalized({int? chapterCount, int? chapterLength}) {
    final maxChapter =
        chapterCount == null || chapterCount <= 0 ? null : chapterCount - 1;
    final safeChapter =
        maxChapter == null
            ? (chapterIndex < 0 ? 0 : chapterIndex)
            : chapterIndex.clamp(0, maxChapter).toInt();
    final maxOffset =
        chapterLength == null || chapterLength < 0 ? null : chapterLength;
    final safeOffset =
        maxOffset == null
            ? (charOffset < 0 ? 0 : charOffset)
            : charOffset.clamp(0, maxOffset).toInt();
    return ReaderV2Location(
      chapterIndex: safeChapter,
      charOffset: safeOffset,
      visualOffsetPx: normalizeVisualOffsetPx(visualOffsetPx),
    );
  }

  ReaderV2Location copyWith({
    int? chapterIndex,
    int? charOffset,
    double? visualOffsetPx,
  }) {
    return ReaderV2Location(
      chapterIndex: chapterIndex ?? this.chapterIndex,
      charOffset: charOffset ?? this.charOffset,
      visualOffsetPx: visualOffsetPx ?? this.visualOffsetPx,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chapterIndex': chapterIndex,
      'charOffset': charOffset,
      'visualOffsetPx': visualOffsetPx,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is ReaderV2Location &&
        other.chapterIndex == chapterIndex &&
        other.charOffset == charOffset &&
        other.visualOffsetPx == visualOffsetPx;
  }

  @override
  int get hashCode => Object.hash(chapterIndex, charOffset, visualOffsetPx);

  @override
  String toString() {
    return 'ReaderV2Location(chapterIndex: $chapterIndex, charOffset: $charOffset, visualOffsetPx: $visualOffsetPx)';
  }
}
