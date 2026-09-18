import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/local_book_service.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/text/text_preprocessor.dart';

final File _journeyToTheWest = File(
  '${Directory.current.path}${Platform.pathSeparator}samples${Platform.pathSeparator}西游记.txt',
);

bool _isUtf16Boundary(String text, int offset) {
  if (offset <= 0 || offset >= text.length) return true;
  final previous = text.codeUnitAt(offset - 1);
  final next = text.codeUnitAt(offset);
  return !(previous >= 0xD800 &&
      previous <= 0xDBFF &&
      next >= 0xDC00 &&
      next <= 0xDFFF);
}

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

  test('西遊記章節在 ReaderV2 文字管線保有完整 UTF-16 block ranges', () async {
    expect(
      _journeyToTheWest.existsSync(),
      isTrue,
      reason: '整合測試需要 samples/西游记.txt fixture。',
    );
    final imported = await LocalBookService().importBook(
      _journeyToTheWest.path,
    );
    expect(imported, isNotNull);
    final result = imported!;
    final selectedIndexes = <int>[
      0,
      result.chapters.length ~/ 2,
      result.chapters.length - 1,
    ];
    final rawContents = await Future.wait<String>([
      for (final index in selectedIndexes)
        LocalBookService().getContent(result.book, result.chapters[index]),
    ]);
    final contents = <ReaderV2Content>[
      for (var i = 0; i < selectedIndexes.length; i += 1)
        ReaderV2Content.fromRaw(
          chapterIndex: selectedIndexes[i],
          title: result.chapters[selectedIndexes[i]].title,
          rawText: rawContents[i],
        ),
    ];
    final chapterBlocks = await Future.wait<ChapterBlocks>([
      for (final content in contents)
        const TextPreprocessor().process(
          ChapterText(
            id: content.chapterIndex,
            title: content.title,
            paragraphs: content.paragraphs,
            displayText: content.displayText,
            contentHash: content.contentHash,
          ),
          maxBlockChars: 1024,
        ),
    ]);

    for (var i = 0; i < contents.length; i += 1) {
      final content = contents[i];
      final blocks = chapterBlocks[i];
      final displayText = content.displayText;

      expect(blocks.chapterIndex, content.chapterIndex);
      expect(blocks.displayText, displayText);
      expect(blocks.blocks.length, greaterThan(1));
      expect(
        blocks.blocks.map((block) => block.text).join(),
        '${content.title}${content.paragraphs.join()}',
      );

      var previousEnd = 0;
      for (
        var blockIndex = 0;
        blockIndex < blocks.blocks.length;
        blockIndex += 1
      ) {
        final block = blocks.blocks[blockIndex];
        final range = block.charRange;

        expect(block.key.chapterIndex, content.chapterIndex);
        expect(block.key.blockIndex, blockIndex);
        expect(range.start, greaterThanOrEqualTo(previousEnd));
        expect(range.end, greaterThan(range.start));
        expect(range.end, lessThanOrEqualTo(displayText.length));
        expect(_isUtf16Boundary(displayText, range.start), isTrue);
        expect(_isUtf16Boundary(displayText, range.end), isTrue);
        expect(displayText.substring(range.start, range.end), block.text);
        previousEnd = range.end;
      }
    }
  });
}
