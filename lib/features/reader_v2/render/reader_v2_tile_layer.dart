import 'package:flutter/material.dart';
import 'package:reader/features/reader_v2/render/reader_v2_page_cache.dart';
import 'package:reader/features/reader_v2/layout/reader_v2_style.dart';
import 'package:reader/features/reader_v2/render/reader_v2_tile_key.dart';

import 'reader_v2_tile_painter.dart';

class ReaderV2TileLayer extends StatelessWidget {
  const ReaderV2TileLayer({
    super.key,
    required this.tile,
    required this.style,
    required this.backgroundColor,
    required this.textColor,
    required this.tileKey,
    this.expand = false,
    this.debugOverlay = false,
    this.paintBackground = true,
  });

  final ReaderV2PageCache tile;
  final ReaderV2Style style;
  final Color backgroundColor;
  final Color textColor;
  final ReaderV2TileKey tileKey;
  final bool expand;
  final bool debugOverlay;
  final bool paintBackground;

  @override
  Widget build(BuildContext context) {
    final paint = CustomPaint(
      painter: ReaderV2TilePainter(
        tile: tile,
        style: style,
        backgroundColor: backgroundColor,
        textColor: textColor,
        debugOverlay: debugOverlay,
        paintBackground: paintBackground,
      ),
    );

    return RepaintBoundary(
      key: ValueKey<ReaderV2TileKey>(tileKey),
      child:
          expand
              ? SizedBox.expand(child: paint)
              : SizedBox(
                width: double.infinity,
                height: tile.height,
                child: paint,
              ),
    );
  }
}
