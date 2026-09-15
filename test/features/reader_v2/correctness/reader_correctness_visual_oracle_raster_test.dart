import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/correctness/reader_correctness_foundation.dart';
import 'package:night_reader/features/reader_v2/correctness/reader_correctness_visual_oracle.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

Future<ReaderVisualRaster> _captureProfileRaster(
  WidgetTester tester,
  ReaderInkProfile profile,
) async {
  final boundaryKey = GlobalKey();
  const width = 280.0;
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
                const SizedBox(height: 32),
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
  final image = await boundary.toImage(pixelRatio: 1.0);
  final byteData = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final rgba = Uint8List.fromList(
    byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
  );
  final raster = ReaderVisualRaster.fromRgba(
    sourceWidth: image.width,
    sourceHeight: image.height,
    rgba: rgba,
    analysisWidth: readerVisualDefaultAnalysisWidth,
  );
  image.dispose();
  return raster;
}

void main() {
  testWidgets(
    'C4 actual 160px raster decodes 50 C1 profiles and matches runtime keys',
    (tester) async {
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
      var decodedProfiles = 0;
      var matchingProfiles = 0;
      for (var sample = 0; sample < 50; sample += 1) {
        final coordinate =
            coordinates[(sample * 137 + 29) % coordinates.length];
        final raster = await _captureProfileRaster(
          tester,
          encodeReaderInkProfile(
            chapterIndex: coordinate.chapterIndex,
            paragraphIndex: coordinate.paragraphIndex,
          ),
        );
        final frame = ReaderVisualFrame.fromRaster(
          sequence: sample,
          timestampMicros: sample,
          raster: raster,
        );
        final key = BlockKey(
          chapterIndex: coordinate.chapterIndex,
          blockIndex: coordinate.paragraphIndex + 1,
        );
        final runtime = ReaderVisualRuntimeRecord(
          timestampMicros: sample,
          visibleKeys: [key],
          scrollPixels: 0,
          dominantVisibleChapter: coordinate.chapterIndex,
          displayedProgressChapter: coordinate.chapterIndex,
          phase: 'ready',
          scrollActivity: 'idle',
          isScrolling: false,
          viewportHeight: raster.height.toDouble(),
        );
        final oracle = ReaderVisualOracle();
        final violations = oracle.observe(frame, runtime: runtime);
        if (violations.isNotEmpty) {
          debugPrint(
            'C4_HOST_PROFILE_VIOLATIONS sample=$sample '
            '${violations.map((violation) => violation.toJson()).toList()}',
          );
        }
        expect(violations, isEmpty);
        expect(frame.width, readerVisualDefaultAnalysisWidth);
        expect(frame.decodedProfiles, hasLength(1));
        expect(frame.decodedProfiles.single.key, key);
        decodedProfiles += frame.decodedProfiles.length;
        final stats = oracle.profileMatchStats();
        matchingProfiles += stats['matchingProfiles'] as int;
      }
      debugPrint(
        'C4_HOST_PROFILE_DECODE decodedProfiles=$decodedProfiles '
        'matchingProfiles=$matchingProfiles samples=50 analysisWidth='
        '$readerVisualDefaultAnalysisWidth sourceRaster=280x564',
      );
      expect(decodedProfiles, 50);
      expect(matchingProfiles, 50);
    },
  );
}
