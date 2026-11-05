import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/cache_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/services/cache_manager.dart';

/// 書源規則存的有期限文字（`cache.put`、`java.cacheFile`）：期限在 App 關著
/// 的時候過了，重開後讀不到，要重新向書源抓。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    await GetIt.instance.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    registerDatabase(db);
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  test('text that expired while the app was closed is gone after the '
      'launch cleanup', () async {
    final cache = CacheManager();
    final now = DateTime.now().millisecondsSinceEpoch;
    await cache.put('nr-expired', '舊的目錄', deadline: now - 1000);
    // 重開 App：記憶體是空的。
    cache.deleteMemory('nr-expired');
    await getIt<CacheDao>().clearDeadline(now);

    expect(await cache.get('nr-expired'), isNull);
    expect(await cache.get('nr-expired'), isNull);
  });

  test(
    'text that is still valid survives a restart with its deadline',
    () async {
      final cache = CacheManager();
      final deadline = DateTime.now().millisecondsSinceEpoch + 60 * 1000;
      await cache.put('nr-live', '新的目錄', deadline: deadline);
      cache.deleteMemory('nr-live');

      expect(await cache.get('nr-live'), '新的目錄');
      expect((await getIt<CacheDao>().get('nr-live'))?.deadline, deadline);
    },
  );
}
