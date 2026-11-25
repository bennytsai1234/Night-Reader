import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/content_parser.dart';
import 'package:night_reader/core/engine/web_book/illustration_fetcher.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/storage/book_illustration_storage.dart';
import 'package:night_reader/core/network/cookie_store.dart';
import 'package:night_reader/core/network/network_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../../test_helper.dart';

class _DirPathProvider extends PathProviderPlatform {
  _DirPathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

/// 不用測試環境的假連線。
class _RealHttp extends HttpOverrides {}

/// 只有開頭的 PNG（寬 300、高 200），夠讀出寬高。
final _png = Uint8List(24)
  ..setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
  ..setAll(16, [0, 0, 0x01, 0x2C, 0, 0, 0, 0xC8]);

String _dataUrl(List<int> bytes) =>
    'data:image/png;base64,${base64Encode(bytes)}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  late Directory dir;

  setUpAll(() => NetworkService().init(ephemeral: true));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('illustration_fetcher_test');
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _DirPathProvider(dir.path);
    addTearDown(() => PathProviderPlatform.instance = previous);
  });

  tearDown(() => dir.delete(recursive: true));

  final source = BookSource.fromJson({
    'bookSourceName': '插圖',
    'bookSourceUrl': 'https://u.test',
    'ruleContent': {'content': 'id.c@html'},
  });
  final book = Book(bookUrl: 'https://u.test/book/1', origin: 'https://u.test');

  test('正文留下插圖標記，網址用轉址後的補成完整網址', () async {
    final result = await ContentParser.parse(
      source: source,
      book: book,
      chapter: BookChapter(url: 'https://u.test/c/1', title: '第一章'),
      body:
          '<div id="c"><p>前文</p><p><img src="../img/1.jpg" alt="x"></p>'
          '<p>後文</p></div>',
      baseUrl: 'https://u.test/c/1',
      redirectUrl: 'https://u.test/read/1/',
    );
    expect(
      result.content,
      contains('<img src="https://u.test/read/img/1.jpg">'),
    );
    expect(result.content, contains('前文'));
    expect(result.content, contains('後文'));
  });

  test('抓到的圖存進插圖資料夾，不是圖的不存、記成確定抓不到', () async {
    final images = p.join(dir.path, 'images');
    final good = _dataUrl(_png);
    final bad = _dataUrl(utf8.encode('<html>404</html>'));
    final pending = await IllustrationFetcher.fetch(
      source,
      book,
      '甲\n<img src="$good">\n乙<img src="$bad">\n<img src="$good">',
      images,
    );
    expect(pending, 0);
    expect(
      await File(BookIllustrationStorage.pathFor(images, good)).readAsBytes(),
      _png,
    );
    expect(
      File(BookIllustrationStorage.pathFor(images, bad)).existsSync(),
      isFalse,
    );
    expect(
      File(BookIllustrationStorage.missingPathFor(images, bad)).existsSync(),
      isTrue,
    );
    expect(
      await BookIllustrationStorage.untriedSources(
        images,
        '<img src="$good"><img src="$bad">',
      ),
      isEmpty,
    );
  });

  test('連不上的圖不記成確定抓不到，下次再試', () async {
    final images = p.join(dir.path, 'images');
    // 這個埠沒有人聽，連線立刻被拒。測試環境預設把每個請求都回 400，
    // 這裡要真的連線。
    const unreachable = 'http://127.0.0.1:9/a.png';
    final pending = await HttpOverrides.runWithHttpOverrides(
      () => IllustrationFetcher.fetch(
        source,
        book,
        '<img src="$unreachable">',
        images,
      ),
      _RealHttp(),
    );
    expect(pending, 1);
    expect(
      await BookIllustrationStorage.untriedSources(
        images,
        '<img src="$unreachable">',
      ),
      [unreachable],
    );
  });

  test('取消了就丟出取消，不記成確定抓不到', () async {
    final images = p.join(dir.path, 'images');
    final bad = _dataUrl(utf8.encode('<html>404</html>'));
    final token = CancelToken()..cancel();
    await expectLater(
      IllustrationFetcher.fetch(
        source,
        book,
        '<img src="$bad">',
        images,
        cancelToken: token,
      ),
      throwsA(isA<DioException>()),
    );
    expect(
      File(BookIllustrationStorage.missingPathFor(images, bad)).existsSync(),
      isFalse,
    );
  });

  test('好幾處同時抓同一張圖，每處都算抓到，不留暫存檔', () async {
    final images = p.join(dir.path, 'images');
    final good = _dataUrl(_png);
    final results = await Future.wait([
      for (var i = 0; i < 6; i += 1)
        IllustrationFetcher.fetch(source, book, '<img src="$good">', images),
    ]);
    expect(results, everyElement(0));
    expect(Directory(images).listSync().map((f) => p.basename(f.path)), [
      BookIllustrationStorage.fileNameFor(good),
    ]);
  });

  test('確定抓不到的圖：已存的正文不再抓，重新取得這一章時再試', () async {
    final images = p.join(dir.path, 'images');
    final src = _dataUrl(_png);
    final missing = File(BookIllustrationStorage.missingPathFor(images, src));
    await missing.create(recursive: true);

    await IllustrationFetcher.fetch(
      source,
      book,
      '<img src="$src">',
      images,
      retryMissing: false,
    );
    expect(
      File(BookIllustrationStorage.pathFor(images, src)).existsSync(),
      isFalse,
    );

    await IllustrationFetcher.fetch(source, book, '<img src="$src">', images);
    expect(
      File(BookIllustrationStorage.pathFor(images, src)).existsSync(),
      isTrue,
    );
    expect(missing.existsSync(), isFalse);
  });

  test('外來正文的插圖：和書源不同主機時不帶書源的 Cookie 與登入標頭', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final seen = <String, Map<String, String>>{};
    server.listen((request) async {
      final headers = <String, String>{};
      request.headers.forEach((name, values) {
        headers[name.toLowerCase()] = values.join(', ');
      });
      seen[request.uri.path] = headers;
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(_png);
      await request.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    // 同一個伺服器換一個主機名稱：網站不同，內容相同。
    final other = 'http://localhost:${server.port}';
    final foreign = BookSource.fromJson({
      'bookSourceName': '書架檔',
      'bookSourceUrl': base,
      'loginUrl': 'https://login.example',
      'header': '{"Referer":"$base/"}',
    });
    await foreign.putLoginHeader('{"Authorization":"Bearer secret"}');
    await CookieStore().setCookie(base, 'sid=secret');
    addTearDown(() async {
      await foreign.removeLoginHeader();
      await CookieStore().removeCookie(base);
    });

    final images = p.join(dir.path, 'images');
    final pending = await HttpOverrides.runWithHttpOverrides(
      () => IllustrationFetcher.fetch(
        foreign,
        Book(bookUrl: '$base/book/1', origin: base),
        '<img src="$base/a.png"><img src="$other/b.png">',
        images,
        externalContent: true,
      ),
      _RealHttp(),
    );

    expect(pending, 0);
    // 同一個網站：照舊帶登入資料。
    expect(seen['/a.png']!['authorization'], 'Bearer secret');
    expect(seen['/a.png']!['cookie'], contains('sid=secret'));
    // 不同的網站：照樣抓，但不帶書源的 Cookie 與登入標頭。
    expect(seen['/b.png']!['authorization'], isNull);
    expect(seen['/b.png']!['cookie'], isNull);
    // 書源的標頭照舊，網站才不會擋盜連。
    expect(seen['/b.png']!['referer'], '$base/');

    // 正常抓正文的插圖（不是書架檔帶回來的）照舊帶登入資料，別的主機也一樣。
    await HttpOverrides.runWithHttpOverrides(
      () => IllustrationFetcher.fetch(
        foreign,
        Book(bookUrl: '$base/book/1', origin: base),
        '<img src="$other/c.png">',
        images,
      ),
      _RealHttp(),
    );
    expect(seen['/c.png']!['authorization'], 'Bearer secret');
    expect(seen['/c.png']!['cookie'], contains('sid=secret'));
  });

  test('書源的 imageDecode 先解抓到的位元組，src 是圖的網址', () async {
    final images = p.join(dir.path, 'images');
    // 網站把每個位元組加一，imageDecode 減回來。
    final scrambled = _dataUrl([for (final b in _png) (b + 1) & 0xFF]);
    final decoding = BookSource.fromJson({
      'bookSourceName': '解圖',
      'bookSourceUrl': 'https://u.test',
      'ruleContent': {
        'content': 'id.c@html',
        'imageDecode':
            'src.indexOf("data:") == 0 ? '
            'Array.from(result).map(function (b) { return (b + 255) % 256; }) '
            ': null',
      },
    });
    final failed = await IllustrationFetcher.fetch(
      decoding,
      book,
      '<img src="$scrambled">',
      images,
    );
    expect(failed, 0);
    expect(
      await File(BookIllustrationStorage.pathFor(images, scrambled))
          .readAsBytes(),
      _png,
    );
  }, skip: quickJsUnavailableReason());
}
