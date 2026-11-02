import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/js/js_extensions.dart';
import 'package:night_reader/core/engine/web_book/chapter_list_parser.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../../test_helper.dart';

/// 規則 JS 的 Java Stream：Legado 在 Rhino 上，`List`、`ArrayList`、Jsoup
/// `Elements` 都有 `stream()`，lambda 直接傳 JS 函式。期望值是 Java 的結果。
void main() {
  setupTestDI();
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = quickJsUnavailableReason();

  late JavascriptRuntime runtime;
  String eval(String js) => runtime.evaluate(js).stringResult;

  setUp(() {
    if (skip != null) return;
    runtime = getJavascriptRuntime();
    JsExtensions(runtime).inject();
  });
  tearDown(() {
    if (skip == null) runtime.dispose();
  });

  group('every kind of Java list has stream()', () {
    test('ArrayList、HashSet、Map 的 keySet／values／entrySet', () {
      expect(
        eval(r'''
          var list = new Packages.java.util.ArrayList();
          list.add("b"); list.add("a"); list.add("b");
          var set = new Packages.java.util.HashSet();
          set.add(1); set.add(2); set.add(1);
          var map = new Packages.java.util.HashMap();
          map.put("x", 10); map.put("y", 20);
          [list.stream().count(), list.parallelStream().distinct().count(),
           set.stream().count(),
           map.keySet().stream().collect(Packages.java.util.stream.Collectors.joining(",")),
           map.values().stream().mapToInt(function(v) { return v; }).sum(),
           map.entrySet().stream().map(function(e) { return e.getKey() + e.getValue(); }).toList().join("/")
          ].join("|")
        '''),
        '3|2|2|x,y|30|x10/y20',
      );
    });

    test('規則交回的清單（java.getStringList）', () {
      final rule = AnalyzeRule(
        source: BookSource(bookSourceUrl: 'https://a.test'),
      )..setContent('<i>一</i><i>二</i><i>三</i>', baseUrl: 'https://a.test/');
      addTearDown(rule.dispose);
      expect(
        rule.evalJS(r'''
          java.getStringList("tag.i@text").stream()
            .filter(function(s) { return s != "二"; }).toList().join("/")
        ''', null),
        '一/三',
      );
    });

    test('交給規則的清單（result）與 Jsoup Elements', () {
      final rule = AnalyzeRule(
        source: BookSource(bookSourceUrl: 'https://a.test'),
      )..setContent('<p>1</p><p>2</p>', baseUrl: 'https://a.test/');
      addTearDown(rule.dispose);
      expect(
        rule.evalJS(
          r'''
          var ps = java.getElements("tag.p");
          [ps.stream().map(e => e.text()).toList().join("+"),
           result.stream().count()].join("|")
        ''',
          ['a', 'b', 'c'],
        ),
        '1+2|3',
      );
    });
  });

  group('Stream 照 Java 的語意', () {
    test('map、filter、toList 交回能當 Java 清單用的 ArrayList', () {
      expect(
        eval(r'''
          var list = new Packages.java.util.ArrayList();
          [1, 2, 3, 4, 5].forEach(function(n) { list.add(n); });
          var out = list.stream().filter(n => n % 2 == 1).map(n => n * 10).toList();
          out.add(99);
          [out.size(), out.get(0), out.contains(30), out.isEmpty(),
           out.subList(0, 2).size(), out.iterator().next(),
           out.stream().count(), out.join(",")].join("|")
        '''),
        '4|10|true|false|2|10|4|10,30,50,99',
      );
    });

    test('collect(Collectors.toList())、toSet、joining、counting', () {
      expect(
        eval(r'''
          var C = Packages.java.util.stream.Collectors;
          var src = ["a", "b", "a", "c"];
          [src.stream().collect(C.toList()).size(),
           src.stream().collect(C.toSet()).size(),
           src.stream().collect(C.joining("-", "[", "]")),
           src.stream().collect(C.counting()),
           src.stream().collect(C.groupingBy(s => s, C.counting())).get("a"),
           src.stream().collect(C.groupingBy(s => s)).get("a").size(),
           src.stream().distinct().collect(C.toMap(s => s, s => s.charCodeAt(0))).get("c"),
           src.stream().collect(C.partitioningBy(s => s == "a")).get(true).size(),
           src.stream().collect(C.mapping(s => s.toUpperCase(), C.joining())),
           src.stream().collect(C.summingInt(s => s.length)),
           src.stream().collect(C.averagingInt(s => s.length))
          ].join("|")
        '''),
        '4|3|[a-b-a-c]|4|2|2|99|2|ABAC|4|1',
      );
    });

    test('toMap 鍵重複丟 IllegalStateException，有合併函式就合併', () {
      expect(
        eval(r'''
          var C = Packages.java.util.stream.Collectors;
          var src = ["a", "b", "a"];
          var message;
          try { src.stream().collect(C.toMap(s => s, s => 1)); }
          catch (e) { message = e.message; }
          var merged = src.stream().collect(C.toMap(s => s, s => 1, (x, y) => x + y));
          [message, merged.get("a"), merged.get("b")].join("|")
        '''),
        'java.lang.IllegalStateException: Duplicate key a '
        '(attempted merging values 1 and 1)|2|1',
      );
    });

    test('forEach、count、findFirst、anyMatch、allMatch、noneMatch', () {
      expect(
        eval(r'''
          var seen = [];
          var src = [3, 1, 2];
          src.stream().forEach(n => seen.push(n));
          var first = src.stream().findFirst();
          var none = [].stream().findFirst();
          [seen.join(""), src.stream().count(), first.isPresent(), first.get(),
           none.isPresent(), none.orElse("無"), String(none),
           src.stream().anyMatch(n => n > 2), src.stream().allMatch(n => n > 2),
           src.stream().noneMatch(n => n > 5), [].stream().allMatch(n => false),
           String(first)].join("|")
        '''),
        '312|3|true|3|false|無|Optional.empty|true|false|true|true|Optional[3]',
      );
    });

    test('sorted 穩定、distinct、limit、skip、peek、flatMap', () {
      expect(
        eval(r'''
          var items = [{k: 2, n: "a"}, {k: 1, n: "b"}, {k: 2, n: "c"}, {k: 1, n: "d"}];
          var byKey = items.stream().sorted((a, b) => a.k - b.k).map(o => o.n).toList().join("");
          var natural = ["b", "C", "a", "B"].stream().sorted().toList().join("");
          var numbers = [3, 1, 2].stream().sorted().toList().join("");
          var distinct = ["a", 1, "1", 1, "a", null, null].stream().distinct().count();
          var peeked = [];
          var limited = [1, 2, 3, 4].stream().peek(n => peeked.push(n)).limit(2).toList().join("");
          var skipped = [1, 2, 3, 4].stream().skip(3).toList().join("");
          var flat = [[1, 2], [3], []].stream().flatMap(l => l.stream()).toList().join("");
          [byKey, natural, numbers, distinct, peeked.join(""), limited, skipped, flat].join("|")
        '''),
        'bdac|BCab|123|4|12|12|4|123',
      );
    });

    test('reduce、min、max、基本型別 Stream', () {
      expect(
        eval(r'''
          var S = Packages.java.util.stream;
          var src = [3, 1, 2];
          [src.stream().reduce(0, (a, b) => a + b),
           src.stream().reduce((a, b) => a * b).get(),
           [].stream().reduce((a, b) => a + b).isPresent(),
           src.stream().min((a, b) => a - b).get(),
           src.stream().max((a, b) => a - b).get(),
           src.stream().mapToInt(n => n).sum(),
           src.stream().mapToInt(n => n).max().getAsInt(),
           src.stream().mapToInt(n => n).average().getAsDouble(),
           String(src.stream().mapToInt(n => n).max()),
           String([].stream().mapToDouble(n => n).average()),
           S.IntStream.range(0, 4).boxed().toList().join(""),
           S.IntStream.rangeClosed(1, 3).mapToObj(n => "n" + n).toList().join(""),
           S.Stream.of("x", "y").toList().join(""),
           S.Stream.iterate(1, n => n * 2).limit(5).toList().join(","),
           S.Stream.iterate(1, n => n < 20, n => n * 3).toList().join(","),
           S.Stream.concat(S.Stream.of(1), S.Stream.of(2)).toList().join(""),
           Packages.java.util.Arrays.stream([1, 2, 3]).sum()
          ].join("|")
        '''),
        '6|6|false|1|3|6|3|2|OptionalInt[3]|OptionalDouble.empty|0123|n1n2n3|'
        'xy|1,2,4,8,16|1,3,9|12|6',
      );
    });

    test('惰性：沒有最後一步不跑，limit 之後不再取；takeWhile、dropWhile', () {
      expect(
        eval(r'''
          var S = Packages.java.util.stream;
          var calls = 0;
          [1, 2, 3].stream().map(n => { calls++; return n; });
          var before = calls;
          var generated = 0;
          S.Stream.generate(() => ++generated).limit(3).toList();
          [before, generated,
           [1, 2, 5, 1].stream().takeWhile(n => n < 3).toList().join(""),
           [1, 2, 5, 1].stream().dropWhile(n => n < 3).toList().join("")
          ].join("|")
        '''),
        '0|3|12|51',
      );
    });

    test('Stream 只能接一次；iterator 與 toArray', () {
      expect(
        eval(r'''
          var stream = [1, 2].stream();
          stream.map(n => n);
          var errors = [];
          try { stream.count(); } catch (e) { errors.push(e.message); }
          try { [1].stream().limit(-1); } catch (e) { errors.push(e.message); }
          try { [].stream().findFirst().get(); } catch (e) { errors.push(e.message); }
          try { [null].stream().findFirst(); } catch (e) { errors.push(e.message); }
          var it = [7, 8].stream().iterator(), got = "";
          while (it.hasNext()) got += it.next();
          errors.concat([got, [1, 2].stream().toArray().length]).join("|")
        '''),
        'java.lang.IllegalStateException: stream has already been operated '
        'upon or closed|java.lang.IllegalArgumentException: -1|'
        'java.util.NoSuchElementException: No value present|'
        'java.lang.NullPointerException|78|2',
      );
    });

    test('map 交回 undefined 當 null，filter 可以濾掉', () {
      expect(
        eval(r'''
          var out = ["a", "b"].stream().map(s => s == "a" ? undefined : s).toList();
          [out.size(), out.get(0) === null, out.stream().filter(s => s != null).count()].join("|")
        '''),
        '2|true|1',
      );
    });
  });

  test('📖 蓝海搜书的目錄規則：result.stream().map().filter().toList()', () async {
    // 夜讀交給目錄規則的 result 是 Jsoup Elements，stream() 交回的清單再
    // 交給 chapterName、chapterUrl 解析。
    final source = BookSource.fromJson({
      'bookSourceName': '蓝海搜书',
      'bookSourceUrl': 'https://site.test',
      'ruleToc': {
        'chapterList':
            'class.ch\n@js:(function(){\n'
            '    result.sort(function(a, b){ return a.attr("data-x") - b.attr("data-x"); });\n'
            '    return result.stream().map(e => e.select("a").first())'
            '.filter(e => e != null).toList();\n})()',
        'chapterName': 'text',
        'chapterUrl': 'href',
      },
    });
    const tocHtml = '''
<html><body>
<div class="ch" data-x="3"><a href="/3.html">第三章</a></div>
<div class="ch" data-x="2"><span>沒有連結</span></div>
<div class="ch" data-x="1"><a href="/1.html">第一章</a></div>
</body></html>''';
    final result = await ChapterListParser.parse(
      source: source,
      book: Book(
        bookUrl: 'https://site.test/book',
        origin: 'https://site.test',
        name: '書',
      ),
      body: tocHtml,
      baseUrl: 'https://site.test/book/',
    );
    expect(result.chapters.map((c) => c.title), ['第一章', '第三章']);
    expect(result.chapters.first.url, 'https://site.test/1.html');
  }, skip: skip);
}
