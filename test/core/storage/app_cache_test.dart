import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/storage/app_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppCache', () {
    final cacheDirs = <Directory>[];

    tearDown(() async {
      for (final dir in cacheDirs) {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
      cacheDirs.clear();
    });

    Future<AppCache> createCache({
      required int maxSize,
      int maxCount = 100,
    }) async {
      final cache = await AppCache.get(
        cacheName:
            'app-cache-test-${DateTime.now().microsecondsSinceEpoch}-${cacheDirs.length}',
        maxSize: maxSize,
        maxCount: maxCount,
      );
      cacheDirs.add(cache.cacheDir);
      return cache;
    }

    test(
      'evicts oldest files until the byte-size limit is satisfied',
      () async {
        final cache = await createCache(maxSize: 10);

        await cache.put('oldest', '12345678');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await cache.put('newest', 'abcdefgh');

        expect(await cache.getAsString('oldest'), isNull);
        expect(await cache.getAsString('newest'), 'abcdefgh');
        final totalBytes = cache.cacheDir
            .listSync()
            .whereType<File>()
            .fold<int>(0, (sum, file) => sum + file.lengthSync());
        expect(totalBytes, lessThanOrEqualTo(10));
      },
    );

    test(
      'does not strip ordinary text that merely contains dash and space',
      () async {
        final cache = await createCache(maxSize: 1024);
        const value = 'not-expiring-value with spaces';

        await cache.put('plain-text', value);

        expect(await cache.getAsString('plain-text'), value);
      },
    );

    test('enforces the file-count limit before put completes', () async {
      final cache = await createCache(maxSize: 1024, maxCount: 1);

      await cache.put('first', '1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await cache.put('second', '2');

      expect(cache.cacheDir.listSync().whereType<File>(), hasLength(1));
      expect(await cache.getAsString('first'), isNull);
      expect(await cache.getAsString('second'), '2');
    });

    test('serializes concurrent trims without exceeding count', () async {
      final cache = await createCache(maxSize: 1024, maxCount: 2);

      await Future.wait<void>([
        for (var index = 0; index < 8; index++)
          cache.put('key-$index', '$index'),
      ]);

      expect(
        cache.cacheDir.listSync().whereType<File>().length,
        lessThanOrEqualTo(2),
      );
    });

    test(
      'keeps distinct values for keys with the same Dart hashCode',
      () async {
        final cache = await createCache(maxSize: 1024);
        const firstKey = '19200481012a86d74842c8b3e39d5cfb';
        const secondKey = '37f181e79f06f27857403fb7880b4b21';
        expect(firstKey.hashCode, secondKey.hashCode);

        await cache.put(firstKey, 'first');
        await cache.put(secondKey, 'second');

        expect(await cache.getAsString(firstKey), 'first');
        expect(await cache.getAsString(secondKey), 'second');
      },
    );
  });
}
