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

/// 詳情抓得到：書名照書源寫；[failing] 的書源抓不到；[hanging] 時一直等到
/// 被取消。
class _Details extends BookSourceService {
  _Details({this.failing = const {}, this.hanging = false});

  final Set<String> failing;
  final bool hanging;
  final asked = <String>[];
  final askedUrls = <String>[];

  @override
  Future<Book> getBookInfo(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) async {
    asked.add(source.bookSourceUrl);
    askedUrls.add(book.bookUrl);
    if (hanging) {
      await cancelToken!.whenCancel;
      throw cancelToken.cancelError!;
    }
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

  Future<String> reason(BookLinkService links, String url) async {
    try {
      await links.findBook(url);
      return '';
    } on BookLinkException catch (error) {
      return error.message;
    }
  }

  test('網址自己註明書源（`網址,{"origin": …}`）時先用它，存的網址不帶選項', () async {
    await sources.upsert(source('https://a.example'));
    await sources.upsert(source('https://named.example#2', enabled: false));
    final details = _Details();
    const url =
        'https://named.example/book/1,{"origin":"https://named.example#2"}';

    final book = await service(details).findBook(url);

    expect(book.origin, 'https://named.example#2');
    expect(book.bookUrl, 'https://named.example/book/1');
    expect(details.askedUrls, ['https://named.example/book/1']);
  });

  test('網址選項只認 origin：標頭、js、retry 這些不照著送', () async {
    await sources.upsert(source('https://a.example'));
    final details = _Details();
    const url =
        'https://a.example/book/1,{"headers":{"Cookie":"x"},"js":"java.ajax(1)",'
        '"retry":9,"method":"POST","body":"a=1","webView":true}';

    final book = await service(details).findBook(url);

    expect(details.askedUrls, ['https://a.example/book/1']);
    expect(book.bookUrl, 'https://a.example/book/1');
  });

  test('網址裡有規則 JS（`{{}}`、`<js>`、`@js:`）或反斜線的不抓', () async {
    await sources.upsert(source('https://a.example'));
    final details = _Details();
    final links = service(details);

    for (final url in [
      "https://a.example/{{java.ajax('https://evil.example')}}",
      'https://a.example/b<JS>java.ajax(1)</js>',
      'https://a.example/b@js:java.ajax(1)',
      r'https://a.example\@b.example/1',
    ]) {
      expect(await reason(links, url), '書的網址格式不對', reason: url);
    }
    expect(details.asked, isEmpty);
  });

  test('註明的書源和網址不是同一個網站、也不符合它的詳情頁網址規則時不抓', () async {
    await sources.upsert(source('https://named.example'));
    await sources.upsert(source('https://evil.example'));
    final details = _Details();
    final links = service(details);

    for (final site in [
      'https://evil.example',
      'https://named.example@evil.example',
      'https://named.example.evil.example',
    ]) {
      final url = '$site/book/1,{"origin":"https://named.example"}';
      expect(await reason(links, url), '連結指定的書源和書的網址不是同一個網站', reason: site);
    }
    expect(details.asked, isEmpty, reason: '帶著書源的登入資料去抓別的網站');
  });

  test('註明的書源的詳情頁網址規則符合時照樣用它', () async {
    await sources.upsert(
      source('https://named.example', pattern: r'https://m\.site/b/\d+'),
    );
    final details = _Details();

    final book = await service(details)
        .findBook('https://m.site/b/42,{"origin":"https://named.example"}');

    expect(book.origin, 'https://named.example');
    expect(details.askedUrls, ['https://m.site/b/42']);
  });

  test('註明的書源不在時照 Legado 往下找', () async {
    await sources.upsert(source('https://a.example'));

    final book = await service(_Details())
        .findBook('https://a.example/book/1,{"origin":"https://gone.example"}');

    expect(book.origin, 'https://a.example');
  });

  test('取消後停下，不再試下一個書源', () async {
    await sources.upsert(source('https://a.example'));
    await sources.upsert(
      source('https://b.example', pattern: r'https://a\.example/.*'),
    );
    final details = _Details(hanging: true);
    final cancel = CancelToken();

    final found = service(details)
        .findBook('https://a.example/book/1', cancelToken: cancel);
    await Future<void>.delayed(Duration.zero);
    cancel.cancel();

    await expectLater(found, throwsA(isA<DioException>()));
    expect(details.asked, ['https://a.example']);
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

    final links = service(_Details());

    expect(await reason(links, 'https://off.example/2'), '找不到符合這個網址的書源');
    // 同 Legado `AddToBookshelfDialog`：已在書架上只提示，不開詳情。
    expect(
      await reason(links, 'https://off.example/1,{"origin":"x"}'),
      '《書架上的》已在書架',
    );
    expect(await reason(links, 'not a url'), '書的網址格式不對');
  });
}
