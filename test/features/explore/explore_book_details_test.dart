import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/features/explore/explore_book_details.dart';

void main() {
  final source = BookSource(
    bookSourceUrl: 'https://s.example',
    bookSourceName: '書源',
  );

  SearchBook book(int i, {String? cover, String? words}) => SearchBook(
    bookUrl: 'https://s.example/book/$i',
    name: '書$i',
    author: '作者',
    origin: source.bookSourceUrl,
    coverUrl: cover,
    wordCount: words,
  );

  /// 每一本書的請求停在自己的 completer 上，由測試決定何時回來。
  final calls = <String, Completer<ExploreBookExtras>>{};
  final tokens = <String, CancelToken?>{};
  Future<ExploreBookExtras> loader(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) {
    tokens[book.bookUrl] = cancelToken;
    return (calls[book.bookUrl] = Completer()).future;
  }

  setUp(() {
    calls.clear();
    tokens.clear();
  });

  /// 讓 [ExploreBookDetails] 用 `Timer.run` 排的送出跑完。
  Future<void> idle() => Future<void>.delayed(const Duration(milliseconds: 5));

  test('at most four books are fetched at once, each only once', () async {
    final details = ExploreBookDetails(loader: loader);
    addTearDown(details.dispose);
    for (var i = 0; i < 6; i++) {
      details.shown(source, book(i));
    }
    // 同一本又畫一次（捲回來）不再排。
    details.shown(source, book(0));
    await idle();
    expect(calls.keys, hasLength(ExploreBookDetails.maxConcurrent));

    calls['https://s.example/book/0']!.complete((
      coverUrl: 'https://s.example/c/0.jpg',
      wordCount: '12.3萬字',
    ));
    await idle();
    expect(calls.keys, hasLength(5));
    expect(
      details.extrasOf('https://s.example/book/0').value?.wordCount,
      '12.3萬字',
    );

    details.shown(source, book(0));
    await idle();
    expect(calls.keys, hasLength(5));
  });

  test('a book with a cover and a word count is not fetched', () async {
    final details = ExploreBookDetails(loader: loader);
    addTearDown(details.dispose);
    details.shown(source, book(0, cover: 'https://c/0.jpg', words: '3萬字'));
    // 字數欄沒有、分類裡有「…字」的也算有字數，和清單的寫法一樣。
    details.shown(source, book(1, cover: 'https://c/1.jpg')..kind = '玄幻,25萬字');
    await idle();
    expect(calls, isEmpty);
  });

  test('a queued book scrolled away is not fetched', () async {
    final details = ExploreBookDetails(loader: loader);
    addTearDown(details.dispose);
    for (var i = 0; i < 5; i++) {
      details.shown(source, book(i));
    }
    await idle();
    details.hidden('https://s.example/book/4');
    calls['https://s.example/book/0']!.complete((coverUrl: '', wordCount: ''));
    await idle();
    expect(calls.keys, isNot(contains('https://s.example/book/4')));

    // 再畫出來時重新排。
    details.shown(source, book(4));
    await idle();
    expect(calls.keys, contains('https://s.example/book/4'));
  });

  test('leaving the page cancels the requests in flight', () async {
    final details = ExploreBookDetails(loader: loader);
    for (var i = 0; i < 6; i++) {
      details.shown(source, book(i));
    }
    await idle();
    details.dispose();
    expect(tokens.values.every((token) => token!.isCancelled), isTrue);
    await idle();
    expect(calls.keys, hasLength(ExploreBookDetails.maxConcurrent));
  });

  test('only the missing fields are filled in', () {
    const extras = (coverUrl: 'https://c/new.jpg', wordCount: '8.8萬字');
    final withCover = book(0, cover: 'https://c/own.jpg');
    final filled = ExploreBookDetails.withExtras(withCover, extras);
    expect(filled.coverUrl, 'https://c/own.jpg');
    expect(filled.wordCount, '8.8萬字');

    final complete = book(1, cover: 'https://c/own.jpg', words: '1萬字');
    expect(ExploreBookDetails.withExtras(complete, extras), same(complete));
  });
}
