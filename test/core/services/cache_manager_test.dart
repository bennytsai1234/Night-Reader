import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/dao/cache_dao.dart';
import 'package:night_reader/core/models/cache.dart';
import 'package:night_reader/core/services/cache_manager.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:path/path.dart' as p;

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

  test(
    'delete removes a legacy sanitized cache file for the same key',
    () async {
      final cache = CacheManager();
      final cacheDir = await AppStoragePaths.jsCacheDir();
      const key = 'legacy/source:key';
      final legacyFile = File(p.join(cacheDir.path, 'legacy_source_key'));
      await legacyFile.writeAsString('legacy');

      await cache.delete(key);

      expect(await legacyFile.exists(), isFalse);
    },
  );

  test('legacy cleanup tolerates a file removed by another isolate', () async {
    final cacheDir = await AppStoragePaths.jsCacheDir();
    final file = File(p.join(cacheDir.path, 'already-removed-legacy'));
    await file.writeAsString('legacy');
    await file.delete();

    await expectLater(CacheManager.deleteLegacyFileIfPresent(file), completes);
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

  test('removing a cached null value restores its accounted capacity', () {
    final cache = LruMemoryCache(1028);

    cache.put('nullable', null);
    cache.remove('nullable');
    cache.put('a', 'a');
    cache.put('b', 'b');
    cache.put('c', 'c');

    expect(cache.keys, containsAll(<String>['a', 'b', 'c']));
  });

  test('file cache keys do not collide after path sanitization', () async {
    final cache = CacheManager();

    final slashPath = await cache.getCachePath('source/a');
    final colonPath = await cache.getCachePath('source:a');
    final traversalPath = await cache.getCachePath('..');

    expect(slashPath, isNot(colonPath));
    expect(p.basename(traversalPath), isNot('..'));
    expect(p.basename(traversalPath), hasLength(64));
  });
}
