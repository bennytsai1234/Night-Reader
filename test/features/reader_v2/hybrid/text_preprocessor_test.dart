import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/text/text_preprocessor.dart';

void main() {
  test('block 邊界不會切開 UTF-16 代理對', () async {
    final chapter = ChapterText(
      id: 0,
      title: '',
      paragraphs: const <String>['A😀B'],
      displayText: 'A😀B',
      contentHash: 'unicode-boundary',
    );

    final result = await const TextPreprocessor(
      useIsolate: false,
    ).process(chapter, maxBlockChars: 2);

    expect(result.blocks.map((block) => block.text), <String>['A😀', 'B']);
    expect(
      result.blocks.map((block) => block.text).join(),
      chapter.displayText,
    );
  });
}
