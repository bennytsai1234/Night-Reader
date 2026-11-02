import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/bookmark.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/features/bookmark/reader_v2_bookmarks.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

void main() {
  List<BookChapter> toc(List<String> titles) => [
    for (final (index, title) in titles.indexed)
      BookChapter(url: '/c/$index', title: title, index: index),
  ];

  Bookmark mark({int chapterIndex = 2, String chapterTitle = '第三章'}) =>
      Bookmark(
        id: 1,
        bookName: '書',
        chapterIndex: chapterIndex,
        chapterTitle: chapterTitle,
        charOffset: 5,
      );

  group('which chapter a bookmark is in on this phone', () {
    test('found by its chapter title even when the number moved', () {
      expect(
        ReaderV2Bookmarks.chapterIndexIn(
          mark(),
          toc(['楔子', '第一章', '第二章', '第三章']),
        ),
        3,
      );
    });

    test('a title written in simplified Chinese still matches', () {
      expect(
        ReaderV2Bookmarks.chapterIndexIn(
          mark(chapterTitle: '第三章 松煙墨'),
          toc(['第一章', '第二章', '第三章 松烟墨']),
        ),
        2,
      );
    });

    test('without the chapter list it keeps the stored number', () {
      expect(ReaderV2Bookmarks.chapterIndexIn(mark(), const []), 2);
    });
  });

  test(
    'jumping back finds the same sentence after the chapter text changed',
    () {
      const before = '第三章\n\n雨是從傍晚開始下的。沈知秋撐著一把舊油紙傘。';
      final captured = const ReaderV2Location(
        chapterIndex: 2,
        charOffset: 15,
      ).withContentIdentity(contentHash: 'old', displayText: before);
      final bookmark = Bookmark(
        id: 1,
        bookName: '書',
        chapterIndex: 2,
        chapterTitle: '第三章',
        charOffset: 15,
        anchor: jsonEncode(captured.toJson()),
      );

      final location = ReaderV2Bookmarks.locationOf(bookmark, chapterIndex: 4);
      expect(location.chapterIndex, 4, reason: '章節序號用這台目錄的');

      // 新書源在前面多了一段字。
      const after = '第三章\n\n（本章由某站提供）\n\n雨是從傍晚開始下的。沈知秋撐著一把舊油紙傘。';
      final offset = ReaderV2ContentLocationMapper.offsetIn(
        location: location,
        displayText: after,
        contentHash: 'new',
      );
      expect(after.substring(offset), startsWith(before.substring(15)));
    },
  );
}
