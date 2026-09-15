import 'dart:math' as math;
import 'dart:typed_data';

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

import 'reader_correctness_foundation.dart';

/// The only visual-observation feature flag exposed by the correctness
/// harness.  It is intentionally a test seam, not a product setting.
enum ReaderVisualInjection {
  none,
  blankNextFrame,
  visualScrollWhileIdle,
  crossOracleMismatch,
}

/// A compact grayscale image used by the visual oracle.
///
/// The source image is reduced horizontally, but its vertical resolution is
/// retained.  Keeping the rows is important: the C1 identity band is a
/// sequence of 19 line slots and vertical displacement is measured from the
/// same row vector.  The original RGBA image is kept separately and only for
/// a bounded failure bundle.
final class ReaderVisualRaster {
  ReaderVisualRaster({
    required this.width,
    required this.height,
    required Uint8List pixels,
  }) : pixels = Uint8List.fromList(pixels),
       assert(width > 0),
       assert(height > 0),
       assert(pixels.length == width * height);

  final int width;
  final int height;
  final Uint8List pixels;

  factory ReaderVisualRaster.fromRgba({
    required int sourceWidth,
    required int sourceHeight,
    required Uint8List rgba,
    int analysisWidth = readerVisualDefaultAnalysisWidth,
  }) {
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      throw ArgumentError('RGBA source dimensions must be positive');
    }
    final expectedBytes = sourceWidth * sourceHeight * 4;
    if (rgba.length < expectedBytes) {
      throw ArgumentError.value(
        rgba.length,
        'rgba.length',
        'must contain at least $expectedBytes bytes',
      );
    }
    final width = math.max(1, math.min(sourceWidth, analysisWidth));
    final pixels = Uint8List(width * sourceHeight);
    for (var y = 0; y < sourceHeight; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final startX = (x * sourceWidth ~/ width);
        final endX = math.max(startX + 1, ((x + 1) * sourceWidth ~/ width));
        var total = 0.0;
        var count = 0;
        for (var sourceX = startX; sourceX < endX; sourceX += 1) {
          final offset = (y * sourceWidth + sourceX) * 4;
          final alpha = rgba[offset + 3] / 255.0;
          final luminance =
              rgba[offset] * 0.2126 +
              rgba[offset + 1] * 0.7152 +
              rgba[offset + 2] * 0.0722;
          // `toImage` normally returns opaque pixels, but treating a
          // transparent pixel as white keeps the metric meaningful for a
          // boundary with an alpha background.
          total += luminance * alpha + 255.0 * (1.0 - alpha);
          count += 1;
        }
        pixels[y * width + x] = (total / count).round().clamp(0, 255);
      }
    }
    return ReaderVisualRaster(
      width: width,
      height: sourceHeight,
      pixels: pixels,
    );
  }

  factory ReaderVisualRaster.synthetic({
    required int width,
    required int height,
    required int Function(int x, int y) pixel,
  }) {
    final pixels = Uint8List(width * height);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        pixels[y * width + x] = pixel(x, y).clamp(0, 255);
      }
    }
    return ReaderVisualRaster(width: width, height: height, pixels: pixels);
  }

  int pixelAt(int x, int y) => pixels[y * width + x];

  List<int> inkProfile({int? xStart, int? xEnd}) {
    final first = (xStart ?? 0).clamp(0, width).toInt();
    final last = (xEnd ?? width).clamp(first, width).toInt();
    final result = List<int>.filled(height, 0);
    for (var y = 0; y < height; y += 1) {
      var count = 0;
      for (var x = first; x < last; x += 1) {
        if (pixelAt(x, y) < readerVisualInkThreshold) count += 1;
      }
      result[y] = count;
    }
    return result;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'width': width,
    'height': height,
    'bytes': pixels.length,
  };
}

/// Original pixels kept for a failure bundle.  The oracle never stores more
/// than the three frames around one candidate, and normal frames are kept
/// only as the two-frame before-window needed to complete that bundle.
final class ReaderVisualRawFrame {
  ReaderVisualRawFrame({
    required this.sequence,
    required this.timestampMicros,
    required this.width,
    required this.height,
    required Uint8List rgba,
  }) : rgba = Uint8List.fromList(rgba);

  final int sequence;
  final int timestampMicros;
  final int width;
  final int height;
  final Uint8List rgba;

  Map<String, Object?> toJson({String? label}) => <String, Object?>{
    'label': label,
    'sequence': sequence,
    'timestampMicros': timestampMicros,
    'width': width,
    'height': height,
    'rgbaBytes': rgba.length,
  };
}

/// A profile found by reading the actual pixels of a C1 identity band.
final class ReaderVisualDecodedProfile {
  const ReaderVisualDecodedProfile({
    required this.key,
    required this.top,
    required this.bottom,
    required this.confidence,
    required this.complete,
  });

  final BlockKey key;
  final int top;
  final int bottom;
  final double confidence;
  final bool complete;

  Map<String, Object?> toJson() => <String, Object?>{
    'key': <String, int>{
      'chapterIndex': key.chapterIndex,
      'blockIndex': key.blockIndex,
    },
    'top': top,
    'bottom': bottom,
    'confidence': confidence,
    'complete': complete,
  };
}

/// A runtime snapshot reduced to the fields that S5 is allowed to consume.
/// The visual rules themselves do not receive this object; it is used only by
/// [ReaderVisualOracle._observeCrossOracle].
final class ReaderVisualRuntimeRecord {
  const ReaderVisualRuntimeRecord({
    required this.timestampMicros,
    required this.visibleKeys,
    required this.scrollPixels,
    required this.dominantVisibleChapter,
    required this.displayedProgressChapter,
    required this.phase,
    required this.scrollActivity,
    required this.isScrolling,
    required this.viewportHeight,
  });

  final int timestampMicros;
  final List<BlockKey> visibleKeys;
  final double? scrollPixels;
  final int? dominantVisibleChapter;
  final int? displayedProgressChapter;
  final String phase;
  final String scrollActivity;
  final bool isScrolling;
  final double viewportHeight;

