import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/source/book_source.dart';

/// 發現頁列哪些書源，同 Legado `BookSourceDao.flowExplore`：只看「啟用發現」
/// 與有沒有發現網址，「啟用」（搜尋）各管各的。
void main() {
  BookSource source(
    String name, {
    required bool enabled,
    bool explore = true,
  }) => BookSource(
    bookSourceUrl: 'https://$name.test',
    bookSourceName: name,
    exploreUrl: '/explore',
    enabled: enabled,
    enabledExplore: explore,
  );

  test('a disabled source with discovery on is listed in discovery', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = BookSourceDao(db);
    await dao.upsert(source('on', enabled: true));
    await dao.upsert(source('disabled', enabled: false));
    await dao.upsert(source('noExplore', enabled: true, explore: false));

    final listed = [
      for (final s in await dao.getDiscoveryPart())
        if (s.canParticipateInDiscovery) s.bookSourceName,
    ];
    expect(listed, unorderedEquals(['on', 'disabled']));
  });
}
