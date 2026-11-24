import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/chinese/chinese_utils.dart';
import 'package:night_reader/core/models/search/search_book.dart';
import 'package:night_reader/features/search/search_model.dart';

/// 精準搜尋照 Legado `SearchModel`：留書名或作者「含」關鍵字的
/// （`name.contains(searchKey) || author.contains(searchKey)`）；夜讀比之前
/// 先拿掉繁簡與空白的差別。
void main() {
  setUpAll(() {
    ChineseUtils.initializeFromDictionaryData([
      for (final path in ChineseUtils.dictionaryAssetPaths)
        File(path).readAsStringSync(),
    ]);
  });

  SearchBook book(String name, String author) => SearchBook(
    bookUrl: 'https://s.test/$name',
    name: name,
    author: author,
    origin: 'https://s.test',
  );

  test('書名或作者含關鍵字的留下（續作、外傳）', () {
    expect(matchesPrecisionSearch(book('斗羅大陸', '唐家三少'), '斗羅大陸'), isTrue);
    expect(matchesPrecisionSearch(book('斗羅大陸外傳', '唐家三少'), '斗羅大陸'), isTrue);
    expect(matchesPrecisionSearch(book('終極斗羅', '唐家三少'), '唐家'), isTrue);
    expect(matchesPrecisionSearch(book('斗罗大陆2', '唐家三少'), '斗羅大陸'), isTrue);
  });

  test('都不含的丟掉', () {
    expect(matchesPrecisionSearch(book('大陸', '某人'), '斗羅大陸'), isFalse);
    expect(matchesPrecisionSearch(book('斗破蒼穹', '天蠶土豆'), '斗羅'), isFalse);
  });

  test('精準搜尋的合併結果留「等於」與「含」兩級', () {
    final cards = SearchModel.aggregateForTest(
      [book('斗羅大陸', '唐家三少'), book('斗羅大陸外傳', '唐家三少')],
      '斗羅大陸',
      true,
    );
    expect(cards.map((c) => c.name), ['斗羅大陸', '斗羅大陸外傳']);
  });
}
