import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/dao/cache_dao.dart';
import 'package:night_reader/core/models/cache.dart';
import 'package:night_reader/core/services/cache_manager.dart';

class _InMemoryCacheDao extends Fake implements CacheDao {
  final _entries = <String, Cache>{};

  @override
  Future<Cache?> get(String key) async => _entries[key];

  @override
  Future<void> upsert(Cache cache) async {
    _entries[cache.key] = cache;
  }

  @override
  Future<void> deleteByKey(String key) async {
    _entries.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('works without registered CacheDao', () async {
    final cache = CacheManager();
    final key = 'cache_manager_no_dao_${DateTime.now().microsecondsSinceEpoch}';

    await cache.put(key, 'content');

    expect(await cache.get(key), 'content');

    await cache.delete(key);

    expect(await cache.get(key), isNull);
  });

  test('does not return an expired TTL value from memory', () async {
    final dao = _InMemoryCacheDao();
    getIt.registerSingleton<CacheDao>(dao);
    final cache = CacheManager();
    final key =
        'cache_manager_expired_ttl_${DateTime.now().microsecondsSinceEpoch}';

    await cache.put(key, 'expired content', saveTimeSeconds: 1);
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    expect(await cache.get(key), isNull);
    expect(dao._entries, isNot(contains(key)));
  });
}
