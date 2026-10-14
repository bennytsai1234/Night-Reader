import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/search_book.dart';

/// 合併卡預設開哪個來源：最新章節最新的，一樣新取回得快的。
void main() {
  SearchBook book(
    String origin, {
    String? latest,
    int respondTime = 0,
    int order = 0,
    String? cover,
    String? intro,
  }) => SearchBook(
    bookUrl: '$origin/book',
    name: '夜讀',
    author: '作者',
    origin: origin,
    originName: origin,
    originOrder: order,
    latestChapterTitle: latest,
    respondTime: respondTime,
    coverUrl: cover,
    intro: intro,
  );

  test('the source with the newest chapter wins, in digits or Chinese '
      'numerals', () {
    final card = SearchBook.aggregate([
      book('a', latest: '第998章 前夜', respondTime: 100),
      book('b', latest: '第一千零二章 決戰', respondTime: 900),
      book('c', latest: '番外 後日談', respondTime: 50),
    ]);

    expect(card.origin, 'b');
    expect(card.latestChapterTitle, '第一千零二章 決戰');
    expect(card.origins, hasLength(3));
  });

  test('equally new sources fall back to the faster one, then source '
      'order', () {
    expect(
      SearchBook.aggregate([
        book('slow', latest: '第10章', respondTime: 800),
        book('fast', latest: '第10章', respondTime: 120),
      ]).origin,
      'fast',
    );
    expect(
      SearchBook.aggregate([
        book('second', respondTime: 0, order: 2),
        book('first', respondTime: 0, order: 1),
      ]).origin,
      'first',
    );
  });

  test('details the chosen source lacks are filled from the others', () {
    final card = SearchBook.aggregate([
      book('a', latest: '第2章', cover: 'https://img/a.jpg', intro: '簡介'),
      book('b', latest: '第3章'),
    ]);

    expect(card.origin, 'b');
    expect(card.coverUrl, 'https://img/a.jpg');
    expect(card.intro, '簡介');
  });
}
