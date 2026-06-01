import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/models/replace_rule.dart';

void main() {
  group('ReplaceRuleDao', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('upsert lets new rules receive generated ids', () async {
      await db.replaceRuleDao.upsert(
        ReplaceRule(name: '規則 A', pattern: 'a', order: 0),
      );
      await db.replaceRuleDao.upsert(
        ReplaceRule(name: '規則 B', pattern: 'b', order: 1),
      );

      final rules = await db.replaceRuleDao.getAll();

      expect(rules.map((rule) => rule.name), ['規則 A', '規則 B']);
      expect(rules.map((rule) => rule.id), everyElement(greaterThan(0)));
    });

    test('scoped queries return only rules applicable to the book', () async {
      await db.replaceRuleDao.upsertAll([
        ReplaceRule(name: '全域正文', pattern: 'ad', order: 0),
        ReplaceRule(name: '本書正文', pattern: 'bad', scope: '測試書', order: 1),
        ReplaceRule(
          name: '來源標題',
          pattern: '廣告',
          scope: 'https://source.example',
          scopeTitle: true,
          scopeContent: false,
          order: 2,
        ),
        ReplaceRule(name: '其他書', pattern: 'x', scope: '其他書', order: 3),
        ReplaceRule(name: '排除本書', pattern: 'y', excludeScope: '測試書', order: 4),
        ReplaceRule(name: '停用規則', pattern: 'z', isEnabled: false, order: 5),
      ]);

      final allForBook = await db.replaceRuleDao.getEnabledForBook(
        '測試書',
        'https://source.example',
      );
      final contentRules = await db.replaceRuleDao.getEnabledContentForBook(
        '測試書',
        'https://source.example',
      );
      expect(allForBook.map((rule) => rule.name), ['全域正文', '本書正文', '來源標題']);
      expect(contentRules.map((rule) => rule.name), ['全域正文', '本書正文']);
    });
  });
}
