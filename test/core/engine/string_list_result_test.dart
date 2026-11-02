import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../test_helper.dart';

/// `getStringList` 只有文字與清單算結果，同 Legado `AnalyzeRule.getStringList`
/// （`result is String` 才拆行、`result is List<*>` 才逐項取用，其他的丟掉）。
/// 📖Lofter 的下一頁正文網址規則在 `try` 裡先把 API 回應 `JSON.parse` 存進
/// `$`，下一行讀 `$.data.gainReturnGifts.length` 出錯被 `catch` 吃掉，整段
/// 程式的值就是那個物件；夜讀把它轉成 Dart 的 `{code: 400, …}` 當網址送出。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  AnalyzeRule rule() =>
      AnalyzeRule(source: BookSource(bookSourceUrl: 'https://l.test'))
          .setContent('{"a":1}', baseUrl: 'https://l.test/detail');

  test('JS 交回物件（try 裡存了回應、後面出錯被吃掉）時沒有下一頁', () {
    const lofter = '''<js>
try{
  \$ = JSON.parse('{"code":400,"data":{},"ok":false}');
  l = \$.data.gainReturnGifts.length ? 1 : 2;
}catch(e){}
</js>''';
    expect(rule().getStringList(lofter, isUrl: true), isEmpty);
    expect(rule().getStringList(lofter), isEmpty);
  });

  test('JS 交回物件、數字、布林都沒有結果', () {
    expect(rule().getStringList('@js:({a:1})', isUrl: true), isEmpty);
    expect(rule().getStringList('@js:1', isUrl: true), isEmpty);
    expect(rule().getStringList('@js:true'), isEmpty);
  });

  test('JS 交回文字與清單照舊', () {
    expect(rule().getStringList('@js:"/p2\\n/p3"', isUrl: true), [
      'https://l.test/p2',
      'https://l.test/p3',
    ]);
    expect(rule().getStringList('@js:["/p2","/p3"]', isUrl: true), [
      'https://l.test/p2',
      'https://l.test/p3',
    ]);
    expect(rule().getStringList('@js:["a","b"]'), ['a', 'b']);
  });
}
