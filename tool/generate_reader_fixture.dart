import 'dart:io';

import 'package:night_reader/features/reader_v2/correctness/reader_correctness_foundation.dart';

void main(List<String> arguments) {
  var seed = readerCorrectnessFixtureSeed;
  var outputPath = readerCorrectnessFixturePath;
  for (var index = 0; index < arguments.length; index += 1) {
    switch (arguments[index]) {
      case '--seed':
        seed = int.parse(arguments[++index]);
      case '--output':
        outputPath = arguments[++index];
      default:
        throw ArgumentError('Unknown argument: ${arguments[index]}');
    }
  }

  final fixture = ReaderCorrectnessFixture.generate(seed: seed);
  final output = File(outputPath);
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(fixture.serialize(), flush: true);
  stdout.writeln(
    'reader-fixture seed=$seed chapters=${fixture.chapters.length} '
    'paragraphs=${fixture.chapters.fold<int>(0, (sum, chapter) => sum + chapter.paragraphs.length)} '
    'output=${output.path}',
  );
}
