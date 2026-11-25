import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/sync/replace_rule_sync.dart';
import 'package:night_reader/core/sync/sync_records.dart';
import 'package:night_reader/features/replace_rule/replace_rule_exchange.dart';

ReplaceRule _rule({
  int id = 1700000000001,
  String name = '去廣告',
  String pattern = '廣告',
  int order = 0,
}) => ReplaceRule(
  id: id,
  name: name,
  group: '淨化',
  pattern: pattern,
  replacement: '',
  scope: '某書',
  scopeTitle: true,
  scopeContent: false,
  excludeScope: '別書',
  isEnabled: false,
  isRegex: false,
  timeoutMillisecond: 5000,
  order: order,
);

void main() {
  group('匯出的格式 Legado 讀得懂', () {
    test('開關寫成 true／false，欄位名稱照 Legado', () {
      final json = _rule().toLegadoJson();
      expect(json, {
        'id': 1700000000001,
        'name': '去廣告',
        'group': '淨化',
        'pattern': '廣告',
        'replacement': '',
        'scope': '某書',
        'scopeTitle': true,
        'scopeContent': false,
        'excludeScope': '別書',
        'isEnabled': false,
        'isRegex': false,
        'timeoutMillisecond': 5000,
        'order': 0,
      });
    });

    test('還沒有編號的規則編號寫 null，Legado 讀到時自己配', () {
      final json = ReplaceRule(pattern: 'a').toLegadoJson();
      expect(json.containsKey('id'), isTrue);
      expect(json['id'], isNull);
    });

    test('匯出一批是一個陣列，一條是一個物件', () {
      final list = jsonDecode(
        encodeReplaceRules([_rule(), _rule(id: 2, pattern: 'b')]),
      );
      expect(list, isA<List<dynamic>>());
      expect((list as List).length, 2);
      expect((list.first as Map)['isRegex'], isFalse);
      final one = jsonDecode(encodeReplaceRule(_rule()));
      expect(one, isA<Map<String, dynamic>>());
      expect((one as Map)['scopeTitle'], isTrue);
    });
  });

  group('讀得進來的格式', () {
    test('舊的 1／0 與 Legado 的 true／false 讀成同一條規則', () {
      final legacy = jsonEncode([
        {..._rule().toJson()},
      ]);
      final legado = encodeReplaceRules([_rule()]);
      final fromLegacy = decodeReplaceRules(legacy).single;
      final fromLegado = decodeReplaceRules(legado).single;
      expect(fromLegacy.toJson(), fromLegado.toJson());
      expect(fromLegado.isEnabled, isFalse);
      expect(fromLegado.scopeTitle, isTrue);
      expect(fromLegado.scopeContent, isFalse);
    });

    test('單一規則的物件也收', () {
      expect(decodeReplaceRules(encodeReplaceRule(_rule())).single.name, '去廣告');
    });

    test('不是規則的字丟出格式錯誤', () {
      expect(() => decodeReplaceRules('"abc"'), throwsFormatException);
      expect(() => decodeReplaceRules('not json'), throwsFormatException);
    });

    test('貼上一條：物件或只有一條的陣列；空的、不是規則的回傳 null', () {
      expect(decodeOneReplaceRule(encodeReplaceRule(_rule()))?.name, '去廣告');
      expect(decodeOneReplaceRule(encodeReplaceRules([_rule()]))?.name, '去廣告');
      expect(decodeOneReplaceRule(''), isNull);
      expect(decodeOneReplaceRule('hello'), isNull);
      expect(decodeOneReplaceRule('{"name": "沒有規則"}'), isNull);
      expect(
        decodeOneReplaceRule(encodeReplaceRules([_rule(), _rule()])),
        isNull,
      );
    });
  });

  group('同步不因為匯出格式而認成改過', () {
    test('同步紀錄照舊寫 1／0，之前上傳的紀錄指紋不變', () {
      // 改版前同步上傳的樣子（ReplaceRule.toJson 拿掉 id）。
      const uploaded = <String, Object?>{
        'name': '去廣告',
        'group': '淨化',
        'pattern': '廣告',
        'replacement': '',
        'scope': '某書',
        'scopeTitle': 1,
        'scopeContent': 0,
        'excludeScope': '別書',
        'isEnabled': 0,
        'isRegex': 0,
        'timeoutMillisecond': 5000,
        'order': 0,
      };
      expect(
        ReplaceRuleSync.recordOf(_rule()).fingerprint,
        SyncRecord.fingerprintOf(uploaded),
      );
    });

    test('從 Legado 格式匯入的規則，同步紀錄和原本那條一樣', () {
      final imported = decodeReplaceRules(encodeReplaceRules([_rule()])).single;
      expect(
        ReplaceRuleSync.recordOf(imported).fingerprint,
        ReplaceRuleSync.recordOf(_rule()).fingerprint,
      );
    });
  });

  group('匯入前預覽', () {
    late AppDatabase db;
    late ReplaceRuleDao dao;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dao = ReplaceRuleDao(db);
    });

    tearDown(() => db.close());

    test('已有的同一條（同編號）標更新或已有、預設不勾；新的預設勾', () async {
      await dao.upsert(_rule(id: 1700000000005, name: '這台改過的', pattern: '甲'));
      await dao.upsert(
        _rule(id: 1700000000007, name: '一樣的', pattern: '丙', order: 1),
      );
      final preview = await previewReplaceRuleImport(
        encodeReplaceRules([
          _rule(id: 1700000000005, name: '檔案裡的', pattern: '甲甲'),
          _rule(id: 1700000000006, name: '新規則', pattern: '乙'),
          // 只有順序不同也算同一條。
          _rule(id: 1700000000007, name: '一樣的', pattern: '丙', order: 9),
          ReplaceRule(id: 1700000000008, name: '空的'),
        ]),
        dao,
      );
      expect(
        [for (final item in preview.items) (item.rule.id, item.state)],
        [
          (1700000000005, ReplaceRuleImportState.updated),
          (1700000000006, ReplaceRuleImportState.added),
          (1700000000007, ReplaceRuleImportState.unchanged),
        ],
      );
      expect(preview.invalidCount, 1);
      expect([for (final r in preview.defaultSelection) r.id], [1700000000006]);
    });

    test('照預設的勾選匯入：沒勾的已有規則不被蓋掉', () async {
      await dao.upsert(_rule(id: 1700000000005, name: '這台改過的', pattern: '甲'));
      final before = (await dao.getAll()).single.toJson();
      final preview = await previewReplaceRuleImport(
        encodeReplaceRules([
          _rule(id: 1700000000005, name: '檔案裡的', pattern: '甲甲'),
          _rule(id: 1700000000006, name: '新規則', pattern: '乙'),
        ]),
        dao,
      );
      final count = await importReplaceRules(preview.defaultSelection, dao);
      expect(count, 1);
      final rules = {for (final r in await dao.getAll()) r.id: r};
      expect(rules.keys, unorderedEquals([1700000000005, 1700000000006]));
      expect(rules[1700000000005]!.toJson(), before);
    });

    test('舊流水號撞號、是別條規則：當成新增、預設勾，匯入後兩條都在', () async {
      await dao.upsert(_rule(id: 3, name: '去廣告', pattern: '廣告'));
      final preview = await previewReplaceRuleImport(
        encodeReplaceRules([
          _rule(id: 3, name: '去水印', pattern: '水印'),
          // 同一條規則只改了開關：同步也認成同一條，照舊標更新。
          _rule(id: 3, name: '去廣告', pattern: '廣告')..isEnabled = true,
        ]),
        dao,
      );
      expect(
        [for (final item in preview.items) item.state],
        [ReplaceRuleImportState.added, ReplaceRuleImportState.updated],
      );
      await importReplaceRules(preview.defaultSelection, dao);
      final rules = await dao.getAll();
      expect(
        {for (final r in rules) r.pattern: r.name},
        {'廣告': '去廣告', '水印': '去水印'},
      );
      expect(rules.firstWhere((r) => r.pattern == '廣告').id, 3);
      expect(rules.firstWhere((r) => r.pattern == '水印').id, isNot(3));
    });

    test('編號是建立時間的同號規則照舊標更新、預設不勾', () async {
      await dao.upsert(_rule(id: 1700000000005, name: '這台的', pattern: '甲'));
      final preview = await previewReplaceRuleImport(
        encodeReplaceRules([
          _rule(id: 1700000000005, name: '別的', pattern: '乙'),
        ]),
        dao,
      );
      expect(preview.items.single.state, ReplaceRuleImportState.updated);
      expect(preview.defaultSelection, isEmpty);
    });

    test('勾了已有的才覆蓋', () async {
      await dao.upsert(_rule(id: 1700000000005, name: '這台改過的', pattern: '甲'));
      final preview = await previewReplaceRuleImport(
        encodeReplaceRules([
          _rule(id: 1700000000005, name: '檔案裡的', pattern: '甲甲'),
        ]),
        dao,
      );
      await importReplaceRules([preview.items.single.rule], dao);
      expect((await dao.getAll()).single.name, '檔案裡的');
    });
  });
}
