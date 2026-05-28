import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/cookie.dart';
import 'package:night_reader/core/models/search_keyword.dart';
import 'package:night_reader/core/models/server.dart';
import 'package:night_reader/core/models/keyboard_assist.dart';
import 'package:night_reader/core/models/cache.dart';

void main() {
  group('System and Utility Models Tests', () {
    test('Cookie serialization', () {
      final cookie = Cookie(url: 'https://example.com', cookie: 'key=val');
      final json = cookie.toJson();
      final fromJson = Cookie.fromJson(json);
      expect(fromJson.url, 'https://example.com');
      expect(fromJson.cookie, 'key=val');
    });

    test('SearchKeyword serialization', () {
      final sk = SearchKeyword(word: 'flutter', usage: 10);
      final json = sk.toJson();
      final fromJson = SearchKeyword.fromJson(json);
      expect(fromJson.word, 'flutter');
      expect(fromJson.usage, 10);
    });

    test('Server serialization', () {
      final server = Server(
        id: 1,
        name: 'MyCloud',
        type: 'WEBDAV',
        config: '{"url":"http://dav.com","username":"user"}',
      );

      final json = server.toJson();
      final fromJson = Server.fromJson(json);
      expect(fromJson.id, 1);
      expect(fromJson.name, 'MyCloud');
      expect(fromJson.type, 'WEBDAV');
      expect(fromJson.config, contains('url'));
    });

    test('KeyboardAssist serialization', () {
      final assist = KeyboardAssist(key: 'A', value: 'Alpha');
      final json = assist.toJson();
      final fromJson = KeyboardAssist.fromJson(json);
      expect(fromJson.key, 'A');
      expect(fromJson.value, 'Alpha');
    });

    test('Cache serialization', () {
      final cache = Cache(key: 'key1', value: 'data', deadline: 12345);
      final json = cache.toJson();
      final fromJson = Cache.fromJson(json);
      expect(fromJson.key, 'key1');
      expect(fromJson.deadline, 12345);
    });
  });
}
