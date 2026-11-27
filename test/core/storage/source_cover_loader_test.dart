import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:file/file.dart' as pkgfile;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/network/network_service.dart';
import 'package:night_reader/core/storage/source_cover_loader.dart';

import '../../test_helper.dart';

class _SourceDao extends Fake implements BookSourceDao {
  _SourceDao(this.sources);

  final Map<String, BookSource> sources;

  @override
  Future<BookSource?> getByUrl(String url) async => sources[url];
}

/// 書源網址的請求照 [X-Source] 標頭回不同的位元組，記下收到的請求（不連
/// 網路）。
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<(String?, String)> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    String? header(String name) {
      for (final entry in options.headers.entries) {
        if (entry.key.toLowerCase() == name) return entry.value?.toString();
      }
      return null;
    }

    final source = header('x-source');
    requests.add((source, options.path));
    return ResponseBody.fromBytes(
      source == 'b' ? const [5, 6, 7, 8] : const [1, 2, 3, 4],
      200,
      headers: {
        Headers.contentTypeHeader: ['image/png'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 磁碟快取：照鍵存檔案；一般圖片一律當成不在手機裡（測試只走照書源抓的
/// 那一條）。
class _DiskCache implements BaseCacheManager {
  _DiskCache(this.dir);

  final Directory dir;
  final Map<String, File> stored = {};
  final List<String> generalReads = [];

  FileInfo _info(File file, String key) => FileInfo(
    const LocalFileSystem().file(file.path),
    FileSource.Cache,
    DateTime(2100),
    key,
  );

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async {
    final file = stored[key];
    return file == null ? null : _info(file, key);
  }

  @override
  Future<pkgfile.File> putFile(
    String url,
    Uint8List fileBytes, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) async {
    final file = File('${dir.path}/${stored.length}.$fileExtension')
      ..writeAsBytesSync(fileBytes, flush: true);
    stored[key ?? url] = file;
    return const LocalFileSystem().file(file.path);
  }

  @override
  Future<pkgfile.File> getSingleFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) async {
    generalReads.add(url);
    throw const SocketException('一般圖片快取沒有這張');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 照書源的封面抓：書源有標頭時照標頭抓，其他的照一般圖片抓（[CoverFetcher]）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();
  final skip = quickJsUnavailableReason();

  const originA = 'https://a.example';
  const originB = 'https://b.example';
  const originPlain = 'https://plain.example';
  const baseUrl = 'https://covers.example';
  late final Map<String, BookSource> sources = {
    originA: BookSource(
      bookSourceUrl: originA,
      bookSourceName: '甲',
      header: '{"X-Source":"a"}',
    ),
    originB: BookSource(
      bookSourceUrl: originB,
      bookSourceName: '乙',
      header: '{"X-Source":"b"}',
    ),
    originPlain: BookSource(bookSourceUrl: originPlain, bookSourceName: '丙'),
  };

  late Directory dir;
  late _DiskCache cache;
  late _FakeHttpClientAdapter adapter;

  setUpAll(() async {
    await GetIt.instance.reset();
    setupTestDI();
    GetIt.instance.registerSingleton<BookSourceDao>(_SourceDao(sources));
    await NetworkService().init();
  });

  tearDownAll(() => GetIt.instance.reset());

  setUp(() {
    SourceCoverLoader.clearSourcesForTest();
    dir = Directory.systemTemp.createTempSync('source_cover_');
    CachedNetworkImageProvider.defaultCacheManager = cache = _DiskCache(dir);
    NetworkService().dio.httpClientAdapter = adapter = _FakeHttpClientAdapter();
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  test('兩個書源共用同一個封面網址時各有各的快取鍵', () {
    const url = 'https://covers.example/a.jpg';
    final fromA = SourceCoverLoader.sourceKey(originA, url);
    final fromB = SourceCoverLoader.sourceKey(originB, url);

    expect(fromA, isNot(fromB));
    expect(fromA, contains(originA));
    expect(fromA, contains(url));
    expect(fromB, contains(originB));
  });

  test('兩個書源共用同一個封面網址時各照自己的書源抓、各存一份', () async {
    const url = '$baseUrl/shared.png';

    final fromA = await SourceCoverLoader.load(url, originA);
    final fromB = await SourceCoverLoader.load(url, originB);

    expect(fromA, [1, 2, 3, 4]);
    expect(fromB, [5, 6, 7, 8]);
    expect(adapter.requests, [('a', url), ('b', url)]);

    // 同一個書源再看一次：磁碟快取裡就有了，不再抓。
    expect(await SourceCoverLoader.load(url, originA), fromA);
    expect(adapter.requests, [('a', url), ('b', url)]);
  });

  test('網址帶 {{}} 時照書源抓、先算出來', () async {
    final bytes = await SourceCoverLoader.load(
      '$baseUrl/{{1+1}}.png',
      originPlain,
    );

    expect(bytes, [1, 2, 3, 4]);
    expect(adapter.requests, [(null, '$baseUrl/2.png')]);
    expect(cache.generalReads, isEmpty, reason: '不能照字面當一般圖片抓');
  }, skip: skip);
}
