import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/local_book_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _DirPathProvider extends PathProviderPlatform {
  _DirPathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;
  late Directory picked;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('local_book_docs');
    picked = await Directory.systemTemp.createTemp('local_book_picked');
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _DirPathProvider(documents.path);
    addTearDown(() => PathProviderPlatform.instance = previous);
  });

  tearDown(() async {
    await documents.delete(recursive: true);
    await picked.delete(recursive: true);
  });

  Future<String> pick(String name, String content) async {
    final file = File(p.join(picked.path, name));
    await file.writeAsString(content);
    return file.path;
  }

  test('選到的檔案複製進 App 的本地書資料夾，原檔刪了也讀得到', () async {
    final source = await pick('書.txt', '第一章\n內容');
    final stored = await LocalBookService().storeInLibrary(source);

    expect(p.dirname(stored), p.join(documents.path, 'InkpageBooks'));
    expect(p.basename(stored), '書.txt');
    await File(source).delete();
    expect(await File(stored).readAsString(), '第一章\n內容');
  });

  test('同名同大小視為同一本，同名不同內容另取名字', () async {
    final first = await LocalBookService().storeInLibrary(
      await pick('書.txt', '甲'),
    );
    final again = await LocalBookService().storeInLibrary(
      await pick('書.txt', '甲'),
    );
    final other = await LocalBookService().storeInLibrary(
      await pick('書.txt', '乙乙'),
    );

    expect(again, first);
    expect(p.basename(other), '書 (2).txt');
    expect(await File(other).readAsString(), '乙乙');
    expect(await LocalBookService().storeInLibrary(other), other);
  });
}
