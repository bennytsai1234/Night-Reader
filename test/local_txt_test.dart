import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/local_book/txt_parser.dart';
import 'package:night_reader/core/services/encoding_detect.dart';
import 'package:night_reader/core/services/local_book_service.dart';

final File _journeyToTheWest = File(
  '${Directory.current.path}${Platform.pathSeparator}samples${Platform.pathSeparator}西游记.txt',
);

void main() {
  setUpAll(() {
    expect(
      _journeyToTheWest.existsSync(),
      isTrue,
      reason: '整合測試需要 samples/西游记.txt fixture。',
    );
  });

  group('西遊記本地 TXT 整合測試', () {
    test('TxtParser 以 UTF-8 建立 101 個連續且完整覆蓋的位元組區段', () async {
      final result = await TxtParser(_journeyToTheWest).splitChapters();
      final bytes = await _journeyToTheWest.readAsBytes();

      expect(result.charset.toLowerCase(), 'utf-8');
      expect(result.chapters, hasLength(101));
      expect(result.chapters.first['title'], '前言');
      expect(result.chapters.first['start'], 0);
      expect(result.chapters.last['end'], bytes.length);

      for (var index = 0; index < result.chapters.length; index++) {
        final chapter = result.chapters[index];
        final start = chapter['start']! as int;
        final end = chapter['end']! as int;

        expect(start, greaterThanOrEqualTo(0), reason: '第 $index 段起點錯誤');
        expect(end, greaterThan(start), reason: '第 $index 段為空或反向');
        expect(end, lessThanOrEqualTo(bytes.length), reason: '第 $index 段超出檔案');
        if (index > 0) {
          expect(
            start,
            result.chapters[index - 1]['end'],
            reason: '第 $index 段與前段不連續',
          );
        }
      }
    });

    test('LocalBookService.importBook 保留本地書 metadata 與全部章節索引', () async {
      final imported = await LocalBookService().importBook(
        _journeyToTheWest.path,
      );

      expect(imported, isNotNull);
      final result = imported!;
      expect(result.book.bookUrl, 'local://${_journeyToTheWest.path}');
      expect(result.book.name, '西游记');
      expect(result.book.author, '本地');
      expect(result.book.origin, 'local');
      expect(result.book.originName, '本地');
      expect(result.book.isInBookshelf, isTrue);
      expect(result.book.charset?.toLowerCase(), 'utf-8');
      expect(result.chapters, hasLength(101));

      for (var index = 0; index < result.chapters.length; index++) {
        final chapter = result.chapters[index];
        expect(chapter.index, index);
        expect(chapter.url, '${result.book.bookUrl}#$index');
        expect(chapter.bookUrl, result.book.bookUrl);
        expect(chapter.start, isNotNull);
        expect(chapter.end, isNotNull);
      }
    });

    test('首中末章節的並發讀取與原始位元組解碼完全一致', () async {
      final imported = await LocalBookService().importBook(
        _journeyToTheWest.path,
      );
      expect(imported, isNotNull);
      final result = imported!;
      final chapters = result.chapters;
      final selectedIndexes = <int>[
        0,
        chapters.length ~/ 2,
        chapters.length - 1,
      ];
      final bytes = await _journeyToTheWest.readAsBytes();

      final expectedContents = <String>[
        for (final index in selectedIndexes)
          EncodingDetect.decodeWithCharset(
            bytes.sublist(chapters[index].start!, chapters[index].end!),
            result.book.charset!,
          ),
      ];
      final contents = await Future.wait<String>([
        for (final index in selectedIndexes)
          LocalBookService().getContent(result.book, chapters[index]),
      ]);

      expect(contents, expectedContents);
      for (final content in contents) {
        expect(content, isNotEmpty);
      }
    });
  });
}
