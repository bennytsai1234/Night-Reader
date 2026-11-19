import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/utils/cache_manager.dart';
import 'package:night_reader/core/utils/lru_map.dart';

void main() {
  group('counted by entries', () {
    test('drops the least recently used entry past the limit', () {
      final map = LruMap<String, int>(maxSize: 2);
      map['a'] = 1;
      map['b'] = 2;
      expect(map['a'], 1);
      map['c'] = 3;
      expect(map.containsKey('b'), isFalse);
      expect(map['a'], 1);
      expect(map['c'], 3);
      expect(map.length, 2);
    });

    test('putIfAbsent keeps the stored value and counts as a use', () {
      final map = LruMap<String, int>(maxSize: 2);
      map['a'] = 1;
      map['b'] = 2;
      expect(map.putIfAbsent('a', () => fail('should not build')), 1);
      map['c'] = 3;
      expect(map.containsKey('a'), isTrue);
      expect(map.containsKey('b'), isFalse);
    });
  });

  group('counted by size (CacheManager memory layer)', () {
    test('drops the least recently used until the new value fits', () {
      final cache = LruMap<String, Object?>(
        maxSize: 10,
        sizeOf: estimateMemorySize,
      );
      cache['a'] = 'xx'; // 4
      cache['b'] = 'xx'; // 4
      expect(cache['a'], 'xx');
      cache['c'] = 'xxx'; // 6: dropping b is enough
      expect(cache.keys, ['a', 'c']);
      cache['d'] = [1, 2, 3, 4, 5, 6, 7, 8]; // 8: drops a, then c
      expect(cache.keys, ['d']);
      expect(cache['d'], [1, 2, 3, 4, 5, 6, 7, 8]);
    });

    test('a value bigger than the limit is not kept and drops the old one', () {
      final cache = LruMap<String, Object?>(
        maxSize: 10,
        sizeOf: estimateMemorySize,
      );
      cache['a'] = 'xx';
      cache['b'] = 'xx';
      cache['a'] = 'xxxxxx'; // 12
      expect(cache['a'], isNull);
      expect(cache['b'], 'xx');
    });

    test('replacing and removing give the size back', () {
      final cache = LruMap<String, Object?>(
        maxSize: 10,
        sizeOf: estimateMemorySize,
      );
      cache['a'] = 'xxxx'; // 8
      cache['a'] = 'x'; // 2
      cache['b'] = 'xxxx'; // 8, fits with a
      expect(cache['a'], 'x');
      cache.remove('a');
      cache['c'] = 'x'; // 2, fits with b
      expect(cache['b'], 'xxxx');
      expect(cache['c'], 'x');
    });

    test('a stored null reads as null and still counts as a use', () {
      final cache = LruMap<String, Object?>(
        maxSize: 2048,
        sizeOf: estimateMemorySize,
      );
      cache['n'] = null; // 1024
      cache['a'] = 'x'; // 2
      expect(cache['n'], isNull);
      expect(cache.keys, ['a', 'n']);
      cache['b'] = List<int>.filled(1023, 0); // drops the oldest: a
      expect(cache.keys, ['n', 'b']);
    });
  });
}
