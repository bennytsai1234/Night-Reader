import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/models/cache.dart';

void main() {
  group('CacheDao', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'clearDeadline removes entries whose deadline has just elapsed',
      () async {
        await db.cacheDao.upsert(Cache(key: 'no-expiry', deadline: 0));
        await db.cacheDao.upsert(Cache(key: 'past', deadline: 99));
        await db.cacheDao.upsert(Cache(key: 'now', deadline: 100));
        await db.cacheDao.upsert(Cache(key: 'future', deadline: 101));

        await db.cacheDao.clearDeadline(100);

        expect(await db.cacheDao.get('no-expiry'), isNotNull);
        expect(await db.cacheDao.get('past'), isNull);
        expect(await db.cacheDao.get('now'), isNull);
        expect(await db.cacheDao.get('future'), isNotNull);
      },
    );
  });
}
