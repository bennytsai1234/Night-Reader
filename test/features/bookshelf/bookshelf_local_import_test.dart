import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helper.dart';

class _DirPathProvider extends PathProviderPlatform {
  _DirPathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BookDao bookDao;
  late Directory documents;
  late Directory picked;
  late BookshelfProvider provider;

  setUpAll(() async {
    await GetIt.instance.reset();
    setupTestDI();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    bookDao = BookDao(db);
    GetIt.instance
      ..registerSingleton<SharedPreferences>(
        await SharedPreferences.getInstance(),
      )
      ..registerSingleton<BookDao>(bookDao)
      ..registerSingleton<BookSourceDao>(BookSourceDao(db))
      ..registerSingleton<ChapterDao>(ChapterDao(db));
    documents = await Directory.systemTemp.createTemp('bookshelf_import_docs');
    picked = await Directory.systemTemp.createTemp('bookshelf_import_picked');
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _DirPathProvider(documents.path);
    addTearDown(() => PathProviderPlatform.instance = previous);
  });

  tearDownAll(() async {
    await db.close();
    await GetIt.instance.reset();
    await documents.delete(recursive: true);
    await picked.delete(recursive: true);
  });

  setUp(() async {
    await db.delete(db.books).go();
    await db.delete(db.chapters).go();
    provider = BookshelfProvider();
  });

  tearDown(() => provider.dispose());

  Future<String> pick(String name, String content) async {
    final file = File(p.join(picked.path, name));
    await file.writeAsString(content);
    return file.path;
  }

  test('一次加入好幾個檔：其中一個匯入失敗，其他的照樣加入書架', () async {
    final first = await pick('甲.txt', '第一章 開始\n內容');
    final missing = p.join(picked.path, '乙.txt');
    final third = await pick('丙.txt', '第一章 開始\n另一本');

    final result = await provider.importLocalBookPaths([first, missing, third]);

    expect(result.added, 2);
    expect(result.failed, ['乙']);
    final shelf = await bookDao.getInBookshelf();
    expect(shelf.map((book) => book.name), containsAll(['甲', '丙']));
    expect(shelf, hasLength(2));
  });

  test('匯入結果的說法：全成功、部分失敗、全失敗', () {
    expect(localBookImportMessage(added: 1, failed: const []), '匯入成功');
    expect(localBookImportMessage(added: 3, failed: const []), '已加入 3 本');
    expect(
      localBookImportMessage(added: 2, failed: const ['乙', '丙']),
      '已加入 2 本，2 本失敗：乙、丙',
    );
    expect(
      localBookImportMessage(added: 0, failed: const ['乙', '丙']),
      '匯入失敗：乙、丙',
    );
  });
}
