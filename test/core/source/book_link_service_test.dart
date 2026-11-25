import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source/book_link_service.dart';
import 'package:night_reader/core/source/book_source_service.dart';

/// 詳情抓得到：書名照書源寫；[failing] 的書源抓不到。
class _Details extends BookSourceService {
  _Details({this.failing = const {}});

  final Set<String> failing;
  final asked = <String>[];

  @override
  Future<Book> getBookInfo(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) async {
    asked.add(source.bookSourceUrl);
    if (failing.contains(source.bookSourceUrl)) throw StateError('抓不到');
    return book.copyWith(name: '${source.bookSourceName}的書', author: '某人');
  }
}

void main() {
  late AppDatabase db;
  late BookSourceDao sources;
  late BookDao books;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sources = BookSourceDao(db);
    books = BookDao(db);
  });

  tearDown(() => db.close());

  BookSource source(
    String url, {
    String? pattern,
    bool enabled = true,
    int order = 0,
    int type = 0,
  }) => BookSource(
    bookSourceUrl: url,
    bookSourceName: Uri.parse(url).host,
    bookUrlPattern: pattern,
    enabled: enabled,
    customOrder: order,
    bookSourceType: type,
  );

  BookLinkService service(BookSourceService details) =>
      BookLinkService(sourceDao: sources, bookDao: books, service: details);

  test('照網址的網站找啟用的書源，抓詳情', () async {
    await sources.upsert(source('https://a.example', type: 2));
    await sources.upsert(source('https://b.example'));

    final book = await service(_Details()).findBook('https://a.example/book/1');

    expect(book.bookUrl, 'https://a.example/book/1');
    expect(book.origin, 'https://a.example');
    expect(book.originName, 'a.example');
    expect(book.name, 'a.example的書');
    expect(book.type, 2, reason: '書的類別照書源（ADR 0053）');
  });

  test('網站對不上時照書源的詳情頁網址規則找，整個網址都符合才算', () async {
    await sources.upsert(
      source('https://x.example', pattern: r'https://m\.site/b/\d+', order: 2),
    );
    await sources.upsert(
      source('https://y.example', pattern: r'https://m\.site/b/\d+', order: 1),
    );
    await sources.upsert(source('https://z.example', pattern: r'm\.site'));
    final details = _Details(failing: {'https://y.example'});

    final book = await service(details).findBook('https://m.site/b/42');

    // 排序在前的抓不到詳情，換下一個符合的；只符合一部分的不算。
    expect(details.asked, ['https://y.example', 'https://x.example']);
    expect(book.origin, 'https://x.example');
  });

  test('網址自己註明書源（`網址,{"origin": …}`）時先用它', () async {
    await sources.upsert(source('https://a.example'));
    await sources.upsert(source('https://named.example', enabled: false));
    const url = 'https://a.example/book/1,{"origin":"https://named.example"}';

    final book = await service(_Details()).findBook(url);

    expect(book.origin, 'https://named.example');
    expect(book.bookUrl, url);
  });

  test('加入書架：記成在書架上，整本下載交給書架自動下載', () async {
    await sources.upsert(source('https://a.example'));
    final links = service(_Details());
    final book = await links.findBook('https://a.example/book/1');

    await links.addToShelf(book);

    final saved = (await books.getByUrl('https://a.example/book/1'))!;
    expect(saved.isInBookshelf, isTrue);
    expect(saved.syncTime, greaterThan(0));
    expect(saved.name, 'a.example的書');
  });

  test('找不到書源、沒啟用、已在書架與不是網址時說原因', () async {
    await sources.upsert(source('https://off.example', enabled: false));
    await books.upsert(
      Book(
        bookUrl: 'https://off.example/1',
        origin: 'https://off.example',
        name: '書架上的',
        isInBookshelf: true,
      ),
    );

    Future<String> reason(String url) async {
      try {
        await service(_Details()).findBook(url);
        return '';
      } on BookLinkException catch (error) {
        return error.message;
      }
    }

    expect(await reason('https://off.example/2'), '找不到符合這個網址的書源');
    expect(await reason('https://off.example/1'), '《書架上的》已經在書架上');
    expect(await reason('not a url'), '書的網址格式不對');
  });
}
