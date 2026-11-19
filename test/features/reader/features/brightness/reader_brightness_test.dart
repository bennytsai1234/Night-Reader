import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader/features/brightness/reader_brightness.dart';

void main() {
  group('ReaderBrightness', () {
    test('above the dim zone only the backlight changes', () {
      expect(ReaderBrightness.backlightFor(1), 1);
      expect(ReaderBrightness.dimFor(1), 0);
      expect(
        ReaderBrightness.backlightFor(ReaderBrightness.dimZone),
        ReaderBrightness.minBacklight,
      );
      expect(ReaderBrightness.dimFor(ReaderBrightness.dimZone), 0);
      final mid = ReaderBrightness.backlightFor(0.625);
      expect(mid, greaterThan(ReaderBrightness.minBacklight));
      expect(mid, lessThan(1));
    });

    test('inside the dim zone the backlight stays at its lowest', () {
      expect(ReaderBrightness.backlightFor(0.1), ReaderBrightness.minBacklight);
      expect(ReaderBrightness.backlightFor(0), ReaderBrightness.minBacklight);
      expect(ReaderBrightness.dimFor(0), ReaderBrightness.defaultMaxDim);
      final half = ReaderBrightness.dimFor(ReaderBrightness.dimZone / 2);
      expect(half, closeTo(ReaderBrightness.defaultMaxDim / 2, 1e-9));
    });

    test('the bottom of the bar reaches the chosen darkest level', () {
      expect(ReaderBrightness.dimFor(0, maxDim: 0.85), 0.85);
      expect(ReaderBrightness.dimFor(0, maxDim: 2), ReaderBrightness.maxMaxDim);
      expect(ReaderBrightness.dimFor(ReaderBrightness.dimZone), 0);
    });

    test('normalize clamps and falls back to the default', () {
      expect(ReaderBrightness.normalize(null), ReaderBrightness.defaultLevel);
      expect(
        ReaderBrightness.normalize(double.nan),
        ReaderBrightness.defaultLevel,
      );
      expect(ReaderBrightness.normalize(-1), 0);
      expect(ReaderBrightness.normalize(2), 1);
    });
  });
}