  bool get claimsScrolling =>
      isScrolling ||
      scrollActivity == 'drag' ||
      scrollActivity == 'ballistic' ||
      scrollActivity == 'driven';

  Map<String, Object?> toJson() => <String, Object?>{
    'timestampMicros': timestampMicros,
    'visibleKeys': [
      for (final key in visibleKeys)
        <String, int>{
          'chapterIndex': key.chapterIndex,
          'blockIndex': key.blockIndex,
        },
    ],
    'scrollPixels': scrollPixels,
    'dominantVisibleChapter': dominantVisibleChapter,
    'displayedProgressChapter': displayedProgressChapter,
    'phase': phase,
    'scrollActivity': scrollActivity,
    'isScrolling': isScrolling,
    'viewportHeight': viewportHeight,
  };
}

const int readerVisualDefaultAnalysisWidth = 160;
const int readerVisualInkThreshold = 245;
const int readerVisualMaxFrames = 240;
const int readerVisualMaxViolations = 256;

final class ReaderVisualFrame {
  const ReaderVisualFrame({
    required this.sequence,
    required this.timestampMicros,
    required this.width,
    required this.height,
    required this.contentCoverage,
    required this.meanBrightness,
    required this.edgeDensity,
    required this.diffFromPrevious,
    required this.rowInkProfile,
    required this.visualDy,
    required this.visualCorrelation,
    required this.decodedProfiles,
    this.expectedChapter,
    this.opaquePixelRatio,
  });

  const ReaderVisualFrame.synthetic({
    int sequence = 0,
    int timestampMicros = 0,
    int width = 160,
    int height = 100,
    double contentCoverage = 0.1,
    double meanBrightness = 0.9,
    double edgeDensity = 0.1,
    double diffFromPrevious = 0.0,
    List<int> rowInkProfile = const <int>[1, 2, 1, 2],
    double? visualDy,
    double visualCorrelation = 1.0,
    List<ReaderVisualDecodedProfile> decodedProfiles =
        const <ReaderVisualDecodedProfile>[],
    int? expectedChapter,
    double? opaquePixelRatio,
  }) : this(
         sequence: sequence,
         timestampMicros: timestampMicros,
         width: width,
         height: height,
         contentCoverage: contentCoverage,
         meanBrightness: meanBrightness,
         edgeDensity: edgeDensity,
         diffFromPrevious: diffFromPrevious,
         rowInkProfile: rowInkProfile,
         visualDy: visualDy,
         visualCorrelation: visualCorrelation,
         decodedProfiles: decodedProfiles,
         expectedChapter: expectedChapter,
         opaquePixelRatio: opaquePixelRatio,
       );

  final int sequence;
  final int timestampMicros;
  final int width;
  final int height;
  final double contentCoverage;
  final double meanBrightness;
  final double edgeDensity;
  final double diffFromPrevious;
  final List<int> rowInkProfile;

  /// Positive means the visual content moved down; negative means it moved up.
  final double? visualDy;
  final double visualCorrelation;
  final List<ReaderVisualDecodedProfile> decodedProfiles;

  /// An external case expectation, never populated from Reader runtime.  It
  /// is used by host analyzer tests to prove V16's "target missing" rule.
  final int? expectedChapter;

  /// Fraction of source pixels whose alpha channel is fully opaque. A
  /// debug-only RepaintBoundary around a transparent content stack normally
  /// has a near-zero value; an opaque blank frame has a value near one. This
  /// independent alpha signal keeps a sparse short chapter distinct from a
  /// real blank transition.
  final double? opaquePixelRatio;

  factory ReaderVisualFrame.fromRaster({
    required int sequence,
    required int timestampMicros,
    required ReaderVisualRaster raster,
    ReaderVisualRaster? previousRaster,
    int profileBlockIndexOffset = 1,
    int? expectedChapter,
    double? opaquePixelRatio,
  }) {
    final rowInkProfile = raster.inkProfile();
    final previousProfile = previousRaster?.inkProfile();
    final displacement = previousProfile == null
        ? const ReaderVisualDisplacement.none()
        : estimateReaderVisualDisplacement(previousProfile, rowInkProfile);
    final sum = rowInkProfile.fold<int>(0, (total, value) => total + value);
    final pixelCount = raster.width * raster.height;
    var edgeCount = 0;
    var edgeSamples = 0;
    for (var y = 0; y < raster.height; y += 1) {
      for (var x = 0; x < raster.width; x += 1) {
        final pixel = raster.pixelAt(x, y);
        if (x + 1 < raster.width) {
          edgeSamples += 1;
          if ((pixel - raster.pixelAt(x + 1, y)).abs() >= 12) edgeCount += 1;
        }
        if (y + 1 < raster.height) {
          edgeSamples += 1;
          if ((pixel - raster.pixelAt(x, y + 1)).abs() >= 12) edgeCount += 1;
        }
      }
    }
    final brightness = raster.pixels.fold<int>(
      0,
      (total, value) => total + value,
    );
    final previousPixels = previousRaster;
    var diff = 0.0;
    if (previousPixels != null &&
        previousPixels.width == raster.width &&
        previousPixels.height == raster.height) {
      var totalDifference = 0;
      for (var i = 0; i < raster.pixels.length; i += 1) {
        totalDifference += (raster.pixels[i] - previousPixels.pixels[i]).abs();
      }
      diff = totalDifference / (255.0 * raster.pixels.length);
    }
    final decoded = decodeReaderVisualProfiles(
      raster,
      blockIndexOffset: profileBlockIndexOffset,
    );
    return ReaderVisualFrame(
      sequence: sequence,
      timestampMicros: timestampMicros,
      width: raster.width,
      height: raster.height,
      contentCoverage: pixelCount == 0 ? 0 : sum / pixelCount,
      meanBrightness: pixelCount == 0 ? 1 : brightness / (255.0 * pixelCount),
      edgeDensity: edgeSamples == 0 ? 0 : edgeCount / edgeSamples,
      diffFromPrevious: diff,
      rowInkProfile: List<int>.unmodifiable(rowInkProfile),
      visualDy: displacement.dy?.toDouble(),
      visualCorrelation: displacement.correlation,
      decodedProfiles: List<ReaderVisualDecodedProfile>.unmodifiable(decoded),
      expectedChapter: expectedChapter,
      opaquePixelRatio: opaquePixelRatio,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'sequence': sequence,
    'timestampMicros': timestampMicros,
    'width': width,
    'height': height,
    'contentCoverage': contentCoverage,
    'meanBrightness': meanBrightness,
    'edgeDensity': edgeDensity,
    'diffFromPrevious': diffFromPrevious,
    'rowInkProfile': rowInkProfile,
    'visualDy': visualDy,
    'visualCorrelation': visualCorrelation,
    'opaquePixelRatio': opaquePixelRatio,
    'decodedProfiles': [
      for (final profile in decodedProfiles) profile.toJson(),
    ],
    'expectedChapter': expectedChapter,
  };
}

final class ReaderVisualDisplacement {
  const ReaderVisualDisplacement({required this.dy, required this.correlation});

