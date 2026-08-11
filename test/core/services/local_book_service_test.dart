import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/chapter_content_preparation_pipeline.dart';
import 'package:night_reader/core/services/local_book_service.dart';

class _FakeBookSourceDao extends Fake implements BookSourceDao {}

void main() {
  late Directory tempDir;
  late File textFile;
  late Book book;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('night-reader-local-');
    textFile = File('${tempDir.path}/book.txt');
    await textFile.writeAsString('abcdef');
    book = Book(
      bookUrl: 'local://${textFile.path}',
      origin: 'local',
      charset: 'UTF-8',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('反向章節位元組範圍回報索引無效而不是拋例外', () async {
    final content = await LocalBookService().getContent(
      book,
      BookChapter(url: 'chapter/1', start: 4, end: 2),
    );

    expect(content, '本地 TXT 索引無效，請重新匯入');
  });

  test('章節起點超出檔案尾端回報索引無效', () async {
    final content = await LocalBookService().getContent(
      book,
      BookChapter(url: 'chapter/2', start: 99, end: 100),
    );

    expect(content, '本地 TXT 索引無效，請重新匯入');
  });

  test('章節終點超出檔案尾端回報索引無效', () async {
    final content = await LocalBookService().getContent(
      book,
      BookChapter(url: 'chapter/end', start: 2, end: 99),
    );

    expect(content, '本地 TXT 索引無效，請重新匯入');
  });

  test('正文管線不會把本地索引錯誤文字當成可讀正文', () async {
    final pipeline = ChapterContentPreparationPipeline(
      book: book,
      contentStore: null,
      sourceDao: _FakeBookSourceDao(),
      service: BookSourceService(),
    );

    final result = await pipeline.prepare(
      chapterIndex: 0,
      chapter: BookChapter(url: 'chapter/3', start: 4, end: 2),
    );

    expect(result.isFailed, isTrue);
    expect(result.failureMessage, '本地 TXT 索引無效，請重新匯入');
  });
}
