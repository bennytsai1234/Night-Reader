import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/reader/chinese_text_converter.dart';
import 'package:night_reader/core/services/chinese_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(ChineseUtils.initialize);

  test('S1 measures 0 to 1 to 2 to 0 length deltas and distribution', () async {
    final sample = await File('samples/西游记.txt').readAsString();
    const readerFixture =
        '读者阅读测试。这是一段足够长的正文内容，供状态转换冒烟测试使用。\n'
        '第二章也有足够长度的正文内容，供状态转换冒烟测试使用。';

    final converter = const ChineseTextConverter();
    for (final entry in <String, String>{
      'samples/西游记.txt': sample,
      'reader_v2_state_transition_smoke_fixture': readerFixture,
    }.entries) {
      final result = await _measureChain(entry.value, converter);
      expect(result.stepBackToZero, isNotEmpty);
      expect(result.traces, hasLength(3));
      expect(
        result.traces.map((trace) => trace.converted),
        orderedEquals(<String>[
          converter.convert(entry.value, convertType: 1),
          converter.convert(
            converter.convert(entry.value, convertType: 1),
            convertType: 2,
          ),
          converter.convert(
            converter.convert(
              converter.convert(entry.value, convertType: 1),
              convertType: 2,
            ),
            convertType: 0,
          ),
        ]),
      );
      _printMeasurement(entry.key, result);
    }
  });
}

Future<_ChainMeasurement> _measureChain(
  String source,
  ChineseTextConverter converter,
) async {
  var current = source;
  final traces = <_ConversionTrace>[];
  for (final convertType in <int>[1, 2, 0]) {
    final converted = converter.convert(current, convertType: convertType);
    traces.add(
      _ConversionTrace(
        fromType: convertType == 1
            ? 0
            : convertType == 2
            ? 1
            : 2,
        toType: convertType,
        input: current,
        converted: converted,
        spans: convertType == 0
            ? const <_LengthSpan>[]
            : await _traceLengthSpans(current, converted, convertType),
      ),
    );
    current = converted;
  }
  return _ChainMeasurement(
    lengths: <int>[
      source.length,
      ...traces.map((trace) => trace.converted.length),
    ],
    traces: traces,
    stepBackToZero: current,
  );
}

Future<List<_LengthSpan>> _traceLengthSpans(
  String input,
  String expectedOutput,
  int convertType,
) async {
  final dictionaryPaths = convertType == 1
      ? <String>[
          'assets/opencc/STPhrases.txt',
          'assets/opencc/STCharacters.txt',
        ]
      : <String>[
          'assets/opencc/TSPhrases.txt',
          'assets/opencc/TSCharacters.txt',
        ];
  final dictionaries = await Future.wait(dictionaryPaths.map(_loadDictionary));
  final phrases = dictionaries[0];
  final characters = dictionaries[1];
  var maxPhraseLength = 1;
  for (final key in phrases.keys) {
    if (key.length > maxPhraseLength) maxPhraseLength = key.length;
  }

  final spans = <_LengthSpan>[];
  final output = StringBuffer();
  var inputOffset = 0;
  while (inputOffset < input.length) {
    String? key;
    String? value;
    final maxTry = (inputOffset + maxPhraseLength <= input.length)
        ? maxPhraseLength
        : input.length - inputOffset;
    for (var tryLength = maxTry; tryLength >= 2; tryLength -= 1) {
      final candidate = input.substring(inputOffset, inputOffset + tryLength);
      final mapped = phrases[candidate];
      if (mapped != null) {
        key = candidate;
        value = mapped;
        break;
      }
    }
    key ??= input[inputOffset];
    value ??= characters[key] ?? key;
    output.write(value);
    if (key.length != value.length) {
      spans.add(
        _LengthSpan(
          start: inputOffset,
          source: key,
          converted: value,
          delta: value.length - key.length,
        ),
      );
    }
    inputOffset += key.length;
  }
  expect(output.toString(), expectedOutput);
  return spans;
}

Future<Map<String, String>> _loadDictionary(String assetPath) async {
  // The test binding has already loaded the same assets for ChineseUtils.
  // This second read is intentionally only for reporting the exact matched
  // phrase/character responsible for a measured length change.
  final data = await rootBundle.loadString(assetPath);
  final dictionary = <String, String>{};
  for (final line in data.split('\n')) {
    if (line.isEmpty) continue;
    final tabIndex = line.indexOf('\t');
    if (tabIndex < 0) continue;
    final key = line.substring(0, tabIndex);
    final valuePart = line.substring(tabIndex + 1).trimRight();
    final spaceIndex = valuePart.indexOf(' ');
    dictionary[key] = spaceIndex < 0
        ? valuePart
        : valuePart.substring(0, spaceIndex);
  }
  return dictionary;
}

void _printMeasurement(String name, _ChainMeasurement measurement) {
  print('S1 fixture=$name');
  print('S1 chain lengths=${measurement.lengths}');
  for (final trace in measurement.traces) {
    final totalDelta = trace.converted.length - trace.input.length;
    final perThousand = trace.input.isEmpty
        ? 0.0
        : totalDelta * 1000 / trace.input.length;
    final distribution = <int, int>{};
    for (final span in trace.spans) {
      final bucket = span.start ~/ 1000;
      distribution[bucket] = (distribution[bucket] ?? 0) + span.delta;
    }
    print(
      'S1 transition=${trace.fromType}->${trace.toType} '
      'inputLength=${trace.input.length} outputLength=${trace.converted.length} '
      'delta=$totalDelta deltaPerThousand=${perThousand.toStringAsFixed(3)} '
      'distribution=$distribution',
    );
    final examples = trace.spans
        .take(20)
        .map(
          (span) =>
              '${span.source}->${span.converted}@${span.start}('
              '${span.delta >= 0 ? '+' : ''}${span.delta})',
        )
        .join(', ');
    print('S1 lengthChangingExamples=$examples');
  }
}

final class _ChainMeasurement {
  const _ChainMeasurement({
    required this.lengths,
    required this.traces,
    required this.stepBackToZero,
  });

  final List<int> lengths;
  final List<_ConversionTrace> traces;
  final String stepBackToZero;
}

final class _ConversionTrace {
  const _ConversionTrace({
    required this.fromType,
    required this.toType,
    required this.input,
    required this.converted,
    required this.spans,
  });

  final int fromType;
  final int toType;
  final String input;
  final String converted;
  final List<_LengthSpan> spans;
}

final class _LengthSpan {
  const _LengthSpan({
    required this.start,
    required this.source,
    required this.converted,
    required this.delta,
  });

  final int start;
  final String source;
  final String converted;
  final int delta;
}
