import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/rule_analyzer.dart';
import 'package:night_reader/core/models/rule_data_interface.dart';
import '../../test_helper.dart';

// ─── 測試輔助 ──────────────────────────────────────────────────────────────────
class _MockRuleData extends RuleDataInterface {
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
  setupTestDI();

  // ─── RuleAnalyzer.splitRule() 直接測試 ─────────────────────────────────────
  //
  // 這組測試直接驗證 splitRule() 的分割邏輯，不依賴 JsonPath/JS 引擎。
  // 測試目標：括號內的分隔符不應被視為規則邊界。

  group('RuleAnalyzer.splitRule() — 括號感知分割', () {
    test('簡單 && 分割：兩個規則', () {
      final ra = RuleAnalyzer(r'$.a && $.b');
      final parts = ra.splitRule(['&&']);
      expect(parts.length, equals(2));
      expect(parts[0].trim(), equals(r'$.a'));
      expect(parts[1].trim(), equals(r'$.b'));
    });

    test('[] 括號內的 && 不視為分隔符', () {
      // $.a[?(@.x=='&&')] && $.b
      // 第一部分的 && 在 [] 內，不應被分割
      final ra = RuleAnalyzer(r"$.a[?(@.x=='&&')] && $.b");
      final parts = ra.splitRule(['&&']);
      expect(parts.length, equals(2));
      expect(parts[0].trim(), equals(r"$.a[?(@.x=='&&')]"));
      expect(parts[1].trim(), equals(r'$.b'));
    });

    test('() 括號內的 || 不視為分隔符', () {
      final ra = RuleAnalyzer(r'func(a || b) || $.fallback');
      final parts = ra.splitRule(['||']);
      expect(parts.length, equals(2));
      expect(parts[0].trim(), equals(r'func(a || b)'));
      expect(parts[1].trim(), equals(r'$.fallback'));
    });

    test('無分隔符時回傳整個字串（單元素 list）', () {
      final ra = RuleAnalyzer(r'$.simple.path');
      final parts = ra.splitRule(['&&']);
      expect(parts.length, equals(1));
      expect(parts[0], equals(r'$.simple.path'));
    });

    test('連續三個規則正確分割', () {
      final ra = RuleAnalyzer(r'$.a && $.b && $.c');
      final parts = ra.splitRule(['&&']);
      expect(parts.length, equals(3));
      expect(parts[0].trim(), equals(r'$.a'));
      expect(parts[1].trim(), equals(r'$.b'));
      expect(parts[2].trim(), equals(r'$.c'));
    });

    test('巢狀括號內的分隔符不被分割', () {
      // ([?(@.x == '&&' || @.y == '||')]) 中同時含 && 與 ||
      final ra = RuleAnalyzer(r"$.a[?(@.x == '&&' || @.y == '||')] && $.b");
      final parts = ra.splitRule(['&&']);
      expect(parts.length, equals(2));
      expect(parts[0], contains('[?'));
      expect(parts[1].trim(), equals(r'$.b'));
    });
  });

  // ─── AnalyzeRule 透過 JsonPath 的端對端分割驗證 ────────────────────────────
  //
  // 這組測試驗證 AnalyzeRule 對真實 JSON 資料做 && 規則串聯時，
  // 括號內的 && 不被錯誤切開，導致 JsonPath 語法損壞。
  //
  // 注意：若 AnalyzeByJsonPath 實作有 bug，這組測試也會失敗。
  // 測試失敗的根因在 lib/core/engine/parsers/analyze_by_json_path.dart，
  // 而非本測試檔。

  group('AnalyzeRule && 串聯 — 括號感知（需 JsonPath 正確運作）', () {
    late _MockRuleData mockData;
    late AnalyzeRule analyzer;

    setUp(() {
      mockData = _MockRuleData();
      analyzer = AnalyzeRule(ruleData: mockData);
    });

    test('含 && 的 JsonPath filter 不被誤切，兩條規則各自正確執行', () {
      // 規則語義：
      //   Part 1: $.items[?(@.type=='&&')]  → 取 type 為 '&&' 的元素
      //   Part 2: $.label                  → 取頂層 label
      // && 串聯代表兩個結果用 \n 合併
      analyzer.setContent({
        'items': [
          {'type': '&&', 'name': 'match'},
          {'type': 'other', 'name': 'skip'},
        ],
        'label': 'top-label',
      });

      const rule = r"$.items[?(@.type=='&&')].name && $.label";
      final result = analyzer.getString(rule);

      // 兩段結果都應出現在最終字串中
      expect(result, contains('match'), reason: 'Part 1 應取到 name=match');
      expect(result, contains('top-label'), reason: 'Part 2 應取到 label');
    });

    test('|| 作為 fallback：第一條規則有結果時不執行第二條', () {
      analyzer.setContent({'primary': 'found'});

      const rule = r'$.primary || $.fallback';
      final result = analyzer.getString(rule);

      expect(result, equals('found'));
    });

    test('|| 作為 fallback：第一條規則無結果時執行第二條', () {
      analyzer.setContent({'fallback': 'backup-value'});

      const rule = r'$.missing || $.fallback';
      final result = analyzer.getString(rule);

      expect(result, equals('backup-value'));
    });
  });

  // ─── JS 依賴測試（需要 JS 引擎，暫時略過）─────────────────────────────────
  //
  // 以下場景需要 flutter_js 在 VM 環境正常執行，
  // 目前測試環境不支援，待 JS engine 整合後啟用。

  group('JS 依賴場景', () {
    test('JsonPath + java.put() 邊際行為', () {}, skip: 'flutter_js 在 VM 測試環境不可用');
    test('{{ }} 模板 JS 求值', () {}, skip: 'flutter_js 在 VM 測試環境不可用');
  });
}