  const ReaderVisualDisplacement.none() : this(dy: null, correlation: 0);

  final int? dy;
  final double correlation;

  Map<String, Object?> toJson() => <String, Object?>{
    'dy': dy,
    'correlation': correlation,
  };
}

/// One-dimensional normalized cross-correlation over row ink profiles.
/// `dy > 0` means the second image's content moved down relative to the first.
ReaderVisualDisplacement estimateReaderVisualDisplacement(
  List<int> previous,
  List<int> current, {
  int? maxShift,
}) {
  if (previous.length < 8 || current.length < 8) {
    return const ReaderVisualDisplacement.none();
  }
  final limit = math.min(
    maxShift ?? math.max(8, math.min(previous.length, current.length) ~/ 3),
    math.min(previous.length, current.length) - 1,
  );
  var bestCorrelation = -1.0;
  var bestShift = 0;
  var bestOverlap = 0;
  for (var shift = -limit; shift <= limit; shift += 1) {
    final previousStart = shift < 0 ? -shift : 0;
    final currentStart = shift > 0 ? shift : 0;
    final overlap = math.min(
      previous.length - previousStart,
      current.length - currentStart,
    );
    if (overlap < 8) continue;
    var previousMean = 0.0;
    var currentMean = 0.0;
    for (var i = 0; i < overlap; i += 1) {
      previousMean += previous[previousStart + i];
      currentMean += current[currentStart + i];
    }
    previousMean /= overlap;
    currentMean /= overlap;
    var numerator = 0.0;
    var previousVariance = 0.0;
    var currentVariance = 0.0;
    for (var i = 0; i < overlap; i += 1) {
      final left = previous[previousStart + i] - previousMean;
      final right = current[currentStart + i] - currentMean;
      numerator += left * right;
      previousVariance += left * left;
      currentVariance += right * right;
    }
    if (previousVariance == 0 || currentVariance == 0) continue;
    final correlation =
        numerator / math.sqrt(previousVariance * currentVariance);
    final better = correlation > bestCorrelation + 1e-9;
    final tie =
        (correlation - bestCorrelation).abs() <= 1e-9 &&
        shift.abs() < bestShift.abs();
    if (better || tie) {
      bestCorrelation = correlation;
      bestShift = shift;
      bestOverlap = overlap;
    }
  }
  if (bestOverlap < 8 || bestCorrelation < 0.65) {
    return ReaderVisualDisplacement(
      dy: null,
      correlation: math.max(0, bestCorrelation),
    );
  }
  return ReaderVisualDisplacement(dy: bestShift, correlation: bestCorrelation);
}

/// Decode all identity bands that are fully visible in a raster.
///
/// The scanner deliberately uses only the left ink occupancy of the actual
/// image.  It does not read text, block metadata, scroll state, or a runtime
/// snapshot.  The profile's 1010 sentinel makes false positives from ordinary
/// prose unlikely; a candidate is accepted only when at most one of its 19
/// slots disagrees with the encoded sentinel/payload parity.
List<ReaderVisualDecodedProfile> decodeReaderVisualProfiles(
  ReaderVisualRaster raster, {
  int blockIndexOffset = 1,
}) {
  if (raster.height < 19 * 20) return const <ReaderVisualDecodedProfile>[];
  // C1 profile rows are normalized into their own short paragraphs, so every
  // row starts at the left content edge.  Limiting this scan to the first
  // 80px prevents ordinary prose farther across the viewport from combining
  // into a false 1010/parity sequence while still covering the marker glyph.
  final leftInk = raster.inkProfile(xEnd: math.min(80, raster.width));
  final prefix = List<int>.filled(raster.height + 1, 0);
  for (var y = 0; y < raster.height; y += 1) {
    prefix[y + 1] = prefix[y] + leftInk[y];
  }
  int slotInk(int start, int end) {
    final safeStart = start.clamp(0, raster.height).toInt();
    final safeEnd = end.clamp(safeStart, raster.height).toInt();
    return prefix[safeEnd] - prefix[safeStart];
  }

  final leftLimit = math.min(80, raster.width);
  ({int left, int right, int count}) slotSpan(int start, int end) {
    final safeStart = start.clamp(0, raster.height).toInt();
    final safeEnd = end.clamp(safeStart, raster.height).toInt();
    var left = raster.width;
    var right = -1;
    var count = 0;
    for (var y = safeStart; y < safeEnd; y += 1) {
      for (var x = 0; x < leftLimit; x += 1) {
        if (raster.pixelAt(x, y) >= readerVisualInkThreshold) continue;
        left = math.min(left, x);
        right = math.max(right, x);
        count += 1;
      }
    }
    return (left: left, right: right, count: count);
  }

  final candidates = <ReaderVisualDecodedProfile>[];
  // In the real Reader each profile bit is normalized as a short paragraph,
  // so paragraph spacing is added to the typographic line height.  The C1
  // isolated-band helper uses 28px boxes, while the mounted Reader measured
  // roughly 38px between profile rows, while a paragraph boundary can add
  // another line-height-sized gap. Only the measured layout families are
  // admitted here (28px for the isolated C1 raster and 38/39px for the
  // mounted Reader); scanning every integer in a broad range creates
  // geometrically plausible but false identities from ordinary prose.
  const spacings = <int>[28, 38, 39];
  for (final spacing in spacings) {
    final bandHeight = spacing * 19;
    for (var start = 0; start + bandHeight <= raster.height; start += 1) {
      final widths = [
        for (var bit = 0; bit < 19; bit += 1)
          slotInk(start + bit * spacing, start + (bit + 1) * spacing),
      ];
      final bits = widths.map((value) => value >= 2).toList(growable: false);
      if (bits[0] != true ||
          bits[1] != false ||
          bits[2] != true ||
          bits[3] != false) {
        continue;
      }
      final spans = [
        for (var bit = 0; bit < bits.length; bit += 1)
          if (bits[bit])
            slotSpan(start + bit * spacing, start + (bit + 1) * spacing),
      ];
      // Every profile row is a single marker glyph at the same x-origin. A
      // normal prose line may accidentally satisfy 1010, but it will not
      // have this compact, stable horizontal shape across all ink slots.
      if (spans.isEmpty ||
          spans.any(
            (span) =>
                span.left > 8 ||
                span.right < span.left ||
                span.right - span.left + 1 > 40,
          )) {
        continue;
      }
      final minLeft = spans.map((span) => span.left).reduce(math.min);
      final maxLeft = spans.map((span) => span.left).reduce(math.max);
      final minWidth = spans
          .map((span) => span.right - span.left + 1)
          .reduce(math.min);
      final maxWidth = spans
          .map((span) => span.right - span.left + 1)
          .reduce(math.max);
      if (maxLeft - minLeft > 8 || maxWidth - minWidth > 12) continue;
      var mismatch = 0;
      final expectedPrefix = <bool>[true, false, true, false];
      for (var bit = 0; bit < expectedPrefix.length; bit += 1) {
        if (bits[bit] != expectedPrefix[bit]) mismatch += 1;
      }
      // The payload is not known until parity is decoded.  Require a valid
      // decoder result rather than trying to infer an identity from geometry.
      ({int chapterIndex, int paragraphIndex}) decoded;
      try {
        decoded = decodeReaderInkProfile(widths);
      } on FormatException {
        continue;
      }
      if (mismatch > 0) continue;
      final profile = ReaderVisualDecodedProfile(
        key: BlockKey(
          chapterIndex: decoded.chapterIndex,
          blockIndex: decoded.paragraphIndex + blockIndexOffset,
        ),
        top: start,
        bottom: start + bandHeight,
        confidence: 1.0,
        complete: start > 0 && start + bandHeight < raster.height,
      );
      candidates.add(profile);
    }
  }
  if (candidates.isEmpty) return const <ReaderVisualDecodedProfile>[];
  // The same band is usually found at neighbouring spacing/start pairs. Keep
  // one strongest candidate per identity and location, but deliberately keep
  // two copies of the same identity when their vertical locations differ;
  // that is the evidence needed for V4.
  final bestByKey = <BlockKey, List<ReaderVisualDecodedProfile>>{};
  for (final candidate in candidates) {
    final existing = bestByKey.putIfAbsent(
      candidate.key,
      () => <ReaderVisualDecodedProfile>[],
    );
    final nearbyIndex = existing.indexWhere(
      (item) => (item.top - candidate.top).abs() <= 80,
    );
    if (nearbyIndex < 0) {
      existing.add(candidate);
    } else if (candidate.confidence > existing[nearbyIndex].confidence) {
      existing[nearbyIndex] = candidate;
    }
  }
  final result = bestByKey.values.expand((items) => items).toList()
    ..sort((a, b) => a.top.compareTo(b.top));
  return result;
}

final class ReaderVisualViolation {
  const ReaderVisualViolation({
    required this.invariant,
    required this.reason,
    required this.sequence,
    required this.timestampMicros,
    this.priority = 'normal',
    this.evidence = const <String, Object?>{},
    this.retainedRawFrames = const <ReaderVisualRawFrame>[],
  });

