import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/correctness/reader_correctness_foundation.dart';
import 'package:night_reader/features/reader_v2/correctness/reader_correctness_visual_oracle.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

ReaderVisualDecodedProfile _profile(
  int chapter,
  int block, {
  int top = 10,
  int bottom = 30,
  double confidence = 1,
  bool complete = true,
}) {
  return ReaderVisualDecodedProfile(
    key: BlockKey(chapterIndex: chapter, blockIndex: block),
    top: top,
    bottom: bottom,
    confidence: confidence,
    complete: complete,
  );
}

ReaderVisualFrame _frame(
  int sequence, {
  double coverage = 0.1,
  double brightness = 0.9,
  double? dy,
  int height = 100,
  List<ReaderVisualDecodedProfile> profiles = const [],
  int? expectedChapter,
}) {
  return ReaderVisualFrame.synthetic(
    sequence: sequence,
    timestampMicros: sequence,
    width: 160,
    height: height,
    contentCoverage: coverage,
    meanBrightness: brightness,
    visualDy: dy,
    decodedProfiles: profiles,
    expectedChapter: expectedChapter,
  );
}

ReaderVisualRawFrame _raw(int sequence) {
  return ReaderVisualRawFrame(
    sequence: sequence,
    timestampMicros: sequence,
    width: 160,
    height: 100,
    rgba: Uint8List(160 * 100 * 4)..fillRange(0, 160 * 100 * 4, 255),
  );
}

Set<String> _ids(Iterable<ReaderVisualViolation> violations) =>
    violations.map((violation) => violation.invariant).toSet();

List<ReaderVisualViolation> _feed(Iterable<ReaderVisualFrame> frames) {
  final oracle = ReaderVisualOracle();
  final violations = <ReaderVisualViolation>[];
  for (final frame in frames) {
    violations.addAll(oracle.observe(frame));
  }
  return violations;
}

ReaderVisualRaster _profileRaster({
  int chapter = 18,
  int paragraph = 41,
  int start = 12,
  int spacing = 28,
}) {
  final profile = encodeReaderInkProfile(
    chapterIndex: chapter,
    paragraphIndex: paragraph,
  );
  return ReaderVisualRaster.synthetic(
    width: 160,
    height: start + spacing * 19 + 12,
    pixel: (x, y) {
      if (x >= 24 || y < start) return 255;
      final row = (y - start) ~/ spacing;
      if (row < 0 || row >= profile.bits.length) return 255;
      final rowStart = start + row * spacing;
      final rowEnd = rowStart + spacing;
      if (y >= rowEnd || !profile.bits[row]) return 255;
      return 0;
    },
  );
}

