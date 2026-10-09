import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/book_info_parser.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/crash_handler.dart';
import 'package:night_reader/core/services/update_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../test_helper.dart';

class _DirPathProvider extends PathProviderPlatform {
  _DirPathProvider(this.path);

  final String path;

  @override
  Future<String?> getExternalStoragePath() async => path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  const detailHtml =
      '<h1 class="name">書源上的書名</h1>'
      '<p class="author">書源上的作者</p>';

  BookSource sourceWith({String? canReName}) => BookSource.fromJson({
    'bookSourceName': '測試',
    'bookSourceUrl': 'https://s.example',
    'ruleBookInfo': {
      'name': 'class.name@text',
      'author': 'class.author@text',
      'canReName': ?canReName,
    },
  });

  Book shelfBook({required bool inShelf}) => Book(
    bookUrl: 'https://s.example/book/1',
    origin: 'https://s.example',
    name: '我改過的書名',
    author: '我改過的作者',
  )..isInBookshelf = inShelf;

  Future<Book> parse(BookSource source, Book book) => BookInfoParser.parse(
    source: source,
    book: book,
    body: detailHtml,
    baseUrl: book.bookUrl,
  );

  test('a shelf book keeps the name and author the user set', () async {
    final parsed = await parse(sourceWith(), shelfBook(inShelf: true));
    expect(parsed.name, '我改過的書名');
    expect(parsed.author, '我改過的作者');
  });

  test('canReName or a search result still takes the detail page', () async {
    final renamed = await parse(
      sourceWith(canReName: '1'),
      shelfBook(inShelf: true),
    );
    expect(renamed.name, '書源上的書名');

    final fromSearch = await parse(sourceWith(), shelfBook(inShelf: false));
    expect(fromSearch.name, '書源上的書名');
    expect(fromSearch.author, '書源上的作者');
  });

  test('a failed update check is an error, not "up to date"', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
            ),
          ),
        ),
      );
    final service = AppUpdateService(
      dio: dio,
      currentVersionLoader: () async => '0.3.2',
    );
    await expectLater(service.checkLatest(), throwsA(isA<DioException>()));
  });

  test('no crash logs reads as empty, not as a placeholder line', () async {
    final dir = await Directory.systemTemp.createTemp('crash_logs');
    addTearDown(() => dir.delete(recursive: true));
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _DirPathProvider(dir.path);
    addTearDown(() => PathProviderPlatform.instance = previous);

    expect(await CrashHandler.readLogs(), isEmpty);
  });
}
