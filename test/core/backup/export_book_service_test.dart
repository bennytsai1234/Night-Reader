import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/backup/export_book_service.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/local_book/local_book_formats.dart';
import 'package:night_reader/core/local_book/local_book_service.dart';
import 'package:night_reader/core/local_book/txt_parser.dart';
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
    bool externalContent = false,
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
      ..registerSingleton<BookDao>(BookDao(db))
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

  // 本地 EPUB 的分卷有卷首的字：匯出時照 Legado 寫進去，不只寫卷名。
  test('a local volume with its own text exports the text too', () async {
    final file = File('${root.path}/卷.txt');
    const volume = '第一卷\n卷首語。\n';
    const chapter = '第一章\n正文。\n';
    await file.writeAsString('$volume$chapter');
    final book = Book(
      bookUrl: 'local://${file.path}',
      origin: 'local',
      name: '卷',
      isInBookshelf: true,
      charset: 'utf-8',
    );
    final volumeBytes = utf8.encode(volume).length;
    final chapters = [
      BookChapter(
        url: '${book.bookUrl}#0',
        title: '第一卷',
        bookUrl: book.bookUrl,
        index: 0,
        start: 0,
        end: volumeBytes,
        isVolume: true,
      ),
      BookChapter(
        url: '${book.bookUrl}#1',
        title: '第一章',
        bookUrl: book.bookUrl,
        index: 1,
        start: volumeBytes,
        end: await file.length(),
      ),
    ];
    await ChapterDao(db).insertChapters(chapters);
    // 這份目錄記成照現在的分章規則切的，匯出前不重新分章。
    writeChapterRanges(
      await LocalBookService.txtChaptersPath(book),
      TxtParser.tocVersion,
      [
        for (final c in chapters)
          (title: c.title, start: c.start!, end: c.end!, isVolume: c.isVolume),
      ],
    );

    await ExportBookService().exportToTxt(book, present: present);
    // Windows 上開著的原檔刪不掉。
    await LocalBookService().closeOpenFile();

    final exported = await (await AppStoragePaths.shareExportFile('卷.txt'))
        .readAsString();
    expect(exported, contains('卷首語。'));
    expect(exported, contains('正文。'));
  });

  // 本地書的原檔不在這台（例如匯入了別台的書架檔）：匯出要說失敗，不能把
  // 「檔案不存在」當成正文寫進檔案、還說建立好了。
  test('a local book whose original is missing fails to export instead of '
      'writing the error as text', () async {
    final missing = '${root.path}/gone/夜航.txt';
    final book = Book(
      bookUrl: 'local://$missing',
      origin: 'local',
      name: '夜航',
      isInBookshelf: true,
    );
    await ChapterDao(db).insertChapters([
      BookChapter(
        url: '${book.bookUrl}#0',
        title: '一',
        bookUrl: book.bookUrl,
        index: 0,
        start: 0,
        end: 10,
      ),
    ]);

    await expectLater(
      ExportBookService().exportToTxt(book, present: present),
      throwsA(isA<LocalBookContentException>()),
    );
    expect(shared, isEmpty);
  });
}
