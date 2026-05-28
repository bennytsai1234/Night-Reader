import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book_source.dart';

void main() {
  // ─── BookSourceService 純函式 ──────────────────────────────────────────────
  //
  // BookSourceService 的大部分方法（getBookInfo, getChapterList, getContent…）
  // 都需要真實網路呼叫，無法在 unit test 中驗證。
  // 這裡測試可獨立驗證的靜態/純邏輯部分。

  // ─── BookSource 模型 ───────────────────────────────────────────────────────
  group('BookSource 模型', () {
    test('fromJson() 解析必要欄位', () {
      final source = BookSource.fromJson({
        'bookSourceUrl': 'https://example.com',
        'bookSourceName': '測試書源',
        'bookSourceType': 0,
        'enabled': true,
      });
      expect(source.bookSourceUrl, equals('https://example.com'));
      expect(source.bookSourceName, equals('測試書源'));
      expect(source.bookSourceType, equals(0));
      expect(source.enabled, isTrue);
    });

    test('toJson() + fromJson() 往返不失資料', () {
      final original = BookSource.fromJson({
        'bookSourceUrl': 'https://example.com',
        'bookSourceName': '往返測試書源',
        'bookSourceType': 1,
        'enabled': false,
        'bookSourceGroup': 'Group A',
        'bookSourceComment': '備注文字',
        'weight': 5,
      });

      final restored = BookSource.fromJson(original.toJson());

      expect(restored.bookSourceUrl, equals(original.bookSourceUrl));
      expect(restored.bookSourceName, equals(original.bookSourceName));
      expect(restored.bookSourceType, equals(original.bookSourceType));
      expect(restored.enabled, equals(original.enabled));
      expect(restored.bookSourceGroup, equals(original.bookSourceGroup));
      expect(restored.bookSourceComment, equals(original.bookSourceComment));
      expect(restored.weight, equals(original.weight));
    });

    test('enabled=false 在序列化後仍保持 false', () {
      final source = BookSource.fromJson({
        'bookSourceUrl': 'https://disabled.com',
        'bookSourceName': 'Disabled Source',
        'enabled': false,
      });
      expect(BookSource.fromJson(source.toJson()).enabled, isFalse);
    });

    test('fromJson() 對缺少選填欄位不拋出例外', () {
      expect(
        () => BookSource.fromJson({
          'bookSourceUrl': 'https://minimal.com',
          'bookSourceName': 'Minimal',
        }),
        returnsNormally,
      );
    });

    test('fromJson() 對未知欄位不拋出例外（容錯性）', () {
      expect(
        () => BookSource.fromJson({
          'bookSourceUrl': 'https://future.com',
          'bookSourceName': 'Future Source',
          'unknownFieldFromFutureVersion': 'some value',
        }),
        returnsNormally,
      );
    });

    test('不同 bookSourceType 的書源序列化正確', () {
      for (final type in [0, 1, 2]) {
        final source = BookSource.fromJson({
          'bookSourceUrl': 'https://type$type.com',
          'bookSourceName': 'Type $type Source',
          'bookSourceType': type,
        });
        expect(source.bookSourceType, equals(type));
        expect(
          BookSource.fromJson(source.toJson()).bookSourceType,
          equals(type),
        );
      }
    });

    test('規則欄位（ruleSearch）可透過序列化傳遞', () {
      // ruleSearch 在 toJson() 被序列化成 JSON 字串，
      // fromJson() 再 parse 成 SearchRule 物件，
      // 驗證往返後物件欄位值正確，而非比較原始字串。
      final source = BookSource.fromJson({
        'bookSourceUrl': 'https://example.com',
        'bookSourceName': '有規則的書源',
        'ruleSearch':
            r'{"name":"$.title","bookUrl":"$.url","author":"$.author"}',
      });
      final restored = BookSource.fromJson(source.toJson());
      expect(restored.ruleSearch, isNotNull);
      expect(restored.ruleSearch!.name, equals(r'$.title'));
      expect(restored.ruleSearch!.bookUrl, equals(r'$.url'));
      expect(restored.ruleSearch!.author, equals(r'$.author'));
    });
  });
}
