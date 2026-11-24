import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source_check/check_source_service.dart';
import 'package:night_reader/core/source_check/source_check_isolate.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 校驗寫回結果時，書源在校驗途中被別處改了或刪了（發現頁的編輯、刪除，
/// 書籍詳情的書源編輯器）：照現在的那一份只寫校驗管的欄位，刪掉的不寫回來。
void main() {
  const a = 'https://a.example';
  const b = 'https://b.example';
  late AppDatabase db;
  late BookSourceDao dao;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = BookSourceDao(db);
    GetIt.instance.registerSingleton<BookSourceDao>(dao);
    await dao.upsert(BookSource(bookSourceUrl: a, bookSourceName: '甲'));
    await dao.upsert(
      BookSource(bookSourceUrl: b, bookSourceName: '乙', bookSourceType: 0),
    );
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  /// 校驗出搜尋失效、正文看起來是漫畫（改寫類型），和真的校驗一樣帶著
  /// 開始時那一份書源的其他欄位。
  SourceCheckIsolateResult broken(BookSource source) {
    final checked = BookSource.fromJson(source.toJson())
      ..removeInvalidGroups()
      ..removeErrorComment()
      ..addHealthGroups(
        const SourceRuntimeHealth(
          category: SourceHealthCategory.searchBroken,
          label: searchBrokenSourceGroupTag,
          description: '搜尋規則已失效',
          allowsSearch: false,
          allowsReading: true,
          cleanupCandidate: false,
          quarantined: false,
        ),
      )
      ..addErrorComment('搜尋連結規則為空')
      ..bookSourceType = 2
      ..lastUpdateTime = 99;
    return SourceCheckIsolateResult(
      stage: 'search',
      message: '搜尋連結規則為空',
      isHealthy: false,
      updatedSourceJson: checked.toJson(),
      logs: const [],
    );
  }

  test('a source deleted or edited during the check stays the way it was '
      'left, with only the check marks written', () async {
    final releaseB = Completer<void>();
    final aDone = Completer<void>();
    final service = CheckSourceService(
      sourceDao: dao,
      spawn: (source, config, timeout) async => SourceCheckIsolateHandle(
        result: source.bookSourceUrl == a
            ? Future.value(broken(source)).whenComplete(aDone.complete)
            : releaseB.future.then((_) => broken(source)),
        abort: () {},
      ),
    );
    addTearDown(service.dispose);

    final run = service.check([a, b]);
    await aDone.future;
    // 甲的結果已經收到、還沒寫進資料庫；乙還在校驗。
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await dao.deleteByUrls([a]);
    await dao.upsert(
      (await dao.getByUrl(b))!
        ..bookSourceName = '乙（改過）'
        ..bookSourceGroup = '精選',
    );
    releaseB.complete();
    await run;

    expect(await dao.getByUrl(a), isNull);
    final saved = (await dao.getByUrl(b))!;
    expect(saved.bookSourceName, '乙（改過）');
    expect(saved.hasGroupTag('精選'), isTrue);
    expect(saved.hasGroupTag(searchBrokenSourceGroupTag), isTrue);
    expect(saved.errorComment, '搜尋連結規則為空');
    expect(saved.bookSourceType, 2);
    expect(saved.lastCheckTime, greaterThan(0));
  });
}
