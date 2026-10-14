import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:night_reader/features/search/search_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回應都在記憶體裡；`slow.test` 晚一點回，搜尋停在它之前。
class _MemoryAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.host == 'slow.test') {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return ResponseBody.fromBytes(
      utf8.encode('<div class="item"><a href="/b/1">夜讀</a></div>'),
      200,
      headers: {
        Headers.contentTypeHeader: ['text/html; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 第一個書源完成時按下停止。
class _StopAfterFirst implements SearchModelCallback {
  _StopAfterFirst(this.stop);

  final void Function() stop;
  final List<SearchBook> published = [];

  @override
  void onSearchProgress({
    required List<String> waitingSources,
    required int completed,
    required int total,
    required int failed,
  }) {
    if (completed == 1) stop();
  }

  @override
  void onSearchSuccess(List<SearchBook> searchBooks) => published
    ..clear()
    ..addAll(searchBooks);

  @override
  void onSearchStart() {}
  @override
  void onSearchFailure(SearchFailure failure) {}
  @override
  void onSearchFinish({required bool isEmpty}) {}
}

void main() {
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final getIt = GetIt.instance;
    await getIt.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    getIt
      ..registerSingleton<BookSourceDao>(BookSourceDao(db))
      ..registerSingleton<SearchBookDao>(SearchBookDao(db));
    await NetworkService().init(ephemeral: true);
    NetworkService().dio
      ..interceptors.clear()
      ..httpClientAdapter = _MemoryAdapter();
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  final sources = [
    for (final host in ['fast', 'slow'])
      BookSource.fromJson({
        'bookSourceUrl': 'https://$host.test',
        'bookSourceName': host,
        'searchUrl': 'https://$host.test/search',
        'ruleSearch': {
          'bookList': 'class.item',
          'name': 'a@text',
          'bookUrl': 'a@href',
        },
      }),
  ];

  test('stopping keeps the results that already arrived', () async {
    late SearchModel model;
    final callback = _StopAfterFirst(() => model.stopSearch());
    model = SearchModel(callback: callback);
    addTearDown(model.dispose);

    await model.searchSources(
      key: '夜讀',
      sources: sources,
      precisionSearch: false,
    );

    expect(callback.published.map((b) => b.name), ['夜讀']);
    expect(callback.published.single.origins, ['https://fast.test']);
  });

  test('cancelling for a new search drops results not yet shown', () async {
    late SearchModel model;
    final callback = _StopAfterFirst(() => model.cancelSearch());
    model = SearchModel(callback: callback);
    addTearDown(model.dispose);

    await model.searchSources(
      key: '夜讀',
      sources: sources,
      precisionSearch: false,
    );

    expect(callback.published, isEmpty);
  });
}
