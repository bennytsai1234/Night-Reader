import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/ai_find_dao.dart';
import 'package:night_reader/core/models/search/ai_find_record.dart';

void main() {
  late AppDatabase db;
  late AiFindDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = AiFindDao(db);
  });

  tearDown(() => db.close());

  AiFindRecord find(String id) => AiFindRecord(
    id: id,
    description: id,
    depth: 'normal',
    createdAt: DateTime(2026, 11, 20).millisecondsSinceEpoch,
    outcome: AiFindOutcome.found,
  );

  /// 寫入提交後資料層在背景重讀，等它讀完。
  Future<List<String>?> latestIds() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return dao.latestNewestFirst?.map((find) => find.id).toList();
  }

  test('沒讀過時寫入不讀，記著的仍是 null', () async {
    await dao.upsert(find('a'));
    expect(await latestIds(), isNull);
  });

  test('讀過之後，寫入、刪除提交後記著的跟著換', () async {
    await dao.getNewestFirst();
    await dao.upsert(find('a'));
    expect(await latestIds(), ['a']);
    await dao.upsertAll([find('b')]);
    expect(await latestIds(), unorderedEquals(['a', 'b']));
    await dao.deleteByIds(['a']);
    expect(await latestIds(), ['b']);
    await dao.deleteById('b');
    expect(await latestIds(), isEmpty);
  });

  test('交易撤銷時記著的不含撤銷的那幾筆', () async {
    await dao.getNewestFirst();
    await expectLater(
      db.transaction(() async {
        await dao.upsert(find('rolled-back'));
        throw StateError('還原到一半失敗');
      }),
      throwsStateError,
    );
    expect(await latestIds(), isEmpty);
    expect(await dao.getAll(), isEmpty);
  });

  test('交易裡寫很多筆，提交後記著的是全部', () async {
    await dao.getNewestFirst();
    await db.transaction(() async {
      for (var i = 0; i < 20; i++) {
        await dao.upsert(find('$i'));
      }
    });
    expect(await latestIds(), hasLength(20));
  });
}
