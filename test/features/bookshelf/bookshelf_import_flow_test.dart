import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/backup/bookshelf_exchange_service.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/network/network_service.dart';
import 'package:night_reader/features/bookshelf/bookshelf_import_flow.dart';

/// 搜尋要等：第一本找完就停住，等讀者按取消。
class _Waiting extends BookshelfExchangeService {
  _Waiting({this.total = 2});

  /// 實際要找的本數（檔裡已在書架上的不算）。
  final int total;
  final started = Completer<void>();

  @override
  Future<BookshelfImportResult> importFile(
    BookshelfFile? file, {
    void Function(int done, int total)? onSearchProgress,
    CancelToken? cancelToken,
  }) async {
    onSearchProgress?.call(total - 1, total);
    started.complete();
    await cancelToken!.whenCancel;
    return const BookshelfImportResult(
      books: 1,
      chapters: 0,
      sources: 0,
      notFound: [],
    );
  }
}

void main() {
  late AppDatabase db;

  setUp(() async {
    await GetIt.instance.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await NetworkService().init(ephemeral: true);
    GetIt.instance
      ..registerSingleton<BookDao>(BookDao(db))
      ..registerSingleton<ChapterDao>(ChapterDao(db))
      ..registerSingleton<BookSourceDao>(BookSourceDao(db))
      ..registerSingleton<NetworkService>(NetworkService());
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  testWidgets('Legado 的書架開進度框寫找到第幾本，取消後找到的留著', (tester) async {
    final service = _Waiting();
    String? message;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => message = await importBookshelfFile(
              context,
              BookshelfFile.parse(
                jsonEncode([
                  {'name': '一', 'author': ''},
                  {'name': '二', 'author': ''},
                ]),
              ),
              service: service,
            ),
            child: const Text('匯入'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('匯入'));
    await tester.runAsync(() => service.started.future);
    await tester.pump();
    expect(find.text('匯入書架'), findsOneWidget);
    expect(find.text('在書源裡找第 2／2 本'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('匯入書架'), findsNothing);
    expect(message, '已停下，已匯入 1 本書');
  });

  testWidgets('進度的分母是實際要找的本數，不算已在書架上的', (tester) async {
    final service = _Waiting(total: 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => importBookshelfFile(
              context,
              BookshelfFile.parse(
                jsonEncode([
                  {'name': '已在書架', 'author': ''},
                  {'name': '一', 'author': ''},
                ]),
              ),
              service: service,
            ),
            child: const Text('匯入'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('匯入'));
    await tester.runAsync(() => service.started.future);
    await tester.pump();
    expect(find.text('在書源裡找第 1／1 本'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('不用在書源裡找時不開進度框，頁面留著', (tester) async {
    String? message;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => message = await importBookshelfFile(
              context,
              BookshelfFile.parse('[]'),
              service: _Nothing(),
            ),
            child: const Text('匯入'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('匯入'));
    await tester.pumpAndSettle();

    expect(find.text('匯入書架'), findsNothing);
    expect(find.text('匯入'), findsOneWidget);
    expect(message, '未找到可匯入的書架資料');
  });
}

/// 什麼都沒匯入，也沒在書源裡找。
class _Nothing extends BookshelfExchangeService {
  @override
  Future<BookshelfImportResult> importFile(
    BookshelfFile? file, {
    void Function(int done, int total)? onSearchProgress,
    CancelToken? cancelToken,
  }) async => const BookshelfImportResult(books: 0, chapters: 0, sources: 0);
}
