import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/models/read_record.dart';
import 'package:night_reader/core/sync/read_stats_sync.dart';
import 'package:night_reader/core/sync/sync_base_storage.dart';
import 'package:night_reader/core/sync/sync_records.dart';
import 'package:night_reader/core/sync/sync_settings.dart';
import 'package:night_reader/features/bookmarks/reading_stats_view.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _OwnPathProvider extends PathProviderPlatform {
  _OwnPathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  late AppDatabase db;
  late Directory appDir;
  late PathProviderPlatform previous;
  late ReadStatsSync sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<SharedPreferences>(prefs);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final dao = ReadRecordDao(db);
    GetIt.instance.registerSingleton<ReadRecordDao>(dao);
    appDir = Directory.systemTemp.createTempSync('nr-stats-page-');
    previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _OwnPathProvider(appDir.path);
    sync = ReadStatsSync(
      settings: SyncSettings(prefs),
      bases: SyncBaseStorage(),
      dao: dao,
      prefs: prefs,
    );
  });

  tearDown(() async {
    PathProviderPlatform.instance = previous;
    await db.close();
    await GetIt.instance.reset();
    appDir.deleteSync(recursive: true);
  });

  /// 讓檔案與資料庫的讀取在真實事件迴圈上完成，再把結果畫出來。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: const Scaffold(body: ReadingStatsView()),
      ),
    );
    await settle(tester);
  }

  SyncRecord otherPhone(int seconds, {String book = '夜雨聽書'}) => SyncRecord(
    time: 1,
    data: {
      'books': {
        book: {'t': seconds, 'l': 5},
      },
      'days': <String, int>{},
    },
  );

  testWidgets('開著的閱讀統計收到別台的時間後，不用重進就加上去', (tester) async {
    await tester.runAsync(
      () =>
          ReadRecordDao(db)
              .upsert(ReadRecord(bookName: '夜雨聽書', readTime: 600, lastRead: 3)),
    );
    await pumpPage(tester);
    expect(find.text('10 分鐘'), findsWidgets);

    await tester.runAsync(() => sync.apply({'phone-b': otherPhone(1200)}));
    await settle(tester);
    expect(find.text('30 分鐘'), findsWidgets);

    // 別台再讀了、又多一本書。
    await tester.runAsync(
      () => sync.apply({
        'phone-b': otherPhone(1800),
        'phone-c': otherPhone(60, book: '山海經'),
      }),
    );
    await settle(tester);
    expect(find.text('40 分鐘'), findsWidgets);
    expect(find.text('山海經'), findsOneWidget);
  });

  testWidgets('聽過有聲書時，書分成閱讀與收聽兩組，合計含收聽（ADR 0055）', (tester) async {
    final dao = ReadRecordDao(db);
    await tester.runAsync(() async {
      await dao.upsert(
        ReadRecord(bookName: '長夜將盡', readTime: 600, lastRead: 3),
      );
      await dao.upsert(
        ReadRecord(bookName: 'audio:長夜將盡', readTime: 1200, lastRead: 4),
      );
    });
    await pumpPage(tester);

    expect(find.text('閱讀'), findsOneWidget);
    expect(find.text('收聽'), findsOneWidget);
    expect(find.text('累積閱讀時間'), findsNothing);
    // 總計 30 分鐘：讀 10 加聽 20。
    expect(find.text('30 分鐘', findRichText: true), findsOneWidget);
  });

  testWidgets('沒聽過有聲書時照舊一組', (tester) async {
    await tester.runAsync(
      () =>
          ReadRecordDao(db)
              .upsert(ReadRecord(bookName: '長夜將盡', readTime: 600, lastRead: 3)),
    );
    await pumpPage(tester);

    expect(find.text('累積閱讀時間'), findsOneWidget);
    expect(find.text('收聽'), findsNothing);
  });

  testWidgets('同步後重讀時不閃一格轉圈', (tester) async {
    await tester.runAsync(
      () =>
          ReadRecordDao(db)
              .upsert(ReadRecord(bookName: '夜雨聽書', readTime: 600, lastRead: 3)),
    );
    await pumpPage(tester);
    await tester.runAsync(() => sync.apply({'phone-b': otherPhone(1200)}));
    // 照 settle 的步驟一格一格看，每一格都不該是轉圈。
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }
    expect(find.text('30 分鐘'), findsWidgets);
  });

  testWidgets('內容沒變就不通知', (tester) async {
    await tester.runAsync(() => sync.apply({'phone-b': otherPhone(60)}));
    final applied = ReadStatsSync.applied.value;

    await tester.runAsync(() => sync.apply({'phone-b': otherPhone(60)}));

    expect(ReadStatsSync.applied.value, applied);
  });

  testWidgets('頁面關掉後收到同步不出錯', (tester) async {
    await pumpPage(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    await tester.runAsync(() => sync.apply({'phone-b': otherPhone(60)}));
    await settle(tester);

    expect(tester.takeException(), isNull);
  });
}
