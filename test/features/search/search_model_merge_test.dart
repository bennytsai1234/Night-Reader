import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/features/search/search_model.dart';

/// 跨源合併（呈現層）相關測試。
///
/// 透過 [SearchModel.rebuildForTest] 直接驅動重算式合併演算法，
/// 不涉及網路與資料庫，純驗證分組 / 作者缺失三分支 / representative 選擇 /
/// 漸進重算行為。
void main() {
  SearchBook book({
    required String name,
    String? author,
    required String origin,
    String? originName,
    String? bookUrl,
    String? coverUrl,
    String? latestChapterTitle,
    int originOrder = 0,
  }) {
    return SearchBook(
      bookUrl: bookUrl ?? '$origin/$name',
      name: name,
      author: author,
      origin: origin,
      originName: originName ?? origin,
      coverUrl: coverUrl,
      latestChapterTitle: latestChapterTitle,
      originOrder: originOrder,
    );
  }

  group('跨源合併 — 同名同作者', () {
    test('不同書源的同名同作者合併成一張卡，origins 累計', () {
      final results = SearchModel.aggregateForTest([
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://a', originName: 'A'),
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://b', originName: 'B'),
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://c', originName: 'C'),
      ], '劍來', false);

      expect(results, hasLength(1));
      final card = results.single;
      expect(card.origins, hasLength(3));
      expect(card.origins, containsAll(['src://a', 'src://b', 'src://c']));
      expect(card.sourceLabels, containsAll(['A', 'B', 'C']));
    });

    test('不同書名不會被合併', () {
      final results = SearchModel.aggregateForTest([
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://a'),
        book(name: '雪中悍刀行', author: '烽火戲諸侯', origin: 'src://b'),
      ], '烽火戲諸侯', false);

      expect(results, hasLength(2));
    });

    test('同源去重：同源同名同作者只算一個 origin', () {
      final results = SearchModel.aggregateForTest([
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://a', bookUrl: 'u1'),
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://a', bookUrl: 'u2'),
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://b', bookUrl: 'u3'),
      ], '劍來', false);

      expect(results, hasLength(1));
      expect(results.single.origins, hasLength(2));
    });

    test('同源同 bookUrl 去重', () {
      final results = SearchModel.aggregateForTest([
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://a', bookUrl: 'U1'),
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://a', bookUrl: 'u1'),
      ], '劍來', false);

      expect(results, hasLength(1));
      expect(results.single.origins, hasLength(1));
    });
  });

  group('representative 選擇', () {
    test('originOrder 最前者優先', () {
      final results = SearchModel.aggregateForTest([
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://b', originOrder: 5),
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://a', originOrder: 1),
      ], '劍來', false);

      expect(results.single.origin, 'src://a');
    });

    test('優先有封面者，即使 originOrder 較後', () {
      final results = SearchModel.aggregateForTest([
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://a', originOrder: 1),
        book(
          name: '劍來',
          author: '烽火戲諸侯',
          origin: 'src://b',
          originOrder: 5,
          coverUrl: 'http://cover/b.jpg',
          latestChapterTitle: '最終章',
        ),
      ], '劍來', false);

      final card = results.single;
      // representative 是有封面的 b → 卡片封面 / 最新章 / origin 都來自 b
      expect(card.origin, 'src://b');
      expect(card.coverUrl, 'http://cover/b.jpg');
      expect(card.latestChapterTitle, '最終章');
    });

    test('多個有封面者取 originOrder 最前的有封面者', () {
      final results = SearchModel.aggregateForTest([
        book(
          name: '劍來',
          author: '烽火戲諸侯',
          origin: 'src://c',
          originOrder: 9,
          coverUrl: 'http://cover/c.jpg',
        ),
        book(
          name: '劍來',
          author: '烽火戲諸侯',
          origin: 'src://b',
          originOrder: 3,
          coverUrl: 'http://cover/b.jpg',
        ),
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://a', originOrder: 1),
      ], '劍來', false);

      expect(results.single.origin, 'src://b');
    });

    test('全無封面退回 originOrder 最前者', () {
      final results = SearchModel.aggregateForTest([
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://b', originOrder: 5),
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://a', originOrder: 2),
      ], '劍來', false);

      expect(results.single.origin, 'src://a');
    });
  });

  group('作者缺失三分支', () {
    test('書名只有 1 個作者 → 缺作者同名書併入該作者群組', () {
      final results = SearchModel.aggregateForTest([
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://a', originName: 'A'),
        book(name: '劍來', author: null, origin: 'src://b', originName: 'B'),
      ], '劍來', false);

      expect(results, hasLength(1));
      final card = results.single;
      expect(card.author, '烽火戲諸侯');
      expect(card.origins, containsAll(['src://a', 'src://b']));
    });

    test('書名完全沒人有作者 → 同名缺作者書併成一張「作者不詳」卡', () {
      final results = SearchModel.aggregateForTest([
        book(name: '劍來', author: null, origin: 'src://a', originName: 'A'),
        book(name: '劍來', author: '', origin: 'src://b', originName: 'B'),
      ], '劍來', false);

      expect(results, hasLength(1));
      final card = results.single;
      expect((card.author ?? '').trim(), isEmpty);
      expect(card.origins, containsAll(['src://a', 'src://b']));
    });

    test('書名有 ≥2 個不同作者 → 缺作者同名書退出、單獨成「作者不詳」卡', () {
      final results = SearchModel.aggregateForTest([
        book(name: '劍來', author: '作者甲', origin: 'src://a'),
        book(name: '劍來', author: '作者乙', origin: 'src://b'),
        book(name: '劍來', author: null, origin: 'src://c'),
      ], '劍來', false);

      // 兩個有作者群組 + 一張作者不詳卡
      expect(results, hasLength(3));
      final authors =
          results.map((b) => (b.author ?? '').trim()).toList()..sort();
      expect(authors, ['', '作者乙', '作者甲']..sort());
      // 缺作者書沒有被硬塞進任一作者群組
      final undated = results.firstWhere((b) => (b.author ?? '').trim().isEmpty);
      expect(undated.origins, ['src://c']);
    });
  });

  group('漸進重算 / 唯一性轉換', () {
    test('唯一作者時缺作者書併入；出現第二作者後缺作者書退出', () {
      // 第一次：只有作者甲 + 缺作者書 → 併入作者甲
      var results = SearchModel.aggregateForTest([
        book(name: '劍來', author: '作者甲', origin: 'src://a'),
        book(name: '劍來', author: null, origin: 'src://c'),
      ], '劍來', false);
      var jiaCard = results.firstWhere((b) => b.author == '作者甲');
      expect(jiaCard.origins, containsAll(['src://a', 'src://c']));
      expect(results.where((b) => (b.author ?? '').trim().isEmpty), isEmpty);

      // 第二次（新增第二作者源）：從頭重算 → 缺作者書退出成獨立卡
      results = SearchModel.aggregateForTest([
        book(name: '劍來', author: '作者甲', origin: 'src://a'),
        book(name: '劍來', author: null, origin: 'src://c'),
        book(name: '劍來', author: '作者乙', origin: 'src://b'),
      ], '劍來', false);

      expect(results, hasLength(3));
      jiaCard = results.firstWhere((b) => b.author == '作者甲');
      expect(jiaCard.origins, ['src://a']); // 不再含 c
      final undated = results.firstWhere((b) => (b.author ?? '').trim().isEmpty);
      expect(undated.origins, ['src://c']);
    });

    test('SearchModel 漸進回傳：每源 append 後從頭重建', () {
      final model = SearchModel(callback: _NoopCallback());

      model.mergeForTest([
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://a', originName: 'A'),
      ], '劍來', false);
      expect(model.searchBooksForTest, hasLength(1));
      expect(model.searchBooksForTest.single.origins, ['src://a']);

      model.mergeForTest([
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://b', originName: 'B'),
      ], '劍來', false);
      expect(model.searchBooksForTest, hasLength(1));
      expect(
        model.searchBooksForTest.single.origins,
        containsAll(['src://a', 'src://b']),
      );
    });
  });

  group('三級相關度排序與精準搜尋', () {
    test('完全 > 包含 > 其他，組內 origins.length 降序', () {
      final results = SearchModel.aggregateForTest([
        // 包含級，1 源
        book(name: '劍來番外', author: '烽火戲諸侯', origin: 'src://x'),
        // 完全級，2 源
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://a', originName: 'A'),
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://b', originName: 'B'),
        // 其他級，1 源
        book(name: '雪中悍刀行', author: '烽火戲諸侯', origin: 'src://y'),
      ], '劍來', false);

      expect(results.map((b) => normalizeSearchText(b.name)).toList(), [
        normalizeSearchText('劍來'),
        normalizeSearchText('劍來番外'),
        normalizeSearchText('雪中悍刀行'),
      ]);
      expect(results.first.origins, hasLength(2));
    });

    test('精準搜尋丟棄「其他」級', () {
      final results = SearchModel.aggregateForTest([
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://a'),
        book(name: '雪中悍刀行', author: '烽火戲諸侯', origin: 'src://y'),
      ], '劍來', true);

      expect(results, hasLength(1));
      expect(normalizeSearchText(results.single.name), normalizeSearchText('劍來'));
    });

    test('完全匹配級內按 origins.length 降序', () {
      final results = SearchModel.aggregateForTest([
        book(name: '劍來', author: '烽火戲諸侯', origin: 'src://a', originName: 'A'),
        book(name: '劍來', author: '貓膩', origin: 'src://b', originName: 'B'),
        book(name: '劍來', author: '貓膩', origin: 'src://c', originName: 'C'),
      ], '劍來', false);

      // 「貓膩」群組 2 源在前，「烽火戲諸侯」1 源在後
      expect(results, hasLength(2));
      expect(results.first.author, '貓膩');
      expect(results.first.origins, hasLength(2));
      expect(results.last.author, '烽火戲諸侯');
    });
  });
}

class _NoopCallback implements SearchModelCallback {
  @override
  void onSearchStart() {}
  @override
  void onSearchSuccess(List<SearchBook> searchBooks) {}
  @override
  void onSearchFailure(SearchFailure failure) {}
  @override
  void onSearchFinish({required bool isEmpty}) {}
  @override
  void onSearchProgress({
    required String currentSource,
    required int completed,
    required int total,
    required int failed,
  }) {}
}
