import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/utils/lru_map.dart';

void main() {
  group('LruMap', () {
    test('basic put and get', () {
      final cache = LruMap<String, int>(maxSize: 5);
      cache['a'] = 1;
      cache['b'] = 2;
      cache['c'] = 3;

      expect(cache['a'], 1);
      expect(cache['b'], 2);
      expect(cache['c'], 3);
      expect(cache.length, 3);
    });

    test('returns null for absent key', () {
      final cache = LruMap<String, int>(maxSize: 5);
      expect(cache['missing'], isNull);
    });

    test('containsKey works', () {
      final cache = LruMap<String, int>(maxSize: 5);
      cache['x'] = 10;
      expect(cache.containsKey('x'), true);
      expect(cache.containsKey('y'), false);
    });

    test('evicts oldest entry when maxSize exceeded', () {
      final cache = LruMap<String, int>(maxSize: 3);
      cache['a'] = 1;
      cache['b'] = 2;
      cache['c'] = 3;
      // Cache is full: [a, b, c]
      cache['d'] = 4;
      // 'a' should be evicted: [b, c, d]

      expect(cache.containsKey('a'), false);
      expect(cache['a'], isNull);
      expect(cache.length, 3);
      expect(cache['b'], 2);
      expect(cache['c'], 3);
      expect(cache['d'], 4);
    });

    test('access promotes entry (LRU behavior)', () {
      final cache = LruMap<String, int>(maxSize: 3);
      cache['a'] = 1;
      cache['b'] = 2;
      cache['c'] = 3;

      // Access 'a' to promote it
      final _ = cache['a'];

      // Now insert 'd' - 'b' should be evicted (it's the least recently used)
      cache['d'] = 4;

      expect(
        cache.containsKey('a'),
        true,
        reason: 'a was promoted and should survive',
      );
      expect(
        cache.containsKey('b'),
        false,
        reason: 'b was LRU and should be evicted',
      );
      expect(cache.containsKey('c'), true);
      expect(cache.containsKey('d'), true);
    });

    test('update existing key promotes it', () {
      final cache = LruMap<String, int>(maxSize: 3);
      cache['a'] = 1;
      cache['b'] = 2;
      cache['c'] = 3;

      // Update 'a' with new value
      cache['a'] = 100;

      // Insert 'd' - 'b' should be evicted
      cache['d'] = 4;

      expect(cache['a'], 100);
      expect(cache.containsKey('b'), false);
      expect(cache.length, 3);
    });

    test('putIfAbsent inserts when absent', () {
      final cache = LruMap<String, int>(maxSize: 5);
      final result = cache.putIfAbsent('key', () => 42);
      expect(result, 42);
      expect(cache['key'], 42);
      expect(cache.length, 1);
    });

    test('putIfAbsent returns existing value when present', () {
      final cache = LruMap<String, int>(maxSize: 5);
      cache['key'] = 10;
      var called = false;
      final result = cache.putIfAbsent('key', () {
        called = true;
        return 99;
      });
      expect(result, 10);
      expect(
        called,
        false,
        reason: 'ifAbsent should not be called for existing key',
      );
    });

    test('putIfAbsent promotes existing entry', () {
      final cache = LruMap<String, int>(maxSize: 3);
      cache['a'] = 1;
      cache['b'] = 2;
      cache['c'] = 3;

      // putIfAbsent on 'a' promotes it
      cache.putIfAbsent('a', () => 99);

      // Insert 'd' - 'b' should be evicted (LRU)
      cache['d'] = 4;

      expect(cache.containsKey('a'), true);
      expect(cache.containsKey('b'), false);
    });

    test('putIfAbsent triggers eviction when full', () {
      final cache = LruMap<String, int>(maxSize: 2);
      cache['a'] = 1;
      cache['b'] = 2;

      cache.putIfAbsent('c', () => 3);

      expect(cache.length, 2);
      expect(cache.containsKey('a'), false);
      expect(cache['c'], 3);
    });

    test('clear removes all entries', () {
      final cache = LruMap<String, int>(maxSize: 5);
      cache['a'] = 1;
      cache['b'] = 2;
      cache['c'] = 3;

      cache.clear();

      expect(cache.length, 0);
      expect(cache.containsKey('a'), false);
      expect(cache['a'], isNull);
    });

    test('maxSize of 1 always keeps only latest entry', () {
      final cache = LruMap<String, int>(maxSize: 1);
      cache['a'] = 1;
      expect(cache.length, 1);
      expect(cache['a'], 1);

      cache['b'] = 2;
      expect(cache.length, 1);
      expect(cache.containsKey('a'), false);
      expect(cache['b'], 2);
    });

    test('default maxSize is 200', () {
      final cache = LruMap<int, int>();
      expect(cache.maxSize, 200);
    });
  });
}
