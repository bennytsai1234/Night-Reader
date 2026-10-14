import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/features/search/search_model.dart';

/// 繁簡通搜：輸入哪一種寫法都搜兩邊，兩邊回傳的同一本書併成一張。
void main() {
  setUpAll(() {
    ChineseUtils.initializeFromDictionaryData([
      for (final path in ChineseUtils.dictionaryAssetPaths)
        File(path).readAsStringSync(),
    ]);
  });

  SearchBook book(String origin, String name, String author) => SearchBook(
    bookUrl: '$origin/book',
    name: name,
    author: author,
    origin: origin,
    originName: origin,
  );

  test('a traditional keyword is also searched in simplified', () {
    expect(searchKeyVariants('鬥羅大陸'), ['鬥羅大陸', '斗罗大陆']);
    expect(searchKeyVariants('斗罗大陆'), ['斗罗大陆', '斗羅大陸']);
    expect(searchKeyVariants('abc'), ['abc']);
  });

  test('the same book from a traditional and a simplified site is one card '
      'that matches the keyword exactly', () {
    final cards = SearchModel.aggregateForTest(
      [
        book('https://tw.example', '鬥羅大陸', '唐家三少'),
        book('https://cn.example', '斗罗大陆', '唐家三少'),
        book('https://cn.example', '斗罗大陆外传', '唐家三少'),
      ],
      '鬥羅大陸',
      false,
    );

    expect(cards, hasLength(2));
    expect(cards.first.origins, hasLength(2));
    expect(searchRelevanceRank(cards.first, '鬥羅大陸'), 0);
    expect(searchRelevanceRank(cards.last, '鬥羅大陸'), 1);
  });
}
