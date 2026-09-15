import 'dart:convert';
import 'dart:io';

import '../test/reader_correctness/reader_correctness_case_generation.dart';

/// Generate the finite C6 Android input.  The tool accepts a C5 manifest and
/// an optional JSON array of host-failure case ids; it never interprets an
/// operation id or duplicates the operation catalog in PowerShell.
void main(List<String> arguments) {
  final options = _parseOptions(arguments);
  final manifestPath =
      options['manifest'] ??
      'docs/changes/evidence/2026-09-14-reader-v2-c5-manifest-seed-9132051.json';
  final laneSuffix = (options['lane'] ?? 'smoke') == 'acceptance'
      ? ''
      : '-smoke';
  final outputPath =
      options['output'] ??
      'docs/changes/evidence/2026-09-14-reader-v2-c6-android-subset-seed-'
          '${_manifestSeed(manifestPath)}$laneSuffix.json';
  final failurePath = options['host-failures'];
  final manifest = ReaderCorrectnessManifest.fromJsonString(
    File(manifestPath).readAsStringSync(),
  );
  final hostFailures = failurePath == null
      ? const <String>[]
      : _readFailureIds(failurePath);
  final laneName = options['lane'] ?? 'smoke';
  final lane = switch (laneName) {
    'smoke' => ReaderCorrectnessAndroidLane.smoke,
    'acceptance' => ReaderCorrectnessAndroidLane.acceptance,
    _ => throw ArgumentError('Unknown --lane $laneName'),
  };
  final selection = selectReaderCorrectnessAndroidSubset(
    manifest,
    hostFailureCaseIds: hostFailures,
    lane: lane,
  );
  Directory(File(outputPath).parent.path).createSync(recursive: true);
  File(outputPath).writeAsStringSync(selection.canonicalJson);
  final summary = <String, Object?>{
    'seed': selection.seed,
    'manifestPath': manifestPath,
    'outputPath': outputPath,
    'manifestSha256': manifest.sha256,
    'subsetSha256': selection.sha256,
    'lane': lane.wireName,
    'caseCount': selection.cases.length,
    'hostFailureCaseIds': selection.hostFailureCaseIds,
    'ruleCoverage': selection.ruleCoverage,
  };
  final summaryPath =
      options['summary'] ??
      'docs/changes/evidence/2026-09-14-reader-v2-c6-subset-coverage-seed-'
          '${selection.seed}$laneSuffix.json';
  Directory(File(summaryPath).parent.path).createSync(recursive: true);
  File(summaryPath).writeAsStringSync(jsonEncode(summary));
  stdout.writeln(jsonEncode(summary));
}

Map<String, String> _parseOptions(List<String> arguments) {
  final result = <String, String>{};
  for (var index = 0; index < arguments.length; index += 1) {
    final argument = arguments[index];
    if (!argument.startsWith('--') || index + 1 >= arguments.length) {
      throw ArgumentError('Expected --name value, got $argument');
    }
    result[argument.substring(2)] = arguments[++index];
  }
  return result;
}

int _manifestSeed(String path) {
  final match = RegExp(r'seed-(\d+)\.json$').firstMatch(path);
  if (match == null) throw ArgumentError('Cannot infer seed from $path');
  return int.parse(match.group(1)!);
}

List<String> _readFailureIds(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  if (decoded is! List) {
    throw const FormatException('host failure case file must be a JSON array');
  }
  return [
    for (final value in decoded)
      if (value is String && value.trim().isNotEmpty) value.trim(),
  ];
}