void main() {
  group('C4 visual raster primitives', () {
    test('metrics include coverage, brightness, edges, and previous diff', () {
      final previous = ReaderVisualRaster.synthetic(
        width: 160,
        height: 100,
        pixel: (x, y) => x < 20 && y >= 20 && y < 35 ? 0 : 255,
      );
      final current = ReaderVisualRaster.synthetic(
        width: 160,
        height: 100,
        pixel: (x, y) => x < 20 && y >= 30 && y < 45 ? 0 : 255,
      );
      final frame = ReaderVisualFrame.fromRaster(
        sequence: 2,
        timestampMicros: 2,
        raster: current,
        previousRaster: previous,
      );
      expect(frame.contentCoverage, greaterThan(0));
      expect(frame.meanBrightness, lessThan(1));
      expect(frame.edgeDensity, greaterThan(0));
      expect(frame.diffFromPrevious, greaterThan(0));
      expect(frame.rowInkProfile, hasLength(100));
    });

    test(
      'one-dimensional correlation returns the signed visual displacement',
      () {
        final previous = List<int>.filled(120, 0);
        final current = List<int>.filled(120, 0);
        for (var y = 20; y < 35; y += 1) {
          previous[y] = y - 19;
        }
        for (var y = 30; y < 45; y += 1) {
          current[y] = y - 29;
        }
        final displacement = estimateReaderVisualDisplacement(
          previous,
          current,
        );
        expect(displacement.dy, 10);
        expect(displacement.correlation, greaterThan(0.9));
      },
    );

    test('low-correlation rows return unknown rather than an invented dy', () {
      final result = estimateReaderVisualDisplacement(
        List<int>.generate(40, (index) => index.isEven ? 1 : 0),
        List<int>.generate(40, (index) => index % 3),
      );
      expect(result.dy, isNull);
      expect(result.correlation, lessThan(0.65));
    });

    test('C1 profile decodes from the actual 160px analysis raster', () {
      final raster = _profileRaster();
      final frame = ReaderVisualFrame.fromRaster(
        sequence: 1,
        timestampMicros: 1,
        raster: raster,
      );
      expect(
        frame.decodedProfiles.map((profile) => profile.key),
        contains(const BlockKey(chapterIndex: 18, blockIndex: 42)),
      );
      expect(frame.decodedProfiles.first.complete, isTrue);
    });
  });

  group('C4 V1-V20 positive proofs', () {
    test('V1 retains before/middle/after even when white frame recovers', () {
      final oracle = ReaderVisualOracle();
      oracle.observe(_frame(0), rawFrame: _raw(0));
      oracle.observe(_frame(1, coverage: 0, brightness: 1), rawFrame: _raw(1));
      final violations = oracle.observe(_frame(2), rawFrame: _raw(2));
      expect(_ids(violations), contains('V1'));
      final violation = oracle.violations.singleWhere(
        (item) => item.invariant == 'V1',
      );
      expect(violation.retainedRawFrames, hasLength(3));
      expect(violation.toJson()['retainedRawFrames'], hasLength(3));
      expect(violation.evidence['recoveredOnNextFrame'], isTrue);
    });

    test('V1 ignores a legitimate sparse short-chapter frame', () {
      final oracle = ReaderVisualOracle();
      oracle.observe(_frame(0, coverage: 0.0055), rawFrame: _raw(0));
      oracle.observe(
        _frame(1, coverage: 0.0045, brightness: 0.999),
        rawFrame: _raw(1),
      );
      final violations = oracle.observe(
        _frame(2, coverage: 0.0045, brightness: 0.999),
        rawFrame: _raw(2),
      );
      expect(_ids(violations), isNot(contains('V1')));
      expect(_ids(oracle.violations), isNot(contains('V1')));
    });

    test('V2 catches a black frame after content', () {
      expect(
        _ids(_feed([_frame(0), _frame(1, coverage: 0, brightness: 0)])),
        contains('V2'),
      );
    });

    test('V3 catches non-white content disappearance', () {
      expect(
        _ids(
          _feed([
            _frame(0, coverage: 0.2),
            _frame(1, coverage: 0.01, brightness: 0.8),
          ]),
        ),
        contains('V3'),
      );
    });

    test('V4 catches duplicate decoded paragraph identity', () {
      expect(
        _ids(
          _feed([
            _frame(
              0,
              profiles: [_profile(1, 2), _profile(1, 2, top: 40, bottom: 60)],
            ),
          ]),
        ),
        contains('V4'),
      );
    });

    test('V5 catches overlapping paragraph bands', () {
      expect(
        _ids(
          _feed([
            _frame(
              0,
              profiles: [
                _profile(1, 2, top: 10, bottom: 50),
                _profile(1, 3, top: 45, bottom: 80),
              ],
            ),
          ]),
        ),
        contains('V5'),
      );
    });

    test('V6 catches reversed decoded order', () {
      expect(
        _ids(
          _feed([
            _frame(
              0,
              profiles: [_profile(2, 2), _profile(1, 4, top: 40, bottom: 60)],
            ),
          ]),
        ),
        contains('V6'),
      );
    });

    test('V7 catches an abnormal vertical gap', () {
      expect(
        _ids(
          _feed([
            _frame(
              0,
              height: 400,
              profiles: [
                _profile(1, 2, top: 10, bottom: 30),
                _profile(1, 3, top: 180, bottom: 200),
              ],
            ),
          ]),
        ),
        contains('V7'),
      );
    });

    test('V8 catches an incomplete band at a viewport edge', () {
      expect(
        _ids(
          _feed([
            _frame(0, profiles: [_profile(1, 2, complete: false)]),
          ]),
        ),
        contains('V8'),
      );
    });

    test('V9 catches a large visual viewport teleport', () {
      expect(_ids(_feed([_frame(0), _frame(1, dy: 80)])), contains('V9'));
    });

    test('V10 catches a rapid reversal after a large excursion', () {
      final values = <double>[20, 20, 20, 20, -20];
      final oracle = ReaderVisualOracle();
      for (var i = 0; i < values.length; i += 1) {
        oracle.observe(_frame(i, dy: values[i]));
      }
      expect(_ids(oracle.violations), contains('V10'));
    });

    test('V11 catches quiet one-direction visual drift', () {
      final oracle = ReaderVisualOracle();
      for (var i = 0; i < 8; i += 1) {
        oracle.observe(_frame(i, dy: 2));
      }
      expect(_ids(oracle.violations), contains('V11'));
    });

    test('V12 catches post-settle creep', () {
      expect(
        _ids(
          _feed([
            for (var i = 0; i < 3; i += 1) _frame(i, dy: 0),
            for (var i = 3; i < 6; i += 1) _frame(i, dy: 3),
          ]),
        ),
        contains('V12'),
      );
    });

    test('V12 does not infer creep across dropped visual samples', () {
      expect(
        _ids(
          _feed([
            _frame(0, dy: 0),
            _frame(1, dy: 0),
            _frame(2, dy: 0),
            // Sequence 3 was dropped by the asynchronous capture path.
            _frame(4, dy: 3),
            _frame(5, dy: 3),
            _frame(6, dy: 3),
          ]),
        ),
        isNot(contains('V12')),
      );
    });

    test('V13 catches a transient wrong chapter', () {
      expect(
        _ids(
          _feed([
            _frame(0, profiles: [_profile(8, 1)]),
            _frame(1, profiles: [_profile(9, 1)]),
            _frame(2, profiles: [_profile(8, 1)]),
          ]),
        ),
        contains('V13'),
      );
    });

    test('V14 catches a transient wrong paragraph in the same chapter', () {
      expect(
        _ids(
          _feed([
            _frame(0, profiles: [_profile(8, 1)]),
            _frame(1, profiles: [_profile(8, 5)]),
            _frame(2, profiles: [_profile(8, 1)]),
          ]),
        ),
        contains('V14'),
      );
    });

    test('V15 catches previous chapter lingering beside the target', () {
      expect(
        _ids(
          _feed([
            _frame(0, profiles: [_profile(8, 1)]),
            _frame(
              1,
              profiles: [_profile(8, 1), _profile(9, 1, top: 40, bottom: 60)],
            ),
          ]),
        ),
        contains('V15'),
      );
    });

    test('V16 catches an expected target chapter with no visual identity', () {
      expect(
        _ids(
          _feed([
            _frame(0, expectedChapter: 12, profiles: [_profile(11, 1)]),
          ]),
        ),
        contains('V16'),
      );
    });

    test('V17 catches small anchor oscillation', () {
      final values = <double>[5, -5, 5, -5, 5, -5];
      final oracle = ReaderVisualOracle();
      for (var i = 0; i < values.length; i += 1) {
        oracle.observe(_frame(i, dy: values[i]));
      }
      expect(_ids(oracle.violations), contains('V17'));
    });

    test('V18 catches visual freeze while runtime claims scrolling', () {
      final oracle = ReaderVisualOracle();
      const runtime = ReaderVisualRuntimeRecord(
        timestampMicros: 0,
        visibleKeys: [BlockKey(chapterIndex: 1, blockIndex: 2)],
        scrollPixels: 0,
        dominantVisibleChapter: 1,
        displayedProgressChapter: 1,
        phase: 'ready',
        scrollActivity: 'ballistic',
        isScrolling: true,
        viewportHeight: 100,
      );
      oracle.observe(_frame(0, dy: 0), runtime: runtime);
      oracle.observe(
        _frame(1, dy: 0),
        runtime: const ReaderVisualRuntimeRecord(
          timestampMicros: 1,
          visibleKeys: [BlockKey(chapterIndex: 1, blockIndex: 2)],
          scrollPixels: 10,
          dominantVisibleChapter: 1,
          displayedProgressChapter: 1,
          phase: 'ready',
          scrollActivity: 'ballistic',
          isScrolling: true,
          viewportHeight: 100,
        ),
      );
      expect(_ids(oracle.violations), contains('V18'));
    });

    test('V19 catches visual motion while runtime claims idle', () {
      final oracle = ReaderVisualOracle();
      oracle.observe(
        _frame(0, dy: 12),
        runtime: const ReaderVisualRuntimeRecord(
          timestampMicros: 0,
          visibleKeys: [BlockKey(chapterIndex: 1, blockIndex: 2)],
          scrollPixels: 10,
          dominantVisibleChapter: 1,
          displayedProgressChapter: 1,
          phase: 'ready',
          scrollActivity: 'idle',
          isScrolling: false,
          viewportHeight: 100,
        ),
      );
      expect(_ids(oracle.violations), contains('V19'));
    });

    test('V19 does not infer idle motion across dropped visual samples', () {
      final oracle = ReaderVisualOracle();
      oracle.observe(
        _frame(0, dy: 0),
        runtime: const ReaderVisualRuntimeRecord(
          timestampMicros: 0,
          visibleKeys: [BlockKey(chapterIndex: 1, blockIndex: 2)],
          scrollPixels: 0,
          dominantVisibleChapter: 1,
          displayedProgressChapter: 1,
          phase: 'ready',
          scrollActivity: 'idle',
          isScrolling: false,
          viewportHeight: 100,
        ),
      );
      oracle.observe(
        _frame(2, dy: 12),
        runtime: const ReaderVisualRuntimeRecord(
          timestampMicros: 2,
          visibleKeys: [BlockKey(chapterIndex: 1, blockIndex: 2)],
          scrollPixels: 0,
          dominantVisibleChapter: 1,
          displayedProgressChapter: 1,
          phase: 'ready',
          scrollActivity: 'idle',
          isScrolling: false,
          viewportHeight: 100,
        ),
      );
      expect(_ids(oracle.violations), isNot(contains('V19')));
    });

    test('V20 and CROSS_ORACLE_MISMATCH report a key/chapter disagreement', () {
      final oracle = ReaderVisualOracle();
      oracle.observe(
        _frame(0, profiles: [_profile(9, 1)]),
        runtime: const ReaderVisualRuntimeRecord(
          timestampMicros: 0,
          visibleKeys: [BlockKey(chapterIndex: 8, blockIndex: 1)],
          scrollPixels: 0,
          dominantVisibleChapter: 8,
          displayedProgressChapter: 8,
          phase: 'ready',
          scrollActivity: 'idle',
          isScrolling: false,
          viewportHeight: 100,
        ),
      );
      expect(
        _ids(oracle.violations),
        containsAll(['V20', 'CROSS_ORACLE_MISMATCH']),
      );
      expect(
        oracle.violations
            .singleWhere((item) => item.invariant == 'CROSS_ORACLE_MISMATCH')
            .priority,
        'high',
      );
    });
  });

  group('C4 continuous negative proofs', () {
    test(
      'normal fling-sized displacement does not trigger V7/V9/V10/V11/V12/V17',
      () {
        final oracle = ReaderVisualOracle();
        for (var i = 0; i < 8; i += 1) {
          oracle.observe(_frame(i, dy: 35 - i * 3.0));
        }
        final ids = _ids(oracle.violations);
        expect(
          ids.intersection({'V7', 'V9', 'V10', 'V11', 'V12', 'V17'}),
          isEmpty,
        );
      },
    );

    test(
      'user-sized reversal remains below the unexpected-reversal budget',
      () {
        final oracle = ReaderVisualOracle();
        for (var i = 0; i < 6; i += 1) {
          oracle.observe(_frame(i, dy: i.isEven ? 10 : -10));
        }
        final ids = _ids(oracle.violations);
        expect(ids.intersection({'V10', 'V17'}), isEmpty);
      },
    );

    test('one ordinary settled frame has no visual violation', () {
      expect(_feed([_frame(0)]), isEmpty);
    });
  });

  group('C4 phase tolerance and serialization', () {
    test('one-frame runtime phase offset is accepted for decoded identity', () {
      final oracle = ReaderVisualOracle();
      oracle.observe(
        _frame(0, profiles: [_profile(8, 1)]),
        runtime: const ReaderVisualRuntimeRecord(
          timestampMicros: 0,
          visibleKeys: [BlockKey(chapterIndex: 8, blockIndex: 1)],
          scrollPixels: 0,
          dominantVisibleChapter: 8,
          displayedProgressChapter: 8,
          phase: 'ready',
          scrollActivity: 'idle',
          isScrolling: false,
          viewportHeight: 100,
        ),
      );
      oracle.observe(
        _frame(1, profiles: [_profile(8, 1)]),
        runtime: const ReaderVisualRuntimeRecord(
          timestampMicros: 1,
          visibleKeys: [BlockKey(chapterIndex: 8, blockIndex: 1)],
          scrollPixels: 0,
          dominantVisibleChapter: 8,
          displayedProgressChapter: 8,
          phase: 'ready',
          scrollActivity: 'idle',
          isScrolling: false,
          viewportHeight: 100,
        ),
      );
      expect(_ids(oracle.violations), isNot(contains('CROSS_ORACLE_MISMATCH')));
    });

    test('violation JSON includes visual source and evidence dimensions', () {
      final oracle = ReaderVisualOracle();
      oracle.observe(_frame(0), rawFrame: _raw(0));
      oracle.observe(_frame(1, coverage: 0, brightness: 1), rawFrame: _raw(1));
      oracle.observe(_frame(2), rawFrame: _raw(2));
      final json = oracle.violations.first.toJson();
      expect(json['oracle'], 'visual');
      expect(json['invariant'], 'V1');
      expect(json['retainedRawFrames'], hasLength(3));
      expect((json['retainedRawFrames']! as List).first['width'], 160);
    });
  });
}
