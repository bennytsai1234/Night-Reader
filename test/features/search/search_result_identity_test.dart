import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/features/search/search_model.dart';

void main() {
  SearchBook book(String url, String name, String? author) => SearchBook(
    bookUrl: url,
    name: name,
    author: author,
    origin: url,
    originName: '書源',
  );

  test('a merged card keeps its identity when another source becomes the '
      'representative', () {
    final first = book('https://a.example/1', '夜讀', '作者');
    final second = book('https://b.example/9', ' 夜讀 ', '作者');

    expect(searchResultIdentity(first), searchResultIdentity(second));
  });

  test('different authors of the same title are different cards', () {
    expect(
      searchResultIdentity(book('u1', '夜讀', '甲')),
      isNot(searchResultIdentity(book('u2', '夜讀', '乙'))),
    );
  });
}
