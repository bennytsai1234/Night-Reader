import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reader_correctness_operations.dart';

/// Render the exact ink/no-ink band on the current platform and return one
/// measured ink width per visual row.  The decoder remains independent; this
/// helper only supplies its pixel observation vector.
Future<List<int>> captureReaderInkWidths(
  WidgetTester tester,
  ReaderInkProfile profile, {
  double width = 280,
}) async {
  final boundaryKey = GlobalKey();
  const textStyle = TextStyle(color: Colors.black, fontSize: 18, height: 1.5);
  await tester.pumpWidget(
    MaterialApp(
      home: ColoredBox(
        color: Colors.white,
        child: RepaintBoundary(
          key: boundaryKey,
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final bit in profile.bits)
                  SizedBox(
                    width: width,
                    height: 28,
                    child: Text(bit ? '墨' : '\u2060', style: textStyle),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final byteData = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final widths = <int>[];
  for (var row = 0; row < profile.rowCount; row += 1) {
    final top = (row * 28).clamp(0, image.height - 1);
    final bottom = ((row + 1) * 28).clamp(top + 1, image.height);
    var inkPixels = 0;
    for (var y = top; y < bottom; y += 1) {
      for (var x = 0; x < image.width; x += 1) {
        final offset = (y * image.width + x) * 4;
        final red = byteData.getUint8(offset);
        final green = byteData.getUint8(offset + 1);
        final blue = byteData.getUint8(offset + 2);
        final alpha = byteData.getUint8(offset + 3);
        if (alpha > 0 && red < 245 && green < 245 && blue < 245) {
          inkPixels += 1;
        }
      }
    }
    widths.add(inkPixels);
  }
  image.dispose();
  return widths;
}