  final String invariant;
  final String reason;
  final int sequence;
  final int timestampMicros;
  final String priority;
  final Map<String, Object?> evidence;
  final List<ReaderVisualRawFrame> retainedRawFrames;

  Map<String, Object?> toJson() => <String, Object?>{
    'invariant': invariant,
    'oracle': 'visual',
    'priority': priority,
    'reason': reason,
    'sequence': sequence,
    'timestampMicros': timestampMicros,
    'evidence': evidence,
    'retainedRawFrames': [
      for (var i = 0; i < retainedRawFrames.length; i += 1)
        retainedRawFrames[i].toJson(
          label: switch (i) {
            0 => 'before',
            1 => 'middle',
            _ => 'after',
          },
        ),
    ],
  };
}

final class _ReaderVisualPair {
  const _ReaderVisualPair(this.frame, this.runtime);

  final ReaderVisualFrame frame;
  final ReaderVisualRuntimeRecord? runtime;
}

final class _PendingBlankCandidate {
  const _PendingBlankCandidate({
    required this.frame,
    required this.before,
    required this.middle,
  });

  final ReaderVisualFrame frame;
  final ReaderVisualRawFrame? before;
  final ReaderVisualRawFrame? middle;
}

/// Bounded visual oracle.  Rules V1–V17 use only pixels and decoded profiles;
/// V18–V20 and CROSS_ORACLE_MISMATCH are evaluated in the explicit S5 method,
/// where the runtime record is paired by timestamp and nowhere else.
final class ReaderVisualOracle {
  ReaderVisualOracle({
    this.maxFrames = readerVisualMaxFrames,
    this.maxViolations = readerVisualMaxViolations,
  }) : assert(maxFrames > 0),
       assert(maxViolations > 0);

