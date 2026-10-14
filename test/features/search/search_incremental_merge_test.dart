import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/features/search/search_model.dart';

/// 搜尋結果逐個書源併入時只重算有變動的書名；結果要和一次全部分組相同。
void main() {
  setUpAll(() {
    ChineseUtils.initializeFromDictionaryData([
      for (final path in ChineseUtils.dictionaryAssetPaths)
        File(path).readAsStringSync(),
    ]);
  });

  SearchBook book(String origin, String name, String? author) => SearchBook(
    bookUrl: '$origin/$name',
    name: name,
    author: author,
    origin: origin,
    originName: origin,
  );

  String describe(SearchBook card) =>
      '${card.name}/${card.author}/${card.origins.join(',')}';

  test('merging source by source gives the same cards as grouping at once', () {
    final batches = [
      [book('a', '系統', null), book('a', '修仙系統', '甲')],
      // 書名只有一位作者：缺作者的同名書併進去。
      [book('b', '系統', '甲'), book('b', '劍俠', null)],
      // 出現第二位作者：缺作者的書退出，自成一張。
      [book('c', '系統', '乙'), book('c', '修仙系统', '甲')],
      [book('d', '劍俠', null), book('d', '超級系統', '丙')],
    ];
    final model = SearchModel(callback: const _SilentCallback());
    for (final batch in batches) {
      model.mergeForTest(batch, '系統', false);
    }

    final atOnce = SearchModel.aggregateForTest(
      [for (final batch in batches) ...batch],
      '系統',
      false,
    );
    expect(
      model.searchBooksForTest.map(describe).toList(),
      atOnce.map(describe).toList(),
    );
    expect(
      atOnce.where((card) => card.name == '系統').map((card) => card.author),
      containsAll(['甲', '乙', null]),
    );
  });
}

class _SilentCallback implements SearchModelCallback {
  const _SilentCallback();

  @override
  void noSuchMethod(Invocation invocation) {}
}
