import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/source_check/check_source_service.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';
import 'package:night_reader/features/source_manager/widgets/import_preview_sheet.dart';
import 'package:night_reader/features/source_manager/widgets/source_manager_dialogs.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 書源管理裡原本塞在提示框的表單，改成底部面板之後的行為。
void main() {
  late AppDatabase db;
  late BookSourceDao dao;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = BookSourceDao(db);
    GetIt.instance.registerSingleton<BookSourceDao>(dao);
    GetIt.instance.registerLazySingleton<CheckSourceService>(
      CheckSourceService.new,
    );
    await dao.upsertAll([
      BookSource(bookSourceUrl: 'https://novel.test', bookSourceName: '小說甲'),
      BookSource(
        bookSourceUrl: 'https://comic.test',
        bookSourceName: '漫畫甲',
        bookSourceType: 2,
        bookSourceGroup: '常用',
      ),
      BookSource(
        bookSourceUrl: 'https://novel2.test',
        bookSourceName: '小說乙',
        bookSourceGroup: '常用',
      ),
    ]);
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  Future<SourceManagerProvider> loadedProvider(WidgetTester tester) async {
    final provider = (await tester.runAsync(() async {
      final provider = SourceManagerProvider(entrance: Future<void>.value());
      while (provider.isLoading || provider.totalSourceCount == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      return provider;
    }))!;
    addTearDown(provider.dispose);
    return provider;
  }

  Future<void> open(
    WidgetTester tester,
    Future<void> Function(BuildContext context) show,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.kraft, Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => show(context),
              child: const Text('開'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開'));
    await tester.pumpAndSettle();
  }

  testWidgets('按標籤刪除：勾了才能刪，按了再確認一次無法復原', (tester) async {
    final provider = await loadedProvider(tester);
    Set<SourceTag>? picked;
    await open(tester, (context) async {
      picked = await pickSourceTagsToDelete(context, provider);
    });

    // 還沒勾：頁首的「刪除」按不了。
    await tester.tap(find.text('刪除'));
    await tester.pumpAndSettle();
    expect(find.text('無法復原'), findsNothing);

    await tester.tap(find.text('常用：2 個'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除 2 個'));
    await tester.pumpAndSettle();
    expect(find.text('刪除 2 個書源？'), findsOneWidget);
    expect(find.text('無法復原'), findsOneWidget);

    await tester.tap(find.text('刪除').last);
    await tester.pumpAndSettle();
    expect(picked, {(kind: null, group: '常用')});
  });

  testWidgets('校驗設定：詳情關掉時，目錄與正文藏起來', (tester) async {
    final provider = await loadedProvider(tester);
    await open(
      tester,
      (context) => SourceManagerDialogs.showCheckConfigDialog(
        context,
        provider,
        checkAll: true,
      ),
    );
    expect(find.text('校驗全部 3 個書源'), findsOneWidget);
    expect(find.text('目錄'), findsOneWidget);

    await tester.tap(find.text('詳情'));
    await tester.pumpAndSettle();
    expect(find.text('目錄'), findsNothing);
    expect(find.text('正文'), findsNothing);
  });

  testWidgets('校驗詳情：沒在校驗、也沒有出問題的書源時，頁首右邊沒有動作', (tester) async {
    final provider = await loadedProvider(tester);
    await open(tester, (context) async {
      SourceManagerDialogs.showCheckLog(context, provider);
    });
    expect(find.text('校驗詳情'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('目前還沒有校驗日誌'), findsOneWidget);
    expect(find.text('結束校驗'), findsNothing);
    expect(find.text('複製診斷'), findsNothing);
  });

  testWidgets('匯入預覽：關掉的類型不匯入', (tester) async {
    final novel = BookSource(bookSourceUrl: 'https://n.test');
    final comic = BookSource(
      bookSourceUrl: 'https://c.test',
      bookSourceType: 2,
    );
    final updated = BookSource(bookSourceUrl: 'https://novel.test');
    List<BookSource>? chosen;
    await open(tester, (context) async {
      chosen = await showImportPreviewSheet(
        context,
        ImportPreviewResult(
          newSources: [novel, comic],
          updatedSources: [updated],
          unchangedSources: const [],
        ),
      );
    });
    expect(find.text('匯入 3 個'), findsOneWidget);

    await tester.tap(find.text('漫畫源 1 個'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('匯入 2 個'));
    await tester.pumpAndSettle();
    expect(chosen, [novel, updated]);
  });
}