  final int maxFrames;
  final int maxViolations;
  final List<_ReaderVisualPair> _pairs = <_ReaderVisualPair>[];
  final List<ReaderVisualViolation> _violations = <ReaderVisualViolation>[];
  final Set<String> _reported = <String>{};
  final List<ReaderVisualRawFrame> _rawRecent = <ReaderVisualRawFrame>[];
  _PendingBlankCandidate? _pendingBlank;
  List<ReaderVisualRawFrame> _lastRetainedRawFrames =
      const <ReaderVisualRawFrame>[];

  List<ReaderVisualFrame> get frames => [for (final pair in _pairs) pair.frame];

  List<ReaderVisualViolation> get violations => [..._violations];

  List<ReaderVisualRawFrame> get lastRetainedRawFrames => [
    ..._lastRetainedRawFrames,
  ];

  /// Compare decoded profile identities with the paired runtime record.  A
  /// profile is allowed to match either the current or immediately previous
  /// runtime visible-key set; that is the explicit one-frame phase tolerance
  /// used by S5.  This method is reporting only and is not used by V1–V17.
  Map<String, Object?> profileMatchStats() {
    var decodedProfiles = 0;
    var matchingProfiles = 0;
    var framesWithDecodedProfiles = 0;
    for (var index = 0; index < _pairs.length; index += 1) {
      final pair = _pairs[index];
      final profiles = pair.frame.decodedProfiles;
      if (profiles.isEmpty) continue;
      framesWithDecodedProfiles += 1;
      final currentKeys = pair.runtime?.visibleKeys.toSet() ?? <BlockKey>{};
      final previousPair =
          index == 0 ||
              pair.frame.sequence != _pairs[index - 1].frame.sequence + 1
          ? null
          : _pairs[index - 1];
      final previousKeys =
          previousPair?.runtime?.visibleKeys.toSet() ?? <BlockKey>{};
      for (final profile in profiles) {
        decodedProfiles += 1;
        if (currentKeys.contains(profile.key) ||
            previousKeys.contains(profile.key)) {
          matchingProfiles += 1;
        }
      }
    }
    return <String, Object?>{
      'framesWithDecodedProfiles': framesWithDecodedProfiles,
      'decodedProfiles': decodedProfiles,
      'matchingProfiles': matchingProfiles,
      'matchRate': decodedProfiles == 0
          ? 0.0
          : matchingProfiles / decodedProfiles,
    };
  }

  List<ReaderVisualViolation> observe(
    ReaderVisualFrame frame, {
    ReaderVisualRuntimeRecord? runtime,
    ReaderVisualRawFrame? rawFrame,
  }) {
    final newViolations = <ReaderVisualViolation>[];
    if (rawFrame != null) {
      _rawRecent.add(rawFrame);
      while (_rawRecent.length > 2) {
        _rawRecent.removeAt(0);
      }
    }

    final pending = _pendingBlank;
    if (pending != null && frame.sequence > pending.frame.sequence) {
      final retained = <ReaderVisualRawFrame>[
        if (pending.before != null) pending.before!,
        if (pending.middle != null) pending.middle!,
        if (rawFrame != null) rawFrame,
      ];
      _lastRetainedRawFrames = List<ReaderVisualRawFrame>.unmodifiable(
        retained,
      );
      newViolations.add(
        _emit(
          'V1',
          'white/blank candidate did not become acceptable merely because the next frame recovered',
          pending.frame,
          evidence: <String, Object?>{
            'candidateType': 'white_or_blank',
            'recoveredOnNextFrame': true,
            'beforeMiddleAfter': retained.length,
          },
          retainedRawFrames: retained,
        ),
      );
      _pendingBlank = null;
    }

    _pairs.add(_ReaderVisualPair(frame, runtime));
    while (_pairs.length > maxFrames) {
      _pairs.removeAt(0);
    }
    newViolations.addAll(_observePixelRules(frame));
    newViolations.addAll(_observeCrossOracle(frame, runtime));
    return newViolations;
  }

  List<ReaderVisualViolation> finish() {
    final pending = _pendingBlank;
    if (pending == null) return const <ReaderVisualViolation>[];
    _pendingBlank = null;
    final retained = <ReaderVisualRawFrame>[
      if (pending.before != null) pending.before!,
      if (pending.middle != null) pending.middle!,
    ];
    _lastRetainedRawFrames = List<ReaderVisualRawFrame>.unmodifiable(retained);
    return [
      _emit(
        'V1',
        'white/blank candidate remained unresolved at case end',
        pending.frame,
        evidence: <String, Object?>{
          'candidateType': 'white_or_blank',
          'recoveredOnNextFrame': false,
          'beforeMiddleAfter': retained.length,
        },
        retainedRawFrames: retained,
      ),
    ];
  }

  void reset() {
    _pairs.clear();
    _violations.clear();
    _reported.clear();
    _rawRecent.clear();
    _pendingBlank = null;
    _lastRetainedRawFrames = const <ReaderVisualRawFrame>[];
  }

