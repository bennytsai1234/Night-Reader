import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/features/source_manager/source_manager_page.dart';
import 'package:night_reader/features/source_manager/source_group_manage_page.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PageSourceDao extends Fake implements BookSourceDao {
  final Map<String, BookSource> sources = <String, BookSource>{};
  int loadCount = 0;
  Completer<List<BookSource>>? loadCompleter;

  @override
  Future<List<BookSource>> getAllPart() async {
    loadCount += 1;
    if (loadCompleter != null) return loadCompleter!.future;
    return sources.values.toList(growable: false);
  }

  @override
  Future<BookSource?> getByUrl(String url) async => sources[url];

  @override
  Future<void> upsert(BookSource source) async {
    sources[source.bookSourceUrl] = source;
  }
}

void main() {
  late _PageSourceDao dao;

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dao = _PageSourceDao();
    GetIt.instance.registerSingleton<BookSourceDao>(dao);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets('successful new-source save reloads the manager list', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SourceManagerPage()));
    await tester.pumpAndSettle();
    expect(find.text('尚未加入書源'), findsOneWidget);

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建書源'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '書源名稱'), '新增書源');
    await tester.enterText(
      find.widgetWithText(TextFormField, '書源網址'),
      'https://new.example.com',
    );
    await tester.tap(find.byTooltip('儲存書源'));
    await tester.pumpAndSettle();

    expect(find.text('新增書源'), findsOneWidget);
    expect(dao.sources, contains('https://new.example.com'));
  });

  testWidgets('canceling the editor does not reload the manager list', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SourceManagerPage()));
    await tester.pumpAndSettle();
    final loadCountBeforeEditor = dao.loadCount;

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建書源'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(dao.loadCount, loadCountBeforeEditor);
    expect(find.text('尚未加入書源'), findsOneWidget);
  });

  testWidgets('group mutation controls are disabled while loading', (
    tester,
  ) async {
    dao.sources['https://source.example.com'] = BookSource(
      bookSourceUrl: 'https://source.example.com',
      bookSourceName: '書源',
      bookSourceGroup: '測試分組',
    );
    final provider = SourceManagerProvider();
    await provider.loadSources();
    dao.loadCompleter = Completer<List<BookSource>>();
    final loading = provider.loadSources();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<SourceManagerProvider>.value(
          value: provider,
          child: const SourceGroupManagePage(),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.share_outlined),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.edit_outlined),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.delete_outline),
          )
          .onPressed,
      isNull,
    );

    dao.loadCompleter!.complete(dao.sources.values.toList(growable: false));
    await loading;
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });
}
