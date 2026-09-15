import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:integration_test/integration_test.dart';

import '../test/reader_correctness/reader_correctness_raster.dart';
import 'reader_test_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android decodes 50 deterministic fixture profiles from pixels', (
    tester,
  ) async {
    final harness = ReaderTestHarness(tester);
    await harness.startAndProvision();
    final fixture = ReaderCorrectnessFixture.generate();
    final coordinates = [
      for (final chapter in fixture.chapters)
        for (
          var paragraph = 0;
          paragraph < chapter.paragraphs.length;
          paragraph += 1
        )
          (chapterIndex: chapter.index, paragraphIndex: paragraph),
    ];
    final selected = [
      for (var sample = 0; sample < 50; sample += 1)
        coordinates[(sample * 137 + 29) % coordinates.length],
    ];
    var decoded = 0;
    for (final coordinate in selected) {
      final profile = encodeReaderInkProfile(
        chapterIndex: coordinate.chapterIndex,
        paragraphIndex: coordinate.paragraphIndex,
      );
      final widths = await captureReaderInkWidths(tester, profile);
      expect(
        decodeReaderInkProfile(widths),
        coordinate,
        reason: 'Android pixel decode failed for $coordinate',
      );
      decoded += 1;
    }
    expect(decoded, 50);
    debugPrint(
      'C1_ANDROID_DECODE decoded=$decoded totalFixtureParagraphs=${coordinates.length} '
      'seed=$readerCorrectnessFixtureSeed',
    );
    debugPrint(
      'READER_E2E_RESULT status=passed fixture=$readerFixtureHostPath '
      'decodedProfiles=$decoded',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
