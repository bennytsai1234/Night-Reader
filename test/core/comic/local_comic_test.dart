import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/comic/comic_chapter_files.dart';
import 'package:night_reader/core/comic/local_comic_library.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/core/comic/local_comic_service.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:path/path.dart' as p;

import '../../features/comic_reader/comic_test_pages.dart';

Future<R> _direct<R>(FutureOr<R> Function() work) async => work();

void main() {
  late Directory root;
  late Directory picked;

  setUp(() {
    root = Directory.systemTemp.createTempSync('local_comic_');
    AppStoragePaths.useRoots((
      documents: p.join(root.path, 'docs'),
      support: p.join(root.path, 'support'),
      temporary: p.join(root.path, 'tmp'),
    ));
    picked = Directory(p.join(root.path, 'picked', '夜行'))
      ..createSync(recursive: true);
  });
  tearDown(() => root.deleteSync(recursive: true));

  void imageFolder(String name, List<int> heights) {
    final dir = Directory(p.join(picked.path, name))..createSync();
    for (final (i, h) in heights.indexed) {
      File(p.join(dir.path, '${i + 1}.png'))
          .writeAsBytesSync(stripedPng(4, h, 0x112233, 0x445566));
    }
  }

  void cbz(String name, List<int> heights) {
    final archive = Archive();
    for (final (i, h) in heights.indexed) {
      archive.add(
        ArchiveFile.bytes(
          'p${i + 1}.png',
          stripedPng(4, h, 0x112233, 0x445566),
        ),
      );
    }
    File(p.join(picked.path, name))
        .writeAsBytesSync(ZipEncoder().encode(archive));
  }

  test('作品資料夾：CBZ 與圖片資料夾各是一話，照名稱自然排序', () {
    cbz('第10話.cbz', [4]);
    imageFolder('第2話', [5, 6]);
    imageFolder('空資料夾', []);
    File(p.join(picked.path, '說明.txt')).writeAsStringSync('x');
    expect(LocalComicLibrary.discover(picked.path).map((s) => s.title), [
      '第2話',
      '第10話',
    ]);
  });

  test('資料夾直接放圖時整個資料夾是一話', () {
    File(p.join(picked.path, '1.png')).writeAsBytesSync(stripedPng(4, 4, 0, 0));
    expect(LocalComicLibrary.discover(picked.path).map((s) => s.title), ['夜行']);
  });

  test('沒有副檔名的圖照內容認（同 Mihon）：資料夾裡的圖與直接放的圖都算', () {
    final chapter = Directory(p.join(picked.path, '第1話'))..createSync();
    File(p.join(chapter.path, '001')).writeAsBytesSync(stripedPng(4, 4, 0, 0));
    final notes = Directory(p.join(picked.path, '只有說明'))..createSync();
    File(p.join(notes.path, 'README')).writeAsStringSync('x');
    expect(LocalComicLibrary.discover(picked.path).map((s) => s.title), [
      '第1話',
    ]);

    // JPEG 的寬高常在檔頭 64 個位元組之後（前面是 EXIF 這類資料）。
    final jpeg = Directory(p.join(picked.path, '第2話'))..createSync();
    File(p.join(jpeg.path, '001')).writeAsBytesSync([
      0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0xA0, //
      ...List.filled(0xA0, 0),
    ]);
    expect(LocalComicLibrary.discover(picked.path).map((s) => s.title), [
      '第1話',
      '第2話',
    ]);

    final loose = Directory(p.join(root.path, 'picked', '散圖'))..createSync();
    File(p.join(loose.path, '002')).writeAsBytesSync(stripedPng(4, 4, 0, 0));
    expect(LocalComicLibrary.discover(loose.path).map((s) => s.title), ['散圖']);
  });

  test('章指紋只看圖：同樣的圖放在 CBZ 或資料夾都一樣', () {
    imageFolder('第1話', [5, 6]);
    cbz('第1話.cbz', [5, 6]);
    cbz('第2話.cbz', [5, 7]);
    final folder = LocalComicLibrary.fingerprintOf(p.join(picked.path, '第1話'));
    expect(
      LocalComicLibrary.fingerprintOf(p.join(picked.path, '第1話.cbz')),
      folder,
    );
    expect(
      LocalComicLibrary.fingerprintOf(p.join(picked.path, '第2話.cbz')),
      isNot(folder),
    );
  });

  group('LocalComicService', () {
    late AppDatabase db;
    late LocalComicService service;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      service = LocalComicService(
        bookDao: BookDao(db),
        chapterDao: ChapterDao(db),
        run: _direct,
      );
    });
    tearDown(() => db.close());

    test('匯入作品資料夾：一本漫畫、每話一個 CBZ、讀得到圖', () async {
      imageFolder('第1話', [5, 6]);
      cbz('第2話.cbz', [7]);
      final progress = <int>[];
      final book = await service.importPath(
        picked.path,
        onProgress: (done, _) => progress.add(done),
      );

      expect(book, isNotNull);
      expect(book!.name, '夜行');
      expect(book.bookKind, BookSourceKind.comic);
      expect(book.isLocal, isTrue);
      expect(progress, [1, 2]);
      final chapters = await ChapterDao(db).getByBook(book.bookUrl);
      expect(chapters.map((c) => c.title), ['第1話', '第2話']);
      expect(book.fileFingerprint, chapters.first.url);
      final first = LocalComicService.chapterPathOf(book, chapters.first);
      expect(
        (await ComicChapterFiles.open(first)).pages.map((page) => page.height),
        [5, 6],
      );
    });

    test('之後補上新的一話：併進同一本，已有的話不重複存', () async {
      imageFolder('第1話', [5]);
      final first = await service.importPath(picked.path);
      imageFolder('第2話', [6]);
      final again = await service.importPath(picked.path);

      expect(again!.bookUrl, first!.bookUrl);
      final chapters = await ChapterDao(db).getByBook(first.bookUrl);
      expect(chapters.map((c) => c.title), ['第1話', '第2話']);
      expect((await BookDao(db).getInBookshelf()), hasLength(1));
      expect(
        Directory(p.join(first.bookUrl.replaceFirst('local://', '')))
            .listSync()
            .whereType<File>()
            .length,
        2,
      );
    });

    test('補進更前面的一話：讀到的那一話與第幾張不變', () async {
      imageFolder('第2話', [6]);
      imageFolder('第3話', [7]);
      final first = await service.importPath(picked.path);
      await BookDao(db).updateProgress(first!.bookUrl, 1, '第3話', 4);
      imageFolder('第1話', [5]);
      final again = await service.importPath(picked.path);

      final book = (await BookDao(db).getByUrl(again!.bookUrl))!;
      final chapters = await ChapterDao(db).getByBook(book.bookUrl);
      expect(chapters.map((c) => c.title), ['第1話', '第2話', '第3話']);
      expect(chapters[book.chapterIndex].title, '第3話');
      expect(book.charOffset, 4);
    });

    test('同一話補上漏掉的頁重新匯入：換成新的那份，不並存', () async {
      imageFolder('第2話', [7]);
      // 舊版匯入時漏了沒有副檔名的圖：這一話只有一張有副檔名的。
      final chapter = Directory(p.join(picked.path, '第1話'))..createSync();
      File(p.join(chapter.path, '002.png'))
          .writeAsBytesSync(stripedPng(4, 6, 0x112233, 0x445566));
      final first = await service.importPath(picked.path);

      File(p.join(chapter.path, '001'))
          .writeAsBytesSync(stripedPng(4, 5, 0x112233, 0x445566));
      final again = await service.importPath(picked.path);

      expect(again!.bookUrl, first!.bookUrl);
      final chapters = await ChapterDao(db).getByBook(first.bookUrl);
      expect(chapters.map((c) => c.title), ['第1話', '第2話']);
      // 書的資料夾裡只剩兩話的兩個 CBZ，舊的缺頁那份刪掉了。
      expect(
        Directory(first.bookUrl.replaceFirst('local://', ''))
            .listSync()
            .whereType<File>(),
        hasLength(2),
      );
      final pages = await ComicChapterFiles.open(
        LocalComicService.chapterPathOf(first, chapters.first),
      );
      expect(pages.pages.map((page) => page.height), [5, 6]);
    });

    test('換掉正在讀的那一話時，進度留在同一話', () async {
      imageFolder('第1話', [5]);
      imageFolder('第2話', [6]);
      final first = await service.importPath(picked.path);
      await BookDao(db).updateProgress(first!.bookUrl, 0, '第1話', 0);

      File(p.join(picked.path, '第1話', '2.png'))
          .writeAsBytesSync(stripedPng(4, 7, 0x112233, 0x445566));
      await service.importPath(picked.path);

      final book = (await BookDao(db).getByUrl(first.bookUrl))!;
      final chapters = await ChapterDao(db).getByBook(book.bookUrl);
      expect(chapters[book.chapterIndex].title, '第1話');
    });

    test('同步下載的章不照章名換掉同名的一話', () async {
      imageFolder('番外', [5]);
      final first = await service.importPath(picked.path);
      final printA = (await ChapterDao(db).getByBook(first!.bookUrl))
          .single
          .url;

      // 雲端這本的另一話也叫「番外」、內容不同：下載下來要新增，不是換掉
      // 舊的那一話（同步的章名可以重複）。
      final staging = Directory(p.join(root.path, 'staging'))..createSync();
      final archive = Archive()
        ..add(
          ArchiveFile.bytes('p1.png', stripedPng(4, 9, 0x112233, 0x445566)),
        );
      File(p.join(staging.path, '00001.cbz'))
          .writeAsBytesSync(ZipEncoder().encode(archive));
      final printB = LocalComicLibrary.fingerprintOf(
        p.join(staging.path, '00001.cbz'),
      );
      await service.importPath(
        staging.path,
        name: first.name,
        related: {printA},
        titles: {printB: '番外'},
        fingerprint: printA,
      );

      final chapters = await ChapterDao(db).getByBook(first.bookUrl);
      expect(chapters.map((c) => c.title), ['番外', '番外']);
      expect(chapters.map((c) => c.url), containsAll([printA, printB]));
    });

    test('單一個 CBZ 是只有一話的書；沒有圖的不匯入', () async {
      cbz('短篇.cbz', [5]);
      final book = await service.importPath(p.join(picked.path, '短篇.cbz'));
      expect(book!.name, '短篇');
      expect(await ChapterDao(db).getByBook(book.bookUrl), hasLength(1));

      final empty = Directory(p.join(root.path, '空的'))..createSync();
      expect(await service.importPath(empty.path), isNull);
    });
  });
}
