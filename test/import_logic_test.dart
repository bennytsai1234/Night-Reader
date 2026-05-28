import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/book.dart';

void main() {
  group('真實數據解析測試', () {
    test('書源 JSON 解析測試', () {
      const rawJson = '''
      [
        {
          "bookSourceComment": "// Error: 搜索失敗",
          "bookSourceGroup": "修復,搜尋失敗",
          "bookSourceName": "武俠閣",
          "bookSourceType": 0,
          "bookSourceUrl": "https://novels-a.test/",
          "customOrder": -43359,
          "enabled": true,
          "enabledExplore": true,
          "ruleSearch": {
            "author": "author",
            "bookList": ".item",
            "bookUrl": "a.0@href",
            "coverUrl": "img@src",
            "intro": ".resume@text",
            "name": "h3@text"
          }
        }
      ]
      ''';

      final List<dynamic> decoded = jsonDecode(rawJson);
      expect(decoded, isA<List>());

      final source = BookSource.fromJson(decoded.first);
      expect(source.bookSourceName, '武俠閣');
      expect(source.bookSourceUrl, 'https://novels-a.test/');
      expect(source.ruleSearch?.name, 'h3@text');
    });

    test('書籍 JSON 解析測試', () {
      const rawJson = '''
      [
        {
          "author": "天海祥雲",
          "intro": "關於JOJO：迪奧波羅在不在？",
          "name": "JOJO：迪奧波羅在不在",
          "bookUrl": "https://example.com/book/1",
          "origin": "https://example.com/"
        }
      ]
      ''';

      final List<dynamic> decoded = jsonDecode(rawJson);
      expect(decoded, isA<List>());

      final book = Book.fromJson(decoded.first);
      expect(book.name, 'JOJO：迪奧波羅在不在');
      expect(book.author, '天海祥雲');
    });
  });
}
