import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/reading/bookmark.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/features/reader/chapter/reader_content.dart';
import 'package:night_reader/features/reader/features/bookmark/reader_bookmarks.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';

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
        ReaderBookmarks.chapterIndexIn(
          mark(),
          toc(['楔子', '第一章', '第二章', '第三章']),
          reversed: false,
        ),
        3,
      );
    });

    test('a title written in simplified Chinese still matches', () {
      expect(
        ReaderBookmarks.chapterIndexIn(
          mark(chapterTitle: '第三章 松煙墨'),
          toc(['第一章', '第二章', '第三章 松烟墨']),
          reversed: false,
        ),
        2,
      );
    });

    test('without the chapter list it keeps the stored number', () {
      expect(
        ReaderBookmarks.chapterIndexIn(mark(), const [], reversed: false),
        2,
      );
    });

    group('the TOC reversed since (ADR 0085)', () {
      // 兩個同名的「番外」只能靠序號分。
      const titles = ['第一章', '番外', '第二章', '番外', '第三章'];
      Bookmark twin({required int index, bool? tocReversed}) => Bookmark(
        id: 1,
        bookName: '書',
        chapterIndex: index,
        chapterTitle: '番外',
        tocReversed: tocReversed,
      );

      test('counted in the other direction: counted from the other end, '
          'landing on the same 番外', () {
        final reversed = toc(titles.reversed.toList());
        expect(
          ReaderBookmarks.chapterIndexIn(
            twin(index: 3, tocReversed: false),
            reversed,
            reversed: true,
          ),
          1,
        );
        expect(
          ReaderBookmarks.chapterIndexIn(
            twin(index: 1, tocReversed: true),
            toc(titles),
            reversed: false,
          ),
          3,
        );
      });

      test('no direction recorded (older versions, Legado) counts as the '
          'book’s own', () {
        expect(
          ReaderBookmarks.chapterIndexIn(
            twin(index: 3),
            toc(titles.reversed.toList()),
            reversed: true,
          ),
          3,
        );
      });

      test('new chapters appended after a mark in a reversed book still find '
          'the same 番外', () {
        final grown = toc([...titles, '第四章', '番外', '第五章']);
        expect(
          ReaderBookmarks.chapterIndexIn(
            twin(index: 3, tocReversed: true),
            grown,
            reversed: true,
          ),
          3,
        );
      });
    });
  });

  test(
    'jumping back finds the same sentence after the chapter text changed',
    () {
      const before = '第三章\n\n雨是從傍晚開始下的。沈知秋撐著一把舊油紙傘。';
      final captured = const ReaderLocation(
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

      final location = ReaderBookmarks.locationOf(bookmark, chapterIndex: 4);
      expect(location.chapterIndex, 4, reason: '章節序號用這台目錄的');

      // 新書源在前面多了一段字。
      const after = '第三章\n\n（本章由某站提供）\n\n雨是從傍晚開始下的。沈知秋撐著一把舊油紙傘。';
      final offset = ReaderContentLocationMapper.offsetIn(
        location: location,
        displayText: after,
        contentHash: 'new',
      );
      expect(after.substring(offset), startsWith(before.substring(15)));
    },
  );
}
