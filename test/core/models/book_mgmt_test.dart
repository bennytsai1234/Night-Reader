import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_group.dart';
import 'package:night_reader/core/models/bookmark.dart';
import 'package:night_reader/core/models/book_progress.dart';
import 'package:night_reader/core/models/read_record.dart';

void main() {
  group('Book Management Models Tests', () {
    test('BookGroup serialization', () {
      final group = BookGroup(groupId: 101, groupName: 'Fantasy');
      final json = group.toJson();
      final fromJson = BookGroup.fromJson(json);
      expect(fromJson.groupId, 101);
      expect(fromJson.groupName, 'Fantasy');
    });

    test('Bookmark serialization', () {
      final bookmark = Bookmark(
        time: 123456,
        bookName: 'Book A',
        chapterName: 'Ch 1',
      );
      final json = bookmark.toJson();
      final fromJson = Bookmark.fromJson(json);
      expect(fromJson.time, 123456);
      expect(fromJson.bookName, 'Book A');
    });

    test('BookProgress serialization', () {
      final progress = BookProgress(
        name: 'Book B',
        author: 'Author B',
        chapterIndex: 5,
        charOffset: 100,
        visualOffsetPx: 18.5,
        durChapterTime: 999,
        durChapterTitle: 'Chapter 5',
      );
      final json = progress.toJson();
      final fromJson = BookProgress.fromJson(json);
      expect(fromJson.name, 'Book B');
      expect(fromJson.chapterIndex, 5);
      expect(fromJson.visualOffsetPx, 18.5);
    });

    test('Book progress coordinate json uses ReaderLocation triple', () {
      final book = Book.fromJson({
        'bookUrl': 'book',
        'name': 'Book B',
        'chapterIndex': 5,
        'charOffset': 100,
        'visualOffsetPx': 24.5,
      });

      expect(book.chapterIndex, 5);
      expect(book.charOffset, 100);
      expect(book.visualOffsetPx, 24.5);
      expect(book.toJson()['chapterIndex'], 5);
      expect(book.toJson()['charOffset'], 100);
      expect(book.toJson()['visualOffsetPx'], 24.5);
    });

    test('ReadRecord serialization', () {
      final record = ReadRecord(
        deviceId: 'dev1',
        bookName: 'Book C',
        readTime: 3600,
      );
      final json = record.toJson();
      final fromJson = ReadRecord.fromJson(json);
      expect(fromJson.deviceId, 'dev1');
      expect(fromJson.readTime, 3600);
    });
  });
}
