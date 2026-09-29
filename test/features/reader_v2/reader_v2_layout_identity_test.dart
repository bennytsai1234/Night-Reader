import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';

void main() {
  group('ReaderV2 layout ownership', () {
    test('height-only viewport change preserves text layout identity', () {
      final tall = _spec();
      final short = _spec(viewportSize: const Size(360, 600));

      expect(short.layoutSignature, tall.layoutSignature);
      expect(short.viewportSignature, isNot(tall.viewportSignature));
      expect(short.presentationSignature, isNot(tall.presentationSignature));
      expect(
        StyleFingerprint.fromLayoutSpec(short),
        StyleFingerprint.fromLayoutSpec(tall),
      );
    });

    test('vertical padding changes viewport geometry only', () {
      final before = _spec();
      final after = _spec(paddingTop: 36, paddingBottom: 12);

      expect(after.layoutSignature, before.layoutSignature);
      expect(after.viewportSignature, isNot(before.viewportSignature));
      expect(
        StyleFingerprint.fromLayoutSpec(after),
        StyleFingerprint.fromLayoutSpec(before),
      );
    });

    test('width change changes text layout identity', () {
      final before = _spec();
      final after = _spec(viewportSize: const Size(340, 640));

      expect(after.layoutSignature, isNot(before.layoutSignature));
    });

    test('horizontal padding changes text layout identity', () {
      final before = _spec();
      final after = _spec(paddingLeft: 28, paddingRight: 28);

      expect(after.layoutSignature, isNot(before.layoutSignature));
    });

    test('typography change changes text layout identity', () {
      final before = _spec();
      final after = _spec(fontSize: 20);

      expect(after.layoutSignature, isNot(before.layoutSignature));
    });
  });
}

ReaderV2LayoutSpec _spec({
  Size viewportSize = const Size(360, 640),
  double fontSize = 18,
  double paddingTop = 24,
  double paddingBottom = 24,
  double paddingLeft = 20,
  double paddingRight = 20,
}) {
  return ReaderV2LayoutSpec.fromViewport(
    viewportSize: viewportSize,
    cellWidth: fontSize,
    style: ReaderV2LayoutStyle(
      fontSize: fontSize,
      lineHeight: 1.6,
      letterSpacing: 0,
      paragraphSpacing: 0.8,
      paddingTop: paddingTop,
      paddingBottom: paddingBottom,
      paddingLeft: paddingLeft,
      paddingRight: paddingRight,
      textIndent: 2,
    ),
  );
}
