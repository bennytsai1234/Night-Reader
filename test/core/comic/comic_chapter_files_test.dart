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

  String writeCbz(
    Map<String, List<int>> files, {
    String name = 'chapter.cbz',
    bool stored = false,
  }) {
    final archive = Archive();
    files.forEach((name, bytes) {
      final file = ArchiveFile.bytes(name, bytes);
      if (stored) file.compression = CompressionType.none;
      archive.add(file);
    });
    final path = p.join(temp.path, name);
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

    final chapter = await ComicChapterFiles.open(dir.path);
    final pages = chapter.pages;
    expect(pages, const [
      ComicPage(name: '2.png', width: 800, height: 600),
      ComicPage(name: '10.png', width: 800, height: 1200),
      ComicPage(name: 'noext', width: 400, height: 400),
    ]);
    expect(pages.first.aspectRatio, 0.75);
    expect(await chapter.read('10.png'), png(800, 1200));
    expect(await chapter.read('gone.png'), isNull);
  });

  test('CBZ：資料夾裡的圖一起排，跳過隱藏檔與非圖片，讀檔頭的寬高', () async {
    final path = writeCbz({
      'vol/b/1.png': png(100, 300),
      'vol/a/2.png': png(100, 200),
      'vol/a/10.png': png(100, 100),
      '__MACOSX/vol/a/._2.png': [0, 1, 2],
      'info.txt': 'hello'.codeUnits,
    });

    final chapter = await ComicChapterFiles.open(path);
    final pages = chapter.pages;
    expect(pages.map((page) => page.name), [
      'vol/a/2.png',
      'vol/a/10.png',
      'vol/b/1.png',
    ]);
    expect(pages.map((page) => page.height), [200, 100, 300]);
    expect(await chapter.read('vol/b/1.png'), png(100, 300));
    expect(await chapter.read('missing.png'), isNull);
  });

  Uint8List noise(int length, int seed) => Uint8List.fromList([
    for (var i = 0; i < length; i++) (i * 31 + seed * 7 + (i >> 3)) & 0xFF,
  ]);

  for (final stored in [true, false]) {
    test('CBZ ${stored ? '原樣存著' : 'Deflate 壓縮'}的圖：直接讀那一段，'
        '和整個解析讀到的一樣', () async {
      final files = <String, List<int>>{
        '01.png': [...png(10, 20), ...noise(5000, 1)],
        '第 2 話/02 夜.png': [...png(10, 30), ...noise(70000, 2)],
        'deep/a/b/03.png': [...png(10, 40), ...noise(10, 3)],
      };
      final path = writeCbz(files, stored: stored);
      final chapter = await ComicChapterFiles.open(path);
      for (final page in chapter.pages) {
        final bytes = await chapter.read(page.name);
        expect(bytes, files[page.name], reason: page.name);
        expect(bytes, ComicChapterFiles.readPageSync(path, page.name));
      }
    });
  }

  test('CBZ 打開後檔案換了：照新的檔讀，不用舊的位置', () async {
    final path = writeCbz({
      '1.png': [...png(10, 20), ...noise(300, 1)],
      '2.png': [...png(10, 20), ...noise(300, 2)],
    }, stored: true);
    final chapter = await ComicChapterFiles.open(path);
    final replacement = [...png(10, 20), ...noise(900, 9)];
    // 換成內容不同、長度也不同的檔（重抓這一話後重新打包）。
    writeCbz({'cover.png': png(1, 1), '2.png': replacement}, stored: true);
    expect(await chapter.read('2.png'), replacement);
    File(path).deleteSync();
    expect(await chapter.read('2.png'), isNull);
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
    expect(
      (await ComicChapterFiles.open(recorded)).pages.map((p) => p.height),
      [22, 44],
    );

    File(recorded).deleteSync();
    final partial = writeCbz({
      '1.png': png(100, 100),
      '2.png': png(100, 150),
      '3.png': png(100, 200),
      'ComicInfo.xml': info.codeUnits,
    });
    expect((await ComicChapterFiles.open(partial)).pages.map((p) => p.height), [
      100,
      150,
      200,
    ]);
  });

  test('章節不存在時丟出錯誤，不是 ZIP 的檔沒有圖', () async {
    await expectLater(
      ComicChapterFiles.open(p.join(temp.path, 'none')),
      throwsA(isA<FileSystemException>()),
    );
    final bad = File(p.join(temp.path, 'bad.cbz'))..writeAsStringSync('nope');
    expect((await ComicChapterFiles.open(bad.path)).pages, isEmpty);
  });
}
