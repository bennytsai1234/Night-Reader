import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/use_cases/reader_v2_page_coordinator.dart';

void main() {
  // displayText：「第一章\n\n甲甲\n\n乙乙乙\n\n丙」，正文從 5 開始。
  final content = ReaderV2Content.fromRaw(
    chapterIndex: 0,
    title: '第一章',
    rawText: '甲甲\n乙乙乙\n\n丙',
  );

  test('the chapter title counts as the first paragraph', () {
    expect(paragraphIndexAt(content, 0), 0);
    expect(paragraphIndexAt(content, 4), 0);
  });

  test('an offset inside a paragraph or its trailing break picks it', () {
    expect(paragraphIndexAt(content, 5), 0);
    expect(paragraphIndexAt(content, 8), 0);
    expect(paragraphIndexAt(content, 9), 1);
    expect(paragraphIndexAt(content, 13), 1);
    expect(paragraphIndexAt(content, 14), 2);
  });

  test('offsets past the end stay on the last paragraph', () {
    expect(paragraphIndexAt(content, 999), 2);
  });
}
