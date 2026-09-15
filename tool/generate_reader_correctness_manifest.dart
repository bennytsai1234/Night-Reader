import 'dart:convert';
import 'dart:io';

import '../test/reader_correctness/reader_correctness_case_generation.dart';

/// Generate the deterministic artifacts consumed by C6.  This is intentionally
/// separate from the default flutter test path: the generated JSON is a
/// durable input artifact, while the C5 full sweep is invoked independently by
/// `flutter test tool/reader_correctness_host_full_sweep_test.dart`.
void main() {
  const seeds = <int>[9132051, 9132052];
  Directory('docs/changes/evidence').createSync(recursive: true);
  final manifests = <Map<String, Object?>>[];
  for (final seed in seeds) {
    final manifest = generateReaderCorrectnessManifest(seed: seed);
    final path =
        'docs/changes/evidence/2026-09-14-reader-v2-c5-manifest-seed-$seed.json';
    File(path).writeAsStringSync(manifest.canonicalJson);
    manifests.add(<String, Object?>{
      'seed': seed,
      'path': path,
      'caseCount': manifest.cases.length,
      'sha256': manifest.sha256,
      'layerCounts': manifest.layerCounts,
    });
  }
  final first = generateReaderCorrectnessManifest(seed: seeds.first);
  File('docs/changes/evidence/2026-09-14-reader-v2-c5-coverage-report.json')
      .writeAsStringSync(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'operationCount': first.coverage.operationCount,
          'manifests': manifests,
          'coverage': first.coverage.toJson(),
          'fullSweepBoundary': 'host logical oracle stream; visualCapturedFrames=0 and visualCoverage=0.0; actual raster evidence remains C4/C6',
        }),
      );
  stdout.writeln(jsonEncode(<String, Object?>{'manifests': manifests}));
}
