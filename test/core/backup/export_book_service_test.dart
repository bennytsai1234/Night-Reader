import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/backup/export_book_service.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:night_reader/core/storage/book_illustration_storage.dart';

/// 正文抓得到，裡面的圖連不上（每張都還沒抓到、也還不能確定抓不到）。
class _ImagesDown extends BookSourceService {
  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async => '前文\n<img src="https://i.example/1.png">\n後文';

  @override
  Future<int> fetchIllustrations(
    BookSource source,
    Book book,
    String content, {
    required String dir,
    bool retryMissing = true,
    CancelToken? cancelToken,
  }) async => 1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory root;
  const origin = 'https://export.example';
  const url = '$origin/book/1';
  final shared = <Object?>[];

  setUp(() async {
    await GetIt.instance.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    GetIt.instance
      ..registerSingleton<ChapterDao>(ChapterDao(db))
      ..registerSingleton<BookSourceDao>(BookSourceDao(db))
      ..registerSingleton<ReaderChapterContentDao>(ReaderChapterContentDao(db));
    root = await Directory.systemTemp.createTemp('export_book');
    AppStoragePaths.useRoots((
      documents: root.path,
      support: root.path,
      temporary: root.path,
    ));
    shared.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/share'),
          (call) async {
            shared.add(call.arguments);
            return 'dev.fluttercommunity.plus/share/unavailable';
          },
        );
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
    await root.delete(recursive: true);
  });

  Future<({String title, String text})> present(
    BookChapter chapter,
    String raw,
  ) async => (title: chapter.title, text: raw);

  // 補抓並匯出時，那一章的插圖暫時連不上：留記號給書架自動下載之後補。
  test('pictures that could not be fetched while exporting are left for the '
      'shelf download', () async {
    final book = Book(
      bookUrl: url,
      origin: origin,
      name: '有圖',
      isInBookshelf: true,
    );
    await BookSourceDao(db).upsert(
      BookSource.fromJson({'bookSourceName': '圖', 'bookSourceUrl': origin}),
    );
    await ChapterDao(db).insertChapters([
      BookChapter(url: '$url/0', title: '一', bookUrl: url, index: 0),
    ]);

    await ExportBookService(sourceService: _ImagesDown())
        .exportToTxt(book, present: present, fetchMissingRemote: true);

    expect(shared, hasLength(1));
    expect(await BookIllustrationStorage.isUnfetched(book), isTrue);
  });
}
