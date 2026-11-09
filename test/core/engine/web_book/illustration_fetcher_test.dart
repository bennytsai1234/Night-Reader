import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/content_parser.dart';
import 'package:night_reader/core/engine/web_book/illustration_fetcher.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_cover_storage_service.dart';
import 'package:night_reader/core/services/book_illustration_storage.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
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

  test('抓到的圖存進插圖資料夾，不是圖的不存、算抓不到', () async {
    final images = p.join(dir.path, 'images');
    final good = _dataUrl(_png);
    final bad = _dataUrl(utf8.encode('<html>404</html>'));
    final failed = await IllustrationFetcher.fetch(
      source,
      book,
      '甲\n<img src="$good">\n乙<img src="$bad">\n<img src="$good">',
      images,
    );
    expect(failed, 1);
    expect(
      await File(BookIllustrationStorage.pathFor(images, good)).readAsBytes(),
      _png,
    );
    expect(
      File(BookIllustrationStorage.pathFor(images, bad)).existsSync(),
      isFalse,
    );
    expect(Directory(images).listSync(), hasLength(1));
  });

  test('清除封面快取只刪抓來的封面，插圖、轉好的文字與書檔自帶的封面不動', () async {
    final folder = await AppStoragePaths.bookAssetDir(
      BookCoverStorageService.bookStorageKey(book),
      ensureExists: true,
    );
    File p0(String name) => File(p.join(folder.path, name));
    await p0('cover-abc.jpg').writeAsBytes([1, 2]);
    await p0('custom-cover-def.png').writeAsBytes([3]);
    await p0('cover-embedded.png').writeAsBytes([4]);
    await p0('epub-text.txt').writeAsString('字');
    final illustration = File(
      BookIllustrationStorage.pathFor(
        await BookIllustrationStorage.dirFor(book),
        'x',
      ),
    );
    await illustration.create(recursive: true);

    book
      ..coverLocalPath = p0('cover-abc.jpg').path
      ..customCoverLocalPath = p0('custom-cover-def.png').path;
    expect(await BookCoverStorageService().getCachedCoverSize(book), 3);
    await BookCoverStorageService().deleteCachedCovers(book);

    expect(p0('cover-abc.jpg').existsSync(), isFalse);
    expect(p0('custom-cover-def.png').existsSync(), isFalse);
    expect(p0('cover-embedded.png').existsSync(), isTrue);
    expect(p0('epub-text.txt').existsSync(), isTrue);
    expect(illustration.existsSync(), isTrue);
    expect(book.coverLocalPath, isNull);
    expect(book.customCoverLocalPath, isNull);
  });
}
