import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_open_target.dart';

void main() {
  group('ReaderV2ContentLocationMapper content identity', () {
    test(
      'source title/prefix changes do not reinterpret the old absolute offset',
      () {
        final before = ReaderV2Content.fromRaw(
          chapterIndex: 3,
          title: '短標題',
          rawText: '前文前文前文\n目標句從這裡開始，後面內容保持一致。\n尾聲尾聲尾聲',
        );
        final targetText = '目標句從這裡開始';
        final oldOffset = before.displayText.indexOf(targetText);
        expect(oldOffset, greaterThan(0));
        final captured = ReaderV2ContentLocationMapper.capture(
          location: ReaderV2Location(chapterIndex: 3, charOffset: oldOffset),
          content: before,
        );

        final after = ReaderV2Content.fromRaw(
          chapterIndex: 3,
          title: '另一個來源使用非常非常長的章節標題',
          rawText: '來源站前言與廣告\n前文前文前文\n目標句從這裡開始，後面內容保持一致。\n尾聲尾聲尾聲',
        );
        final resolved = ReaderV2ContentLocationMapper.resolve(
          location: captured,
          target: after,
        );

        expect(resolved.contentHash, after.contentHash);
        expect(
          after.displayText.substring(resolved.charOffset),
          startsWith(targetText),
        );
        expect(resolved.charOffset, isNot(oldOffset));
      },
    );

    test('replacement that changes sentence boundaries maps by text identity, not sentence ordinal', () {
      final before = ReaderV2Content.fromRaw(
        chapterIndex: 1,
        title: '章名',
        rawText: '甲乙丙丁目標內容保持不變，這裡才是閱讀位置。後續文字也保持不變。',
      );
      const targetText = '目標內容保持不變';
      final oldOffset = before.displayText.indexOf(targetText);
      final captured = ReaderV2ContentLocationMapper.capture(
        location: ReaderV2Location(chapterIndex: 1, charOffset: oldOffset),
        content: before,
      );

      final after = ReaderV2Content.fromRaw(
        chapterIndex: 1,
        title: '章名',
        rawText: '甲。乙。丙。丁。目標內容保持不變，這裡才是閱讀位置。後續文字也保持不變。',
      );
      final resolved = ReaderV2ContentLocationMapper.resolve(
        location: captured,
        target: after,
      );

      expect(
        after.displayText.substring(resolved.charOffset),
        startsWith(targetText),
      );
    });

    test('legacy location without identity remains a backwards-compatible scalar offset', () {
      final target = ReaderV2Content.fromRaw(
        chapterIndex: 0,
        title: '章',
        rawText: 'abcdefghijklmnopqrstuvwxyz',
      );
      const legacy = ReaderV2Location(chapterIndex: 0, charOffset: 7);

      final resolved = ReaderV2ContentLocationMapper.resolve(
        location: legacy,
        target: target,
      );

      expect(resolved.charOffset, 7);
      expect(resolved.contentHash, target.contentHash);
    });

    test('persisted context radius never cuts a surrogate pair in half', () {
      final before = List<String>.filled(10, 'a').join();
      final leftContext = List<String>.filled(47, 'b').join();
      final rightContext = List<String>.filled(47, 'c').join();
      final after = List<String>.filled(20, 'd').join();
      final content = ReaderV2Content.fromRaw(
        chapterIndex: 0,
        title: '',
        rawText: '$before😀$leftContext$rightContext😀$after',
      );
      // UTF-16 geometry:
      // 10 ASCII + 😀(2) + 47 = 59. With a 48-code-unit radius, the raw
      // left boundary would be 11 (inside the first surrogate pair), while
      // the raw right boundary would be 107 (inside the second pair).
      final captured = ReaderV2ContentLocationMapper.capture(
        location: const ReaderV2Location(chapterIndex: 0, charOffset: 59),
        content: content,
      );

      expect(captured.anchorBefore, leftContext);
      expect(captured.anchorAfter, rightContext);
      expect(captured.charOffset, 59);
      expect(jsonDecode(jsonEncode(captured.toJson())), isA<Map>());
    });

    test('source migration rewrites chapter ownership but preserves the text anchor', () {
      final oldBook = Book(
        bookUrl: 'old',
        origin: 'source-a',
        chapterIndex: 2,
        charOffset: 42,
        visualOffsetPx: 8,
        durChapterTitle: '第三章',
        totalChapterNum: 3,
        readerAnchorJson: jsonEncode(
          const ReaderV2Location(
            chapterIndex: 2,
            charOffset: 42,
            visualOffsetPx: 8,
            contentHash: 'old-content',
            contentLength: 180,
            anchorBefore: '閱讀位置前文',
            anchorAfter: '閱讀位置後文',
          ).toJson(),
        ),
      );
      final migrated = oldBook.migrateTo(
        Book(bookUrl: 'new', origin: 'source-b'),
        <BookChapter>[
          BookChapter(title: '第一章'),
          BookChapter(title: '第三章'),
          BookChapter(title: '第五章'),
        ],
      );

      expect(migrated.chapterIndex, 1);
      expect(migrated.charOffset, 42);
      final resumed = ReaderV2OpenTarget.resume(migrated).location;
      expect(resumed.chapterIndex, 1);
      expect(resumed.charOffset, 42);
      expect(resumed.contentHash, 'old-content');
      expect(resumed.anchorBefore, '閱讀位置前文');
      expect(resumed.anchorAfter, '閱讀位置後文');
    });

    test('source migration resets a legacy scalar address with no content identity', () {
      final oldBook = Book(
        bookUrl: 'old',
        origin: 'source-a',
        chapterIndex: 2,
        charOffset: 42,
        visualOffsetPx: 8,
        durChapterTitle: '第三章',
        totalChapterNum: 3,
      );

      final migrated = oldBook.migrateTo(
        Book(bookUrl: 'new', origin: 'source-b'),
        <BookChapter>[
          BookChapter(title: '第一章'),
          BookChapter(title: '第三章'),
          BookChapter(title: '第五章'),
        ],
      );

      expect(migrated.chapterIndex, 1);
      expect(migrated.charOffset, 0);
      expect(migrated.visualOffsetPx, 0);
      expect(migrated.readerAnchorJson, isNull);
    });
  });
}
