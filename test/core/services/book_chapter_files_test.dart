import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_chapter_files.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';

void main() {
  late Directory root;
  final book = Book(
    bookUrl: 'https://audio.test/book/1',
    origin: 'https://audio.test',
    name: '長夜將盡',
  );
  BookChapter chapter(int i) => BookChapter(
    url: 'https://audio.test/ep$i',
    title: '第 $i 集',
    bookUrl: book.bookUrl,
    index: i,
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('chapter_files_');
    AppStoragePaths.useRoots((
      documents: root.path,
      support: root.path,
      temporary: root.path,
    ));
  });

  tearDown(() => root.deleteSync(recursive: true));

  test(
    'a chapter counts as downloaded only once its file is complete',
    () async {
      final dir = await BookChapterFiles.dirFor(book);
      expect(dir, contains('book_assets'));
      expect(await BookChapterFiles.downloaded(book), isEmpty);

      await expectLater(
        BookChapterFiles.save(book, chapter(1), '.mp3', (partial) async {
          await partial.writeAsBytes([1, 2, 3]);
          expect(await BookChapterFiles.fileFor(book, chapter(1)), isNull);
          throw const SocketException('斷線');
        }),
        throwsA(isA<SocketException>()),
      );
      // 沒寫完的不留、不算下載好。
      expect(Directory(dir).listSync(), isEmpty);

      final saved = await BookChapterFiles.save(
        book,
        chapter(1),
        '.mp3',
        (partial) => partial.writeAsBytes([1, 2, 3, 4]),
      );
      expect(saved.path, endsWith('.mp3'));
      expect(
        (await BookChapterFiles.fileFor(book, chapter(1)))?.path,
        saved.path,
      );
      expect(await BookChapterFiles.fileFor(book, chapter(2)), isNull);
      expect(await BookChapterFiles.sizeOf(book), 4);
    },
  );

  test('clearing the downloads keeps the cover in the book folder', () async {
    await BookChapterFiles.save(
      book,
      chapter(1),
      '.m4a',
      (partial) => partial.writeAsBytes([1]),
    );
    final bookDir = Directory(await BookChapterFiles.dirFor(book)).parent;
    final cover = File('${bookDir.path}/cover-1.jpg')..writeAsBytesSync([9]);

    await BookChapterFiles.deleteFor(book);

    expect(await BookChapterFiles.downloaded(book), isEmpty);
    expect(await BookChapterFiles.sizeOf(book), 0);
    expect(cover.existsSync(), isTrue);
  });
}
