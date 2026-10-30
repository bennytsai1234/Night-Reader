import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/features/brightness/reader_v2_brightness.dart';

void main() {
  group('ReaderV2Brightness', () {
    test('above the dim zone only the backlight changes', () {
      expect(ReaderV2Brightness.backlightFor(1), 1);
      expect(ReaderV2Brightness.dimFor(1), 0);
      expect(
        ReaderV2Brightness.backlightFor(ReaderV2Brightness.dimZone),
        ReaderV2Brightness.minBacklight,
      );
      expect(ReaderV2Brightness.dimFor(ReaderV2Brightness.dimZone), 0);
      final mid = ReaderV2Brightness.backlightFor(0.625);
      expect(mid, greaterThan(ReaderV2Brightness.minBacklight));
      expect(mid, lessThan(1));
    });

    test('inside the dim zone the backlight stays at its lowest', () {
      expect(
        ReaderV2Brightness.backlightFor(0.1),
        ReaderV2Brightness.minBacklight,
      );
      expect(
        ReaderV2Brightness.backlightFor(0),
        ReaderV2Brightness.minBacklight,
      );
      expect(ReaderV2Brightness.dimFor(0), ReaderV2Brightness.defaultMaxDim);
      final half = ReaderV2Brightness.dimFor(ReaderV2Brightness.dimZone / 2);
      expect(half, closeTo(ReaderV2Brightness.defaultMaxDim / 2, 1e-9));
    });

    test('the bottom of the bar reaches the chosen darkest level', () {
      expect(ReaderV2Brightness.dimFor(0, maxDim: 0.85), 0.85);
      expect(
        ReaderV2Brightness.dimFor(0, maxDim: 2),
        ReaderV2Brightness.maxMaxDim,
      );
      expect(ReaderV2Brightness.dimFor(ReaderV2Brightness.dimZone), 0);
    });

    test('normalize clamps and falls back to the default', () {
      expect(
        ReaderV2Brightness.normalize(null),
        ReaderV2Brightness.defaultLevel,
      );
      expect(
        ReaderV2Brightness.normalize(double.nan),
        ReaderV2Brightness.defaultLevel,
      );
      expect(ReaderV2Brightness.normalize(-1), 0);
      expect(ReaderV2Brightness.normalize(2), 1);
    });
  });
}
