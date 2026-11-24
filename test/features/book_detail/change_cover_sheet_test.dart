import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/chinese/chinese_utils.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/models/search/search_book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/features/book_detail/change_cover_sheet.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/book/book_cover_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _source = 'https://cover.example';

void main() {
  late AppDatabase db;

  setUpAll(() {
    ChineseUtils.initializeFromDictionaryData([
      for (final path in ChineseUtils.dictionaryAssetPaths)
        File(path).readAsStringSync(),
    ]);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final sourceDao = BookSourceDao(db);
    GetIt.instance
      ..registerSingleton<BookSourceDao>(sourceDao)
      ..registerSingleton<SearchBookDao>(SearchBookDao(db));
    await sourceDao.upsert(
      BookSource(bookSourceUrl: _source, bookSourceName: '封面站'),
    );
    await SearchBookDao(db).upsert(
      SearchBook(
        bookUrl: '$_source/book',
        name: '甲書',
        author: '乙作者',
        coverUrl: '$_source/cover.jpg',
        origin: _source,
        originName: '封面站',
      ),
    );
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  // 整區載入用骨架、不放置中轉圈；封面載入中鋪骨架底色、到了淡入
  // （docs/design/components.md「狀態視圖」「封面」）。
  testWidgets('換封面面板先畫格子，候選封面照共用封面元件載入，都不轉圈', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: const Scaffold(
          body: ChangeCoverSheet(bookName: '甲書', author: '乙作者'),
        ),
      ),
    );

    // 還在讀存過的封面：第一格「恢復預設」已經在。
    expect(find.text('正在載入封面…'), findsOneWidget);
    expect(find.text('恢復預設'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.runAsync(() async {
      while (find.text('正在載入封面…').evaluate().isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });
    await tester.pump();

    expect(find.text('封面站'), findsOneWidget);
    expect(find.byType(BookCoverWidget), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
