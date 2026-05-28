import 'package:flutter_test/flutter_test.dart';
import 'package:reader/core/engine/analyze_rule.dart';
import 'package:reader/core/engine/analyze_url.dart';
import 'package:reader/core/models/rule_data_interface.dart';
import 'dart:convert';
import '../../test_helper.dart';

class MockRuleData extends RuleDataInterface {
  @override
  final Map<String, String> variableMap = {};

  @override
  String getVariable(String key) => variableMap[key] ?? '';

  @override
  void putVariable(String key, String? value) {
    if (value != null) {
      variableMap[key] = value;
    } else {
      variableMap.remove(key);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();
  group('Parsing Integration Tests', () {
    const bookSourceJson = {
      'bookSourceUrl': 'https://api.example.com',
      'bookSourceName': 'Integration Test Source',
      'searchUrl': '/search?keyword={{key}}&page={{page}}',
      'ruleSearch': {
        'bookList': r'$.data.books[*]',
        'name': r'$.title',
        'author': r'$.author',
        'bookUrl': r"$.id@js: 'https://api.example.com/book/' + result",
        'kind': r'$.category && $.status',
      },
    };

    const mockApiResponse = {
      'data': {
        'books': [
          {
            'id': '123',
            'title': 'Dart in Action',
            'author': 'John Doe',
            'category': 'Tech',
            'status': 'Completed',
          },
          {
            'id': '456',
            'title': 'Flutter Magic',
            'author': 'Jane Smith',
            'category': 'Tech',
            'status': 'Ongoing',
          },
        ],
      },
    };

    test('Full search flow integration', () async {
      // 1. URL Construction
      final analyzeUrl = AnalyzeUrl(
        bookSourceJson['searchUrl'] as String,
        key: 'flutter',
        page: 1,
        baseUrl: bookSourceJson['bookSourceUrl'] as String,
      );

      expect(
        analyzeUrl.url,
        'https://api.example.com/search?keyword=flutter&page=1',
      );

      // 2. Result Parsing
      final analyzer = AnalyzeRule(ruleData: MockRuleData());
      analyzer.setContent(jsonEncode(mockApiResponse));

      final ruleSearch = bookSourceJson['ruleSearch'] as Map<String, dynamic>;

      // Get Book List
      final bookList = analyzer.getElements(ruleSearch['bookList'] as String);
      expect(bookList.length, 2);

      // Parse first book
      final firstBook = bookList[0];
      final itemAnalyzer = AnalyzeRule(ruleData: MockRuleData());
      itemAnalyzer.setContent(firstBook);

      final name = itemAnalyzer.getString(ruleSearch['name'] as String);
      final author = itemAnalyzer.getString(ruleSearch['author'] as String);
      final bookUrl = itemAnalyzer.getString(ruleSearch['bookUrl'] as String);
      final kind = itemAnalyzer.getString(ruleSearch['kind'] as String);

      expect(name, 'Dart in Action');
      expect(author, 'John Doe');
      expect(bookUrl, 'https://api.example.com/book/123');
      expect(kind, 'Tech\nCompleted');

      analyzer.dispose();
      itemAnalyzer.dispose();
    });

    test('Variable @put and @get integration', () {
      final mockData = MockRuleData();
      final analyzer = AnalyzeRule(ruleData: mockData);

      // Simulate a rule that saves a variable
      analyzer.setContent({'id': '999', 'temp': 'Secret'});

      // Rule with @put
      analyzer.getString(r'$.id@put:{"myVar": "$.temp"}');

      expect(mockData.getVariable('myVar'), 'Secret');

      // Get variable in another rule
      final result = analyzer.getString(
        r'The ID is {$.id} and var is @get:{myVar}',
      );
      expect(result, 'The ID is 999 and var is Secret');

      analyzer.dispose();
    });
  });
}