  List<ReaderVisualViolation> _observePixelRules(ReaderVisualFrame frame) {
    final result = <ReaderVisualViolation>[];
    // A capture gap is an observation boundary for displacement and temporal
    // pixel rules. They must not treat the last captured frame before that
    // gap as the immediate predecessor of this frame.
    final previous = _previousContiguousPair()?.frame;
    // Blank/black/disappearing-raster candidates are different from movement
    // inference: the current raster is direct evidence of the candidate, and
    // the most recent retained raster is enough to establish that content was
    // present before it. A dropped display sample between the two does not
    // make the current blank image safe. Keep this fallback scoped to these
    // point-in-time transition rules; V11/V12/V17 and cross-source motion
    // checks continue to require contiguous capture pairs.
    final previousPixelFrame = _pairs.length >= 2
        ? _pairs[_pairs.length - 2].frame
        : null;

    // A RepaintBoundary can retain a one-pixel compositor edge after the
    // content child is replaced by a solid background.  At the required
    // 160px analysis width that is 1/160 == 0.00625 coverage; brightness is
    // the independent guard that keeps a sparse real text frame distinct.
    final isWhite =
        frame.contentCoverage <= 0.007 && frame.meanBrightness >= 0.995;
    final isBlack =
        frame.contentCoverage <= 0.001 && frame.meanBrightness <= 0.02;
    // A short chapter can legitimately occupy well under 0.5% of this
    // viewport.  Keep the predecessor threshold below that sparse-content
    // range; the separate 75% drop requirement below is what distinguishes a
    // blank transition from ordinary short-chapter scrolling.
    final hadContent =
        previousPixelFrame != null &&
        previousPixelFrame.contentCoverage > 0.001;
    final isMeaningfulBlankTransition =
        previousPixelFrame != null &&
        isWhite &&
        (frame.contentCoverage <= previousPixelFrame.contentCoverage * 0.25 ||
            (frame.opaquePixelRatio ?? 0) >= 0.99);
    if (hadContent && isMeaningfulBlankTransition) {
      // Delay V1 until one following frame is available so the retained
      // before/middle/after contract is observable.  Recovery is never a pass.
      _pendingBlank = _PendingBlankCandidate(
        frame: frame,
        before: _rawRecent.length >= 2
            ? _rawRecent[_rawRecent.length - 2]
            : null,
        middle: _rawRecent.isNotEmpty ? _rawRecent.last : null,
      );
    } else if (hadContent && isBlack) {
      result.add(
        _emit(
          'V2',
          'content raster became a black frame after a non-empty frame',
          frame,
          evidence: <String, Object?>{
            'previousContentCoverage': previousPixelFrame.contentCoverage,
            'currentMeanBrightness': frame.meanBrightness,
            'captureGapBeforeCandidate': previous == null,
          },
        ),
      );
    } else if (hadContent &&
        frame.contentCoverage < previousPixelFrame.contentCoverage * 0.25 &&
        frame.meanBrightness > 0.02 &&
        frame.meanBrightness < 0.985) {
      result.add(
        _emit(
          'V3',
          'content coverage disappeared without being a white or black frame',
          frame,
          evidence: <String, Object?>{
            'previousContentCoverage': previousPixelFrame.contentCoverage,
            'currentContentCoverage': frame.contentCoverage,
            'captureGapBeforeCandidate': previous == null,
          },
        ),
      );
    }

    final profiles = frame.decodedProfiles;
    final keys = profiles.map((profile) => profile.key).toList(growable: false);
    if (keys.length != keys.toSet().length) {
      result.add(
        _emit('V4', 'the same decoded paragraph identity appears twice', frame),
      );
    }
    for (var i = 1; i < profiles.length; i += 1) {
      final before = profiles[i - 1];
      final current = profiles[i];
      if (current.top < before.bottom) {
        result.add(
          _emit(
            'V5',
            'decoded paragraph bands overlap in the pixel geometry',
            frame,
            evidence: <String, Object?>{
              'previous': before.toJson(),
              'current': current.toJson(),
            },
          ),
        );
        break;
      }
      if (current.key.compareTo(before.key) < 0) {
        result.add(
          _emit(
            'V6',
            'decoded paragraph order moves backwards in the same raster',
            frame,
          ),
        );
        break;
      }
      final gap = current.top - before.bottom;
      if (gap > math.max(120, frame.height ~/ 4)) {
        result.add(
          _emit(
            'V7',
            'decoded paragraph bands contain an abnormal vertical gap',
            frame,
            evidence: <String, Object?>{'gap': gap},
          ),
        );
        break;
      }
    }
    if (profiles.any((profile) => !profile.complete)) {
      result.add(
        _emit(
          'V8',
          'an identity band is clipped at the visual viewport boundary',
          frame,
        ),
      );
    }

    final dy = frame.visualDy;
    if (dy != null && frame.visualCorrelation >= 0.65) {
      if (dy.abs() > frame.height * 0.75) {
        result.add(
          _emit(
            'V9',
            'visual displacement teleported by more than 75% of the viewport',
            frame,
            evidence: <String, Object?>{
              'dy': dy,
              'viewportHeight': frame.height,
              'correlation': frame.visualCorrelation,
            },
          ),
        );
      }
    }

    final recentDy = _recentDisplacements(8);
    final nonZeroDy = recentDy.where((value) => value.abs() > 0.5).toList();
    if (nonZeroDy.length >= 4) {
      var reversals = 0;
      for (var i = 1; i < nonZeroDy.length; i += 1) {
        if (nonZeroDy[i].sign != nonZeroDy[i - 1].sign) reversals += 1;
      }
      final path = nonZeroDy.fold<double>(
        0,
        (total, value) => total + value.abs(),
      );
      final net = nonZeroDy.fold<double>(0, (total, value) => total + value);
      if (reversals >= 1 &&
          nonZeroDy.any((value) => value.abs() >= frame.height * 0.15)) {
        result.add(
          _emit(
            'V10',
            'visual movement reversed after a large one-way excursion',
            frame,
            evidence: <String, Object?>{
              'dy': nonZeroDy,
              'reversals': reversals,
              'net': net,
              'path': path,
            },
          ),
        );
      }
      final small = nonZeroDy.every(
        (value) => value.abs() <= frame.height * 0.08,
      );
      if (reversals >= 3 && small && net.abs() <= path * 0.25) {
        result.add(
          _emit(
            'V17',
            'visual anchor oscillates around a nearly unchanged position',
            frame,
            evidence: <String, Object?>{
              'dy': nonZeroDy,
              'reversals': reversals,
              'net': net,
              'path': path,
            },
          ),
        );
      }
    }

    if (recentDy.length >= 8) {
      final tail = recentDy.sublist(recentDy.length - 8);
      final tailFrames = _contiguousSuffix(8);
      final sameDirection = tail.every(
        (value) => value.abs() > 0.5 && value.sign == tail.first.sign,
      );
      final slow = tail.every((value) => value.abs() <= frame.height * 0.025);
      final quiet = tailFrames.every(
        (pair) => pair.frame.diffFromPrevious < 0.02,
      );
      final total = tail.fold<double>(0, (sum, value) => sum + value.abs());
      if (sameDirection && slow && quiet && total > frame.height * 0.05) {
        result.add(
          _emit(
            'V11',
            'visual content keeps drifting in one direction across a quiet window',
            frame,
            evidence: <String, Object?>{'dy': tail, 'total': total},
          ),
        );
      }
    }

    final contiguousSix = _contiguousSuffix(6);
    if (contiguousSix.length >= 6) {
      final tail = [for (final pair in contiguousSix) pair.frame.visualDy ?? 0];
      final settled = tail.take(3).every((value) => value.abs() <= 0.5);
      final creep = tail
          .skip(3)
          .every(
            (value) => value.abs() > 0.5 && value.abs() <= frame.height * 0.08,
          );
      final direction = tail[3].sign;
      if (settled &&
          creep &&
          tail.skip(3).every((value) => value.sign == direction)) {
        result.add(
          _emit(
            'V12',
            'visual content creeps after a settled run',
            frame,
            evidence: <String, Object?>{'dy': tail},
          ),
        );
      }
    }

    final contiguousThree = _contiguousSuffix(3);
    if (contiguousThree.length >= 3) {
      final chapterSequence = [
        for (final pair in contiguousThree) _dominantDecodedChapter(pair.frame),
      ];
      if (chapterSequence[0] != null &&
          chapterSequence[0] == chapterSequence[2] &&
          chapterSequence[1] != null &&
          chapterSequence[1] != chapterSequence[0]) {
        result.add(
          _emit(
            'V13',
            'decoded chapter briefly excursions to a different chapter and returns',
            frame,
            evidence: <String, Object?>{'chapters': chapterSequence},
          ),
        );
      }
      final keySequence = [
        for (final pair in contiguousThree) _dominantDecodedKey(pair.frame),
      ];
      if (keySequence[0] != null &&
          keySequence[0] == keySequence[2] &&
          keySequence[1] != null &&
          keySequence[1] != keySequence[0] &&
          keySequence[1]!.chapterIndex == keySequence[0]!.chapterIndex) {
        result.add(
          _emit(
            'V14',
            'decoded content briefly changes within a chapter and returns',
            frame,
            evidence: <String, Object?>{
              'keys': [
                for (final key in keySequence)
                  key == null
                      ? null
                      : <String, int>{
                          'chapterIndex': key.chapterIndex,
                          'blockIndex': key.blockIndex,
                        },
              ],
            },
          ),
        );
      }
    }

    if (_pairs.length >= 2) {
      final previousKeys =
          _previousContiguousPair()?.frame.decodedProfiles
              .map((profile) => profile.key)
              .toSet() ??
          <BlockKey>{};
      final currentChapters = profiles
          .map((profile) => profile.key.chapterIndex)
          .toSet();
      final previousChapters = previousKeys
          .map((key) => key.chapterIndex)
          .toSet();
      if (currentChapters.length > 1 &&
          previousChapters.length == 1 &&
          currentChapters.containsAll(previousChapters) &&
          currentChapters.length > previousChapters.length) {
        result.add(
          _emit(
            'V15',
            'the previous chapter remains visible after a new chapter appears',
            frame,
            evidence: <String, Object?>{
              'previousChapters': previousChapters.toList(),
              'currentChapters': currentChapters.toList(),
            },
          ),
        );
      }
    }

    if (frame.expectedChapter != null &&
        profiles.every(
          (profile) => profile.key.chapterIndex != frame.expectedChapter,
        )) {
      result.add(
        _emit(
          'V16',
          'the externally requested target chapter has no decoded visual identity',
          frame,
          evidence: <String, Object?>{
            'expectedChapter': frame.expectedChapter,
            'decodedChapters': profiles
                .map((profile) => profile.key.chapterIndex)
                .toSet()
                .toList(),
          },
        ),
      );
    }
    return result;
  }

