import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';

Book _book({String? intro, String? customIntro}) => Book(
  bookUrl: 'https://intro.test/b/1',
  origin: 'https://intro.test',
  name: '書名',
  intro: intro,
  customIntro: customIntro,
);

/// 書籍詳情顯示的簡介：資料庫裡改版前存下、沒整理過的簡介也要乾淨。
void main() {
  test('an intro stored with HTML tags shows as plain lines', () {
    final book = _book(
      intro: '<div id="intro"><p>第一段</p><p>第二段<br>第三段</p></div>',
    );

    expect(book.getShownIntro(), '第一段\n第二段\n第三段');
  });

  // 2026-11-18 笔趣阁 biquge345 的詳情頁：og:description 的原文寫著反斜線加 n。
  test('a literal backslash-n written by the site becomes a line break', () {
    final book = _book(
      intro: r'    【咒术回战+死灭回游】\n如果让你在与白月光修成正果，你会选哪一个？\n芥剑也没想到…',
    );

    expect(book.getShownIntro(), '【咒术回战+死灭回游】\n如果让你在与白月光修成正果，你会选哪一个？\n芥剑也没想到…');
  });

  test('an intro formatted on fetch shows without the indents', () {
    final book = _book(intro: '　　第一段\n　　第二段');

    expect(book.getShownIntro(), '第一段\n第二段');
  });

  test('the intro the reader edited is shown instead', () {
    final book = _book(intro: '書源的簡介', customIntro: '自己寫的簡介');

    expect(book.getShownIntro(), '自己寫的簡介');
  });

  test('no intro shows as empty', () {
    expect(_book().getShownIntro(), '');
  });
}
