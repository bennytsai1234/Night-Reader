import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/text/text_preprocessor.dart';

void main() {
  test('長段落切塊不拆開組合 emoji 與結合音標', () async {
    const content = '甲👩‍💻乙e\u0301丙';
    final blocks = await const TextPreprocessor(useIsolate: false).process(
      ChapterText(
        id: 0,
        title: '',
        paragraphs: [content],
        displayText: content,
        contentHash: 'unicode-test',
      ),
      maxBlockChars: 2,
    );
    final pieces = blocks.blocks.map((block) => block.text).toList();
    expect(pieces.join(), content);
    expect(pieces.where((piece) => piece.contains('👩‍💻')).length, 1);
    expect(pieces.where((piece) => piece.contains('e\u0301')).length, 1);
    expect(pieces.any((piece) => piece.startsWith('\u200D')), isFalse);
    expect(pieces.any((piece) => piece.endsWith('\u200D')), isFalse);
  });

  test('句末標點是可選斷點，仍保留整個字素', () async {
    const content = '「你好。」👨‍👩‍👦再見。';
    final blocks = await const TextPreprocessor(useIsolate: false).process(
      ChapterText(
        id: 0,
        title: '',
        paragraphs: [content],
        displayText: content,
        contentHash: 'unicode-sentence-test',
      ),
      maxBlockChars: 5,
    );
    final pieces = blocks.blocks.map((block) => block.text).toList();
    expect(pieces.join(), content);
    expect(pieces.where((piece) => piece.contains('👨‍👩‍👦')).length, 1);
  });
}
