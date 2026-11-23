import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/ai_repair/ai_repair_apply.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AI 建立的書源存進去（ADR 0082）：加在最後、寫說明；同網址或同網站同類
/// 已有書源時不存，原本那一個不被蓋掉。
void main() {
  late AppDatabase db;
  late BookSourceDao dao;

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    db = AppDatabase.forTesting(NativeDatabase.memory());
    registerDatabase(db);
    dao = GetIt.instance<BookSourceDao>();
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  BookSource created({String url = 'https://www.site.example', int type = 0}) =>
      BookSource(
        bookSourceUrl: url,
        bookSourceName: '範例書站',
        bookSourceType: type,
        enabled: false,
      );

  test('a created source goes after the others, enabled, with a note on '
      'where it came from', () async {
    await dao.upsert(
      BookSource(
        bookSourceUrl: 'https://other.example',
        bookSourceName: '別站',
        customOrder: 7,
      ),
    );

    await saveCreatedSource(created(), 'https://www.site.example/list');

    final saved = (await dao.getByUrl('https://www.site.example'))!;
    expect(saved.bookSourceName, '範例書站');
    expect(saved.enabled, isTrue);
    expect(saved.customOrder, 8);
    expect(
      saved.bookSourceComment,
      startsWith('夜讀 AI 依 https://www.site.example/list 建立'),
    );
  });

  test('a source already there for the same site and kind is kept and the '
      'created one is not saved', () async {
    final mine = BookSource(
      bookSourceUrl: 'https://www.site.example',
      bookSourceName: '我匯入的',
      searchUrl: '/mine?q={{key}}',
    );
    await dao.upsert(mine);

    await expectLater(
      saveCreatedSource(created(), 'https://www.site.example/'),
      throwsA(isA<AiRepairConflict>()),
    );
    expect(
      (await dao.getByUrl('https://www.site.example'))!.searchUrl,
      '/mine?q={{key}}',
    );

    await expectLater(
      saveCreatedSource(
        created(url: 'https://www.site.example#2'),
        'https://www.site.example/',
      ),
      throwsA(isA<AiRepairConflict>()),
      reason: '同主機、同類',
    );
    await saveCreatedSource(
      created(url: 'https://www.site.example#audio', type: 1),
      'https://www.site.example/',
    );
    expect(
      await dao.getByUrl('https://www.site.example#audio'),
      isNotNull,
      reason: '同網站的另一類照存',
    );
  });
}
