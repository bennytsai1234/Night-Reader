import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/comic/comic_chapter_files.dart';
import 'package:path/path.dart' as p;

/// 只有 PNG 檔頭（簽章加 IHDR）的圖，讀得出寬高就夠了。
Uint8List png(int width, int height) {
  final bytes = ByteData(33);
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < signature.length; i++) {
    bytes.setUint8(i, signature[i]);
  }
  bytes.setUint32(8, 13);
  for (final (i, c) in 'IHDR'.codeUnits.indexed) {
    bytes.setUint8(12 + i, c);
  }
  bytes.setUint32(16, width);
  bytes.setUint32(20, height);
  return bytes.buffer.asUint8List();
}

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('comic-files-'));
  tearDown(() => temp.deleteSync(recursive: true));

  String writeCbz(Map<String, List<int>> files) {
    final archive = Archive();
    files.forEach((name, bytes) => archive.add(ArchiveFile.bytes(name, bytes)));
    final path = p.join(temp.path, 'chapter.cbz');
    File(path).writeAsBytesSync(ZipEncoder().encode(archive));
    return path;
  }

  test('自然排序：數字照數值、不分大小寫', () {
    final names = ['10.jpg', '2.jpg', 'P1.jpg', 'p01b.jpg', '1.jpg', '002.png']
      ..sort(ComicChapterFiles.compareNatural);
    // 數值相同時照後面的字比：`2.jpg` 在 `002.png` 前面。
    expect(names, [
      '1.jpg',
      '2.jpg',
      '002.png',
      '10.jpg',
      'P1.jpg',
      'p01b.jpg',
    ]);
  });

  test('圖片資料夾：只收圖片、照名稱排、讀得出寬高', () async {
    final dir = Directory(p.join(temp.path, 'ch'))..createSync();
    File(p.join(dir.path, '10.png')).writeAsBytesSync(png(800, 1200));
    File(p.join(dir.path, '2.png')).writeAsBytesSync(png(800, 600));
    File(p.join(dir.path, 'noext')).writeAsBytesSync(png(400, 400));
    File(p.join(dir.path, 'notes.txt')).writeAsStringSync('x');
    File(p.join(dir.path, '.hidden.png')).writeAsBytesSync(png(1, 1));

    final pages = await ComicChapterFiles.pagesOf(dir.path);
    expect(pages, const [
      ComicPage(name: '2.png', width: 800, height: 600),
      ComicPage(name: '10.png', width: 800, height: 1200),
      ComicPage(name: 'noext', width: 400, height: 400),
    ]);
    expect(pages.first.aspectRatio, 0.75);
    expect(
      await ComicChapterFiles.readPage(dir.path, '10.png'),
      png(800, 1200),
    );
    expect(await ComicChapterFiles.readPage(dir.path, 'gone.png'), isNull);
  });

  test('CBZ：資料夾裡的圖一起排，跳過隱藏檔與非圖片，讀檔頭的寬高', () async {
    final path = writeCbz({
      'vol/b/1.png': png(100, 300),
      'vol/a/2.png': png(100, 200),
      'vol/a/10.png': png(100, 100),
      '__MACOSX/vol/a/._2.png': [0, 1, 2],
      'info.txt': 'hello'.codeUnits,
    });

    final pages = await ComicChapterFiles.pagesOf(path);
    expect(pages.map((page) => page.name), [
      'vol/a/2.png',
      'vol/a/10.png',
      'vol/b/1.png',
    ]);
    expect(pages.map((page) => page.height), [200, 100, 300]);
    expect(
      await ComicChapterFiles.readPage(path, 'vol/b/1.png'),
      png(100, 300),
    );
    expect(await ComicChapterFiles.readPage(path, 'missing.png'), isNull);
  });

  test('CBZ 的 ComicInfo.xml 記齊寬高時直接用，沒記齊時讀檔頭', () async {
    const info = '''<?xml version="1.0" encoding="utf-8"?>
<ComicInfo><Pages>
  <Page Image="0" ImageWidth="11" ImageHeight="22" />
  <Page Image="1" ImageWidth="33" ImageHeight="44" />
</Pages></ComicInfo>''';
    final recorded = writeCbz({
      '1.png': png(100, 100),
      '2.png': png(100, 100),
      'ComicInfo.xml': info.codeUnits,
    });
    expect((await ComicChapterFiles.pagesOf(recorded)).map((p) => p.height), [
      22,
      44,
    ]);

    File(recorded).deleteSync();
    final partial = writeCbz({
      '1.png': png(100, 100),
      '2.png': png(100, 150),
      '3.png': png(100, 200),
      'ComicInfo.xml': info.codeUnits,
    });
    expect((await ComicChapterFiles.pagesOf(partial)).map((p) => p.height), [
      100,
      150,
      200,
    ]);
  });

  test('章節不存在時丟出錯誤，不是 ZIP 的檔沒有圖', () async {
    await expectLater(
      ComicChapterFiles.pagesOf(p.join(temp.path, 'none')),
      throwsA(isA<FileSystemException>()),
    );
    final bad = File(p.join(temp.path, 'bad.cbz'))..writeAsStringSync('nope');
    expect(await ComicChapterFiles.pagesOf(bad.path), isEmpty);
  });
}