  List<ReaderVisualViolation> _observeCrossOracle(
    ReaderVisualFrame frame,
    ReaderVisualRuntimeRecord? runtime,
  ) {
    if (runtime == null) return const <ReaderVisualViolation>[];
    final result = <ReaderVisualViolation>[];
    final previousPair = _previousContiguousPair();
    final previousRuntime = previousPair?.runtime;
    final hasCaptureGap = _pairs.length >= 2 && previousPair == null;

    final decodedKeys = frame.decodedProfiles
        .map((profile) => profile.key)
        .toSet();
    final previousRuntimeKeys =
        previousRuntime?.visibleKeys.toSet() ?? <BlockKey>{};
    final keyMismatch =
        decodedKeys.isNotEmpty &&
        decodedKeys.every(
          (key) =>
              !runtime.visibleKeys.contains(key) &&
              !previousRuntimeKeys.contains(key),
        );
    final visualChapter = _dominantDecodedChapter(frame);
    final runtimeChapters = <int>{
      if (runtime.dominantVisibleChapter != null)
        runtime.dominantVisibleChapter!,
      if (runtime.displayedProgressChapter != null)
        runtime.displayedProgressChapter!,
      if (previousRuntime?.dominantVisibleChapter != null)
        previousRuntime!.dominantVisibleChapter!,
      if (previousRuntime?.displayedProgressChapter != null)
        previousRuntime!.displayedProgressChapter!,
    };
    final chapterMismatch =
        visualChapter != null &&
        runtimeChapters.isNotEmpty &&
        !runtimeChapters.contains(visualChapter);

    final currentDelta =
        previousRuntime == null ||
            previousRuntime.scrollPixels == null ||
            runtime.scrollPixels == null
        ? null
        : runtime.scrollPixels! - previousRuntime.scrollPixels!;
    final visualDy = frame.visualDy;
    final directionMismatch =
        visualDy != null &&
        frame.visualCorrelation >= 0.65 &&
        visualDy.abs() > 2 &&
        currentDelta != null &&
        currentDelta.abs() > 2 &&
        visualDy.sign != (-currentDelta).sign;
    final visualMoves =
        visualDy != null &&
        frame.visualCorrelation >= 0.65 &&
        visualDy.abs() > 2 &&
        // The displacement was calculated from the previous captured raster,
        // but a sequence gap means that raster is not an adjacent frame. Do
        // not classify endpoint motion as an idle violation without a
        // contiguous capture pair. The first frame remains eligible because
        // it is the explicit synthetic-injection proof case.
        !hasCaptureGap;

    // A capture can complete after several display frames have already been
    // dropped by the bounded in-flight queue.  In that case the visual delta
    // describes the interval between the two captured rasters, while the
    // current activity flag describes only the endpoint.  If the runtime
    // scroll-pixel delta explains the same signed movement, this is a
    // one-frame/endpoint hand-off rather than evidence that pixels are moving
    // while the runtime is idle.  Keep V19 for motion that has no matching
    // runtime displacement (including the explicit null-pixel injection).
    final visualMatchesRuntimeDelta =
        currentDelta != null &&
        visualDy != null &&
        visualDy.abs() > 2 &&
        visualDy.sign == (-currentDelta).sign &&
        (visualDy.abs() - currentDelta.abs()).abs() <=
            math.max(8.0, currentDelta.abs() * 0.35);

    final runtimeMovesEnough =
        currentDelta != null &&
        currentDelta.abs() > math.max(4.0, runtime.viewportHeight * 0.01);
    if (runtime.claimsScrolling &&
        visualDy != null &&
        frame.visualCorrelation >= 0.65 &&
        visualDy.abs() <= 2 &&
        runtimeMovesEnough &&
        previousRuntime != null) {
      result.add(
        _emit(
          'V18',
          'runtime claims scrolling while the visual raster is frozen',
          frame,
          evidence: <String, Object?>{
            'runtime': runtime.toJson(),
            'visualDy': visualDy,
            'visualCorrelation': frame.visualCorrelation,
          },
        ),
      );
    }
    if (!runtime.claimsScrolling && visualMoves && !visualMatchesRuntimeDelta) {
      result.add(
        _emit(
          'V19',
          'runtime claims idle while the visual raster is moving',
          frame,
          evidence: <String, Object?>{
            'runtime': runtime.toJson(),
            'visualDy': visualDy,
            'visualCorrelation': frame.visualCorrelation,
          },
        ),
      );
    }
    if (keyMismatch || chapterMismatch || directionMismatch) {
      result.add(
        _emit(
          'V20',
          'visual position disagrees with the reported viewport state',
          frame,
          evidence: <String, Object?>{
            'keyMismatch': keyMismatch,
            'chapterMismatch': chapterMismatch,
            'directionMismatch': directionMismatch,
            'decodedKeys': [for (final key in decodedKeys) key.toString()],
            'runtime': runtime.toJson(),
          },
        ),
      );
    }
    if (keyMismatch || chapterMismatch || directionMismatch) {
      result.add(
        _emit(
          'CROSS_ORACLE_MISMATCH',
          'pixel-derived identity/position disagrees with the runtime record',
          frame,
          priority: 'high',
          evidence: <String, Object?>{
            'phaseToleranceFrames': 1,
            'keyMismatch': keyMismatch,
            'chapterMismatch': chapterMismatch,
            'directionMismatch': directionMismatch,
            'decodedProfiles': [
              for (final profile in frame.decodedProfiles) profile.toJson(),
            ],
            'runtime': runtime.toJson(),
            'previousRuntime': previousRuntime?.toJson(),
          },
        ),
      );
    }
    return result;
  }

