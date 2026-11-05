import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
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
  late AppDatabase db;
  late BookDao bookDao;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    bookDao = BookDao(db);
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
    final stored = await LocalBookService().storeInLibrary(
      source,
      bookDao: bookDao,
    );

    expect(p.dirname(stored), p.join(documents.path, 'InkpageBooks'));
    expect(p.basename(stored), '書.txt');
    await File(source).delete();
    expect(await File(stored).readAsString(), '第一章\n內容');
  });

  test('同名同內容視為同一本，同名不同內容（大小一樣也算）另取名字', () async {
    Future<String> store(String path) =>
        LocalBookService().storeInLibrary(path, bookDao: bookDao);
    final first = await store(await pick('書.txt', '甲'));
    final again = await store(await pick('書.txt', '甲'));
    final other = await store(await pick('書.txt', '乙'));

    expect(again, first);
    expect(p.basename(other), '書 (2).txt');
    expect(await File(other).readAsString(), '乙');
    expect(await store(other), other);
  });
}
