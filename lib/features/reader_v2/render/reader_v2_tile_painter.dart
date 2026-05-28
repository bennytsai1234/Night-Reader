import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:reader/features/reader_v2/render/reader_v2_page_cache.dart';
import 'package:reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:reader/features/reader_v2/layout/reader_v2_typography.dart';
import 'package:reader/features/reader_v2/render/reader_v2_render_page.dart';

typedef ReaderV2TilePaintObserver = void Function(ReaderV2PageCache tile);

class ReaderV2TilePainter extends CustomPainter {
  ReaderV2TilePainter({
    required this.tile,
    required this.backgroundColor,
    required this.textColor,
    required this.style,
    this.debugOverlay = false,
    this.paintBackground = true,
  });

  final ReaderV2PageCache tile;
  final Color backgroundColor;
  final Color textColor;
  final ReaderV2Style style;
  final bool debugOverlay;
  final bool paintBackground;

  /// Capacity for the TextPainter cache.
  /// Tablet justified paint may request ~30 clusters × 25 lines = ~750
  /// entries for a single tile, so we keep room for several visible tiles
  /// plus the active line painters.
  static const int _cacheCapacity = 2400;

  /// LinkedHashMap preserves insertion order, enabling LRU-style eviction
  /// of the oldest quarter when the cache is full.
  static final LinkedHashMap<(String, int), TextPainter> _textPainterCache =
      LinkedHashMap<(String, int), TextPainter>();
  static ReaderV2TilePaintObserver? debugOnPaint;

  /// Per-painter style signatures, cached for body and title text. Computed
  /// once per painter instance so cluster lookups during justified paint
  /// do not allocate a new cache key string each call.
  int? _bodyStyleSignature;
  int? _titleStyleSignature;

  /// Call when reader style changes (font, size, color, etc.) to avoid
  /// stale painters lingering in the cache.
  static void invalidateCache() {
    _textPainterCache.clear();
  }

  @override
  void paint(Canvas canvas, Size size) {
    assert(() {
      debugOnPaint?.call(tile);
      return true;
    }());

    if (paintBackground) {
      canvas.drawColor(backgroundColor, BlendMode.src);
    }
    final left = style.paddingLeft;
    final top = style.paddingTop;
    final contentWidth =
        (size.width - style.paddingLeft - style.paddingRight)
            .clamp(1.0, double.infinity)
            .toDouble();

    final contentRect = Rect.fromLTWH(
      left,
      top,
      contentWidth,
      tile.contentHeight,
    );
    canvas.save();
    canvas.clipRect(contentRect);
    for (final line in tile.lines) {
      _paintLine(canvas, line, Offset(left, top + line.top), contentWidth);
    }
    canvas.restore();

    if (debugOverlay) {
      final debugPainter = TextPainter(
        text: TextSpan(
          text:
              'c${tile.chapterIndex} p${tile.pageIndex} ${tile.startCharOffset}-${tile.endCharOffset}',
          style: TextStyle(
            color: textColor.withValues(alpha: 0.45),
            fontSize: 10,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: size.width);
      debugPainter.paint(canvas, Offset(left, top + 2));
    }
  }

  void _paintLine(
    Canvas canvas,
    ReaderV2RenderLine line,
    Offset offset,
    double contentWidth,
  ) {
    // Layout engine already measured `line.width` with the same TextStyle,
    // so we can decide justification without building the full-line painter.
    if (!_shouldJustifyLine(line, line.width, contentWidth)) {
      _painterFor(line).paint(canvas, offset);
      return;
    }

    final clusters = line.text.characters.toList(growable: false);
    final leadingIndentCount = _leadingIndentCount(clusters);
    final stretchableGapCount = clusters.length - 1 - leadingIndentCount;
    if (stretchableGapCount <= 0) {
      _painterFor(line).paint(canvas, offset);
      return;
    }

    final extraGap = (contentWidth - line.width) / stretchableGapCount;
    if (!extraGap.isFinite || extraGap <= 0) {
      _painterFor(line).paint(canvas, offset);
      return;
    }

    final letterSpacing =
        style.letterSpacing.isFinite ? style.letterSpacing : 0.0;
    var dx = 0.0;
    for (var index = 0; index < clusters.length; index++) {
      final cluster = clusters[index];
      final clusterPainter = _painterForText(cluster, isTitle: line.isTitle);
      clusterPainter.paint(canvas, offset.translate(dx, 0));
      if (index == clusters.length - 1) break;
      dx += clusterPainter.width + letterSpacing;
      if (index >= leadingIndentCount) {
        dx += extraGap;
      }
    }
  }

  bool _shouldJustifyLine(
    ReaderV2RenderLine line,
    double lineWidth,
    double contentWidth,
  ) {
    if (line.isTitle || line.isParagraphEnd || line.text.isEmpty) return false;
    final remaining = contentWidth - lineWidth;
    return remaining.isFinite && remaining > 0.5;
  }

  int _leadingIndentCount(List<String> clusters) {
    var count = 0;
    for (final cluster in clusters) {
      if (cluster != '　') break;
      count += 1;
    }
    return count;
  }

  TextPainter _painterFor(ReaderV2RenderLine line) {
    return _painterForText(line.text, isTitle: line.isTitle);
  }

  TextPainter _painterForText(String text, {required bool isTitle}) {
    final styleSignature = _styleSignatureFor(isTitle: isTitle);
    final key = (text, styleSignature);
    final cached = _textPainterCache[key];
    if (cached != null) return cached;

    final effectiveLineHeight = style.effectiveLineHeight;
    final textStyle = TextStyle(
      color: textColor,
      fontSize: isTitle ? style.fontSize + 4 : style.fontSize,
      height: effectiveLineHeight,
      letterSpacing: style.letterSpacing,
      fontWeight: isTitle || style.bold ? FontWeight.bold : FontWeight.normal,
      fontFeatures: kReaderV2CjkFontFeatures,
    );
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout(maxWidth: double.infinity);

    if (_textPainterCache.length >= _cacheCapacity) {
      // Evict the oldest quarter so an over-budget paint does not flush
      // half the cache. LinkedHashMap iterates oldest-first.
      final evictCount = _cacheCapacity ~/ 4;
      final keysToRemove = _textPainterCache.keys
          .take(evictCount)
          .toList(growable: false);
      for (final evictKey in keysToRemove) {
        _textPainterCache.remove(evictKey);
      }
    }
    _textPainterCache[key] = painter;
    return painter;
  }

  int _styleSignatureFor({required bool isTitle}) {
    final cached = isTitle ? _titleStyleSignature : _bodyStyleSignature;
    if (cached != null) return cached;
    final signature = Object.hash(
      isTitle,
      style.fontSize,
      style.effectiveLineHeight,
      style.letterSpacing,
      style.bold,
      kReaderV2CjkTypographyFeatureSignature,
      textColor.toARGB32(),
    );
    if (isTitle) {
      _titleStyleSignature = signature;
    } else {
      _bodyStyleSignature = signature;
    }
    return signature;
  }

  @override
  bool shouldRepaint(covariant ReaderV2TilePainter oldDelegate) {
    return oldDelegate.tile != tile ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.textColor != textColor ||
        oldDelegate.style != style ||
        oldDelegate.debugOverlay != debugOverlay ||
        oldDelegate.paintBackground != paintBackground;
  }
}