  List<double> _recentDisplacements(int count) {
    return [
      for (final pair in _contiguousSuffix(count)) pair.frame.visualDy ?? 0,
    ];
  }

  _ReaderVisualPair? _previousContiguousPair() {
    if (_pairs.length < 2) return null;
    final previous = _pairs[_pairs.length - 2];
    final current = _pairs.last;
    return current.frame.sequence == previous.frame.sequence + 1
        ? previous
        : null;
  }

  List<_ReaderVisualPair> _contiguousSuffix(int count) {
    if (_pairs.isEmpty || count <= 0) return const <_ReaderVisualPair>[];
    final reversed = <_ReaderVisualPair>[_pairs.last];
    for (
      var index = _pairs.length - 2;
      index >= 0 && reversed.length < count;
      index -= 1
    ) {
      final next = _pairs[index + 1].frame.sequence;
      final current = _pairs[index].frame.sequence;
      if (next != current + 1) break;
      reversed.add(_pairs[index]);
    }
    return reversed.reversed.toList(growable: false);
  }

  int? _dominantDecodedChapter(ReaderVisualFrame frame) {
    if (frame.decodedProfiles.isEmpty) return null;
    return frame.decodedProfiles.first.key.chapterIndex;
  }

  BlockKey? _dominantDecodedKey(ReaderVisualFrame frame) {
    if (frame.decodedProfiles.isEmpty) return null;
    return frame.decodedProfiles.first.key;
  }

  ReaderVisualViolation _emit(
    String invariant,
    String reason,
    ReaderVisualFrame frame, {
    String priority = 'normal',
    Map<String, Object?> evidence = const <String, Object?>{},
    List<ReaderVisualRawFrame> retainedRawFrames =
        const <ReaderVisualRawFrame>[],
  }) {
    final key = '$invariant:${frame.sequence}';
    if (!_reported.add(key)) {
      return ReaderVisualViolation(
        invariant: invariant,
        reason: reason,
        sequence: frame.sequence,
        timestampMicros: frame.timestampMicros,
        priority: priority,
        evidence: <String, Object?>{...evidence, 'deduplicated': true},
        retainedRawFrames: retainedRawFrames,
      );
    }
    final violation = ReaderVisualViolation(
      invariant: invariant,
      reason: reason,
      sequence: frame.sequence,
      timestampMicros: frame.timestampMicros,
      priority: priority,
      evidence: evidence,
      retainedRawFrames: retainedRawFrames,
    );
    if (_violations.length >= maxViolations) _violations.removeAt(0);
    _violations.add(violation);
    return violation;
  }
}
