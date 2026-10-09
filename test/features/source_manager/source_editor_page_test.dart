import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/source/book_source_rules.dart';
import 'package:night_reader/features/source_manager/source_editor_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

void main() {
  late AppDatabase db;
  late BookSourceDao dao;

  setUp(() async {
    await GetIt.instance.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = BookSourceDao(db);
    GetIt.instance.registerSingleton<BookSourceDao>(dao);
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  BookSource sampleSource({String url = 'https://a.example'}) => BookSource(
    bookSourceUrl: url,
    bookSourceName: '甲書源',
    ruleToc: TocRule(chapterList: '.list li', formatJs: 'formatJs()'),
    ruleContent: ContentRule(content: '#content', webJs: 'webJs()'),
  );

  /// 從一個起始頁推入編輯器，才能檢查返回行為。
  Future<void> pumpEditor(WidgetTester tester, BookSource? source) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SourceEditorPage(source: source),
                ),
              ),
              child: const Text('開啟'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開啟'));
    await tester.pumpAndSettle();
  }

  Finder field(int index) => find.byType(TextField).at(index);

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('儲存'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('saving keeps rules the editor does not show', (tester) async {
    await tester.runAsync(() => dao.upsert(sampleSource()));
    final stored = await tester.runAsync(
      () => dao.getByUrl('https://a.example'),
    );
    await pumpEditor(tester, stored);

    await tester.enterText(field(0), '乙書源');
    await save(tester);

    final saved = await tester.runAsync(
      () => dao.getByUrl('https://a.example'),
    );
    expect(saved!.bookSourceName, '乙書源');
    expect(saved.ruleToc?.chapterList, '.list li');
    expect(saved.ruleToc?.formatJs, 'formatJs()');
    expect(saved.ruleContent?.webJs, 'webJs()');
  });

  testWidgets('changing the url moves the source instead of copying it', (
    tester,
  ) async {
    await tester.runAsync(() => dao.upsert(sampleSource()));
    final stored = await tester.runAsync(
      () => dao.getByUrl('https://a.example'),
    );
    await pumpEditor(tester, stored);

    await tester.enterText(field(1), 'https://a.example.net');
    await save(tester);

    final all = await tester.runAsync(() => dao.getAll());
    expect(all!.map((s) => s.bookSourceUrl), ['https://a.example.net']);
    expect(all.single.ruleContent?.webJs, 'webJs()');
  });

  testWidgets('a url used by another source asks before overwriting', (
    tester,
  ) async {
    await tester.runAsync(() => dao.upsert(sampleSource()));
    await pumpEditor(tester, null);

    await tester.enterText(field(0), '新書源');
    await tester.enterText(field(1), 'https://a.example');
    await save(tester);

    expect(find.text('覆蓋現有書源？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    final kept = await tester.runAsync(() => dao.getByUrl('https://a.example'));
    expect(kept!.bookSourceName, '甲書源');
    expect(find.byType(SourceEditorPage), findsOneWidget);
  });

  testWidgets('leaving with unsaved edits asks first', (tester) async {
    await pumpEditor(tester, sampleSource());

    // 沒有修改時直接離開。
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SourceEditorPage), findsNothing);

    await tester.tap(find.text('開啟'));
    await tester.pumpAndSettle();
    await tester.enterText(field(0), '改過的名稱');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放棄未儲存的修改？'), findsOneWidget);

    await tester.tap(find.text('放棄'));
    await tester.pumpAndSettle();
    expect(find.byType(SourceEditorPage), findsNothing);
  });
}
