import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/parsers/analyze_by_json_path.dart';

void main() {
  group('AnalyzeByJsonPath Tests', () {
    const jsonStr = '''
    {
      "store": {
        "book": [
          { "category": "reference", "author": "Nigel Rees", "title": "Sayings of the Century", "price": 8.95 },
          { "category": "fiction", "author": "Evelyn Waugh", "title": "Sword of Honour", "price": 12.99 },
          { "category": "fiction", "author": "Herman Melville", "title": "Moby Dick", "isbn": "0-553-21311-3", "price": 8.99 },
          { "category": "fiction", "author": "J. R. R. Tolkien", "title": "The Lord of the Rings", "isbn": "0-395-19395-8", "price": 22.99 }
        ],
        "bicycle": { "color": "red", "price": 19.95 }
      },
      "expensive": 10
    }
    ''';

    late AnalyzeByJsonPath analyzer;

    setUp(() {
      analyzer = AnalyzeByJsonPath(jsonStr);
    });

    test('1. Basic getString (String value)', () {
      expect(analyzer.getString(r'$.store.bicycle.color'), 'red');
    });

    test('2. Basic getString (Number value auto-converted to String)', () {
      expect(analyzer.getString(r'$.store.bicycle.price'), '19.95');
      expect(analyzer.getString(r'$.expensive'), '10');
    });

    test('3. getElements (List of maps)', () {
      final books = analyzer.getElements(r'$.store.book[*]');
      expect(books, isList);
      expect(books.length, 4);
      expect(books[0]['author'], 'Nigel Rees');
    });

    test('4. getStringList (List of strings)', () {
      final authors = analyzer.getStringList(r'$.store.book[*].author');
      expect(authors, isList);
      expect(authors.length, 4);
      expect(authors, contains('Nigel Rees'));
      expect(authors, contains('J. R. R. Tolkien'));
    });

    test('5. Support @json: prefix', () {
      expect(analyzer.getString(r'@json:$.store.bicycle.color'), 'red');
    });

    test('6. Logical && operator', () {
      // RuleAnalyzer splits this into two queries and joins with \n
      final result = analyzer.getString(
        r'$.store.bicycle.color && $.store.bicycle.price',
      );
      expect(result, 'red\n19.95');
    });

    test('7. Logical || operator (fallback)', () {
      // first one doesn't exist
      final result = analyzer.getString(r'$.none || $.store.bicycle.color');
      expect(result, 'red');
    });

    test(r'8. Nested rules {$.}', () {
      // In Legado, {$.rule} is often used to compose strings
      final result = analyzer.getString(r'Color: {$.store.bicycle.color}');
      expect(result, 'Color: red');
    });

    test('9. Root array selectors accept legado \$.[*] syntax', () {
      final arrayAnalyzer = AnalyzeByJsonPath('''
        [
          {"chapterId": "142366", "chapterName": "第一章"},
          {"chapterId": "142367", "chapterName": "第二章"}
        ]
      ''');

      final chapters = arrayAnalyzer.getElements(r'$.[*]');
      expect(chapters, hasLength(2));
      expect(chapters.first['chapterId'], '142366');
      expect(arrayAnalyzer.getString(r'$.[*].chapterName'), '第一章\n第二章');
    });
  });
}
