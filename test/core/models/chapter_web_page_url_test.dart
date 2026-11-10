// 書源膠囊開的網頁：章節的絕對網址，去掉 Legado 的網址選項；不是網頁時沒有。

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/chapter.dart';

void main() {
  test('絕對網址照用', () {
    expect(
      BookChapter(url: 'https://example.com/book/1.html').webPageUrl,
      'https://example.com/book/1.html',
    );
  });

  test('相對網址照章節的基礎網址補成絕對', () {
    expect(
      BookChapter(
        url: '/book/1.html',
        baseUrl: 'https://example.com/book/',
      ).webPageUrl,
      'https://example.com/book/1.html',
    );
  });

  test('去掉 Legado 的網址選項', () {
    expect(
      BookChapter(
        url: 'https://api.example.com/chapter?id=7 , {"method":"POST","body":"a=1"}',
      ).webPageUrl,
      'https://api.example.com/chapter?id=7',
    );
  });

  test('本地書與 data: 沒有網頁', () {
    expect(BookChapter(url: 'local_1').webPageUrl, isNull);
    expect(BookChapter(url: 'data:text/plain,abc').webPageUrl, isNull);
    expect(BookChapter().webPageUrl, isNull);
  });
}
