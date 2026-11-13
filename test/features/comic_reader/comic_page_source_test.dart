import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/comic_reader/comic_page_source.dart';
import 'package:path/path.dart' as p;

import 'comic_test_pages.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('comic-source-'));
  tearDown(() => temp.deleteSync(recursive: true));

  void writeCbz(String path, Map<String, List<int>> files) {
    final archive = Archive();
    files.forEach((name, bytes) {
      archive.add(
        ArchiveFile.bytes(name, bytes)..compression = CompressionType.none,
      );
    });
    File(path).writeAsBytesSync(ZipEncoder().encode(archive));
  }

  test('打開一次讀每一張；重新列清單時照現在的檔重新打開', () async {
    final path = p.join(temp.path, '1.cbz');
    final first = stripedPng(4, 6, 0x112233, 0x445566);
    final second = stripedPng(4, 8, 0x778899, 0x223344);
    writeCbz(path, {'0001.png': first, '0002.png': second});
    var opens = 0;
    final source = ComicChapterFilesSource((_) async {
      opens += 1;
      return path;
    });

    final pages = await source.pagesOf(0);
    expect(pages.map((page) => page.name), ['0001.png', '0002.png']);
    expect(await source.bytesOf(0, pages[0]), first);
    expect(await source.bytesOf(0, pages[1]), second);
    expect(opens, 1);

    // 換成另一個檔（重抓、重新匯入）後列清單：拿到新的圖。
    final replacement = stripedPng(4, 10, 0x000000, 0xFFFFFF);
    writeCbz(path, {'0001.png': replacement});
    final again = await source.pagesOf(0);
    expect(again.map((page) => page.height), [10]);
    expect(await source.bytesOf(0, again[0]), replacement);
    expect(opens, 2);
  });

  test('打不開的一話不留著，下次重新打開', () async {
    final path = p.join(temp.path, 'missing.cbz');
    final source = ComicChapterFilesSource((_) async => path);
    await expectLater(source.pagesOf(0), throwsA(isA<FileSystemException>()));
    writeCbz(path, {'0001.png': stripedPng(2, 2, 0, 0)});
    expect(await source.pagesOf(0), hasLength(1));
  });
}
