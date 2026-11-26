import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/storage/temp_files.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  final now = DateTime.now();
  const old = Duration(hours: 25);
  const fresh = Duration(hours: 23);

  setUp(() {
    root = Directory.systemTemp.createTempSync('night_reader_temp_files_');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Directory folder(String path) =>
      Directory(p.join(root.path, path))..createSync(recursive: true);

  File file(String path, {Duration age = Duration.zero}) {
    final file = File(p.join(root.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    file.setLastModifiedSync(now.subtract(age));
    return file;
  }

  test('名單內資料夾裡超過 24 小時的檔案刪掉，未滿的與資料夾本身留著', () async {
    final oldFile = file('file_picker/old.txt', age: old);
    final freshFile = file('file_picker/fresh.txt', age: fresh);
    final oldExport = file('exports/old.zip', age: old);

    await TempFiles.sweep(root: root, now: now);

    expect(oldFile.existsSync(), isFalse);
    expect(oldExport.existsSync(), isFalse);
    expect(freshFile.existsSync(), isTrue);
    expect(Directory(p.join(root.path, 'file_picker')).existsSync(), isTrue);
    expect(Directory(p.join(root.path, 'exports')).existsSync(), isTrue);
  });

  test('子資料夾整個看最新的修改時間：裡面還有新檔就留著，都舊了才刪', () async {
    final keep = folder('comic_sync/fingerprint');
    file('comic_sync/fingerprint/old.cbz', age: old);
    final recent = file('comic_sync/fingerprint/new.cbz', age: fresh);

    await TempFiles.sweep(root: root, now: now);

    expect(keep.existsSync(), isTrue);
    expect(recent.existsSync(), isTrue);

    // 資料夾自己的修改時間是建立時；把 now 往後推就變成舊資料夾。
    final older = folder('comic_import/1');
    file('comic_import/1/1.cbz');

    await TempFiles.sweep(root: root, now: now.add(old));

    expect(older.existsSync(), isFalse);
    expect(Directory(p.join(root.path, 'comic_import')).existsSync(), isTrue);
  });

  test('名單外的資料夾與根目錄零散檔完全不動', () async {
    final image = file('libCachedImageData/cover.jpg', age: old);
    final update = file('updates/night-reader.apk', age: old);
    final plugin = file('image_picker/image.jpg', age: old);
    final ruleFile = file('java.downloadFile.tmp', age: old);
    final imageDir = folder('libCachedImageData/old-folder');

    await TempFiles.sweep(root: root, now: now);

    expect(image.existsSync(), isTrue);
    expect(update.existsSync(), isTrue);
    expect(plugin.existsSync(), isTrue);
    expect(ruleFile.existsSync(), isTrue);
    expect(imageDir.existsSync(), isTrue);
  });

  test('名單內的資料夾不存在時不出錯', () async {
    await TempFiles.sweep(root: root, now: now);

    expect(root.existsSync(), isTrue);
  });
}
