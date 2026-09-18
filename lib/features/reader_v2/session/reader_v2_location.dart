import 'dart:math' as math;

class ReaderV2Location {
  static const double minVisualOffsetPx = -120.0;
  static const double maxVisualOffsetPx = 120.0;

  const ReaderV2Location({
    required this.chapterIndex,
    required this.charOffset,
    this.visualOffsetPx = 0.0,
    this.contentHash,
    this.contentLength,
    this.anchorBefore,
    this.anchorAfter,
  });

  final int chapterIndex;
  final int charOffset;
  final double visualOffsetPx;

  /// Identity of the exact `displayText` this offset was captured against.
  ///
  /// The legacy scalar fields remain the portable fallback, while the
  /// optional identity/context fields let a resume or source switch detect
  /// that the same integer offset is being interpreted against different
  /// content and remap it before restoring the viewport.
  final String? contentHash;
  final int? contentLength;
  final String? anchorBefore;
  final String? anchorAfter;

  bool get hasContentIdentity =>
      contentHash != null && contentHash!.isNotEmpty && contentLength != null;

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

    int? asNullableInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is double) return value.round();
      if (value is String) return int.tryParse(value);
      return null;
    }

    double asDouble(dynamic value) {
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    String? asNullableString(dynamic value) {
      if (value == null) return null;
      final text = value.toString();
      return text.isEmpty ? null : text;
    }

    return ReaderV2Location(
      chapterIndex: asInt(json['chapterIndex']),
      charOffset: asInt(json['charOffset']),
      visualOffsetPx: asDouble(json['visualOffsetPx']),
      contentHash: asNullableString(json['contentHash']),
      contentLength: asNullableInt(json['contentLength']),
      anchorBefore: asNullableString(json['anchorBefore']),
      anchorAfter: asNullableString(json['anchorAfter']),
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
      contentHash: contentHash,
      contentLength: contentLength,
      anchorBefore: anchorBefore,
      anchorAfter: anchorAfter,
    );
  }

  /// Binds this viewport coordinate to the exact displayed content that owns
  /// the coordinate. The viewport is the authoritative place to do this: it
  /// already knows which ChapterBlocks are actually painted, so persistence
  /// does not have to hope the repository LRU still contains the same version.
  ReaderV2Location withContentIdentity({
    required String contentHash,
    required String displayText,
    int contextRadius = 48,
  }) {
    final clampedOffset = charOffset.clamp(0, displayText.length).toInt();
    final safeOffset = _safeBoundaryAtOrBefore(displayText, clampedOffset);
    final radius = math.max(0, contextRadius);
    final beforeStart = _safeBoundaryAtOrAfter(
      displayText,
      math.max(0, safeOffset - radius),
    );
    final afterEnd = _safeBoundaryAtOrBefore(
      displayText,
      math.min(displayText.length, safeOffset + radius),
    );
    return copyWith(
      charOffset: safeOffset,
      contentHash: contentHash,
      contentLength: displayText.length,
      anchorBefore: displayText.substring(beforeStart, safeOffset),
      anchorAfter: displayText.substring(safeOffset, afterEnd),
    );
  }

  static int _safeBoundaryAtOrBefore(String text, int offset) {
    final safe = offset.clamp(0, text.length).toInt();
    if (safe <= 0 || safe >= text.length) return safe;
    final previous = text.codeUnitAt(safe - 1);
    final next = text.codeUnitAt(safe);
    return _isHighSurrogate(previous) && _isLowSurrogate(next)
        ? safe - 1
        : safe;
  }

  static int _safeBoundaryAtOrAfter(String text, int offset) {
    final safe = offset.clamp(0, text.length).toInt();
    if (safe <= 0 || safe >= text.length) return safe;
    final previous = text.codeUnitAt(safe - 1);
    final next = text.codeUnitAt(safe);
    return _isHighSurrogate(previous) && _isLowSurrogate(next)
        ? safe + 1
        : safe;
  }

  static bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;
  static bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;

  ReaderV2Location copyWith({
    int? chapterIndex,
    int? charOffset,
    double? visualOffsetPx,
    String? contentHash,
    int? contentLength,
    String? anchorBefore,
    String? anchorAfter,
    bool clearContentIdentity = false,
  }) {
    return ReaderV2Location(
      chapterIndex: chapterIndex ?? this.chapterIndex,
      charOffset: charOffset ?? this.charOffset,
      visualOffsetPx: visualOffsetPx ?? this.visualOffsetPx,
      contentHash: clearContentIdentity ? null : contentHash ?? this.contentHash,
      contentLength: clearContentIdentity
          ? null
          : contentLength ?? this.contentLength,
      anchorBefore: clearContentIdentity
          ? null
          : anchorBefore ?? this.anchorBefore,
      anchorAfter: clearContentIdentity ? null : anchorAfter ?? this.anchorAfter,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chapterIndex': chapterIndex,
      'charOffset': charOffset,
      'visualOffsetPx': visualOffsetPx,
      if (contentHash != null) 'contentHash': contentHash,
      if (contentLength != null) 'contentLength': contentLength,
      if (anchorBefore != null) 'anchorBefore': anchorBefore,
      if (anchorAfter != null) 'anchorAfter': anchorAfter,
    };
  }

  @override
  bool operator ==(Object other) {
    // Content identity is persistence/remapping metadata, not another viewport
    // coordinate. Runtime change detection must remain about the visible
    // position itself so enriching an anchor cannot trigger UI churn.
    return other is ReaderV2Location &&
        other.chapterIndex == chapterIndex &&
        other.charOffset == charOffset &&
        other.visualOffsetPx == visualOffsetPx;
  }

  @override
  int get hashCode => Object.hash(chapterIndex, charOffset, visualOffsetPx);

  @override
  String toString() {
    return 'ReaderV2Location(chapterIndex: $chapterIndex, charOffset: $charOffset, visualOffsetPx: $visualOffsetPx, contentHash: $contentHash)';
  }
}
