import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/book_info_parser.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';

import '../../../test_helper.dart';

/// 詳情頁的書名、作者什麼時候蓋掉手上的，照 Legado `BookInfo.analyzeBookInfo`：
/// 書源寫了 `canReName`，或手上的是空的，才換。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  const body = '<h1>《雪中悍刀行》最新章節</h1><p class="a">作者：烽火戲諸侯 著</p>';

  BookSource source({String? canReName}) => BookSource.fromJson({
    'bookSourceName': '詳情',
    'bookSourceUrl': 'https://d.test',
    'ruleBookInfo': {
      'name': 'tag.h1@text',
      'author': 'class.a@text##作者：',
      'canReName': ?canReName,
    },
  });

  Future<Book> parse(Book book, {String? canReName}) => BookInfoParser.parse(
    source: source(canReName: canReName),
    book: book,
    body: body,
    baseUrl: 'https://d.test/b/1',
  );

  test('從搜尋結果進詳情：沒寫 canReName 時留搜尋結果的書名與作者', () async {
    final book = await parse(
      Book(
        bookUrl: 'https://d.test/b/1',
        name: '雪中悍刀行',
        author: '烽火戲諸侯',
        origin: 'https://d.test',
      ),
    );
    expect(book.name, '雪中悍刀行');
    expect(book.author, '烽火戲諸侯');
  });

  test('寫了 canReName 就換成詳情頁的', () async {
    final book = await parse(
      Book(
        bookUrl: 'https://d.test/b/1',
        name: '雪中悍刀行',
        author: '某人',
        origin: 'https://d.test',
      ),
      canReName: '1',
    );
    expect(book.name, '《雪中悍刀行》最新章節');
    expect(book.author, '烽火戲諸侯');
  });

  test('手上沒有書名、作者時用詳情頁的', () async {
    final book = await parse(
      Book(bookUrl: 'https://d.test/b/1', origin: 'https://d.test'),
    );
    expect(book.name, '《雪中悍刀行》最新章節');
    expect(book.author, '烽火戲諸侯');
  });
}
