import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_find/ai_find_library.dart';
import 'package:night_reader/core/ai_find/ai_find_prompt.dart';
import 'package:night_reader/core/ai_find/ai_find_session.dart';
import 'package:night_reader/core/ai_repair/ai_chat_client.dart';
import 'package:night_reader/core/ai_repair/ai_repair_log.dart';
import 'package:night_reader/core/ai_repair/ai_repair_settings.dart';
import 'package:night_reader/core/models/ai_find_record.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/core/services/background_work/background_work.dart';
import 'package:night_reader/features/search/ai_find/ai_find_page.dart';
import 'package:night_reader/features/search/ai_find/ai_find_run.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

SearchBook _book(String name) => SearchBook(
  bookUrl: 'https://a.test/$name',
  name: name,
  author: '作者',
  origin: 'https://a.test',
  originName: 'A 站',
  wordCount: '120萬字',
  kind: '玄幻',
);

class _Library implements AiFindLibrary {
  @override
  final Set<String> secrets = {};

  @override
  Future<AiFindSearchResult> search(
    String keyword,
    BookSourceKind kind,
    CancelToken cancelToken,
  ) async => (books: [_book('獵魔人')], sources: 2, failed: 0);

  @override
  Future<Book> detail(SearchBook book, CancelToken cancelToken) async =>
      Book(name: book.name, author: '作者', intro: '穿越後獵魔');

  @override
  Future<AiFindChapter> chapter(
    SearchBook book,
    int number,
    CancelToken cancelToken,
  ) async => (title: '第一章', text: '正文', total: 1);

  @override
  Future<List<AiFindExploreSource>> exploreSources() async => const [];

  @override
  Future<List<String>> exploreCategories(
    AiFindExploreSource source,
    CancelToken cancelToken,
  ) async => const [];

  @override
  Future<List<SearchBook>> exploreBooks(
    AiFindExploreSource source,
    int category,
    int page,
    CancelToken cancelToken,
  ) async => const [];

  @override
  Future<List<AiFindShelfEntry>> shelf() async => const [];
}

AiReply _call(String name, Map<String, Object?> args) => (
  content: '',
  toolCalls: [(id: 'c', name: name, arguments: jsonEncode(args))],
  reasoning: '',
  usage: (prompt: 30000, cached: 0, completion: 2000, reasoning: 0),
  firstData: Duration.zero,
);

class _Platform implements BackgroundWorkPlatform {
  @override
  Future<bool> show(BackgroundWorkStatus status) async => true;
  @override
  Future<void> hide() async {}
  @override
  set onAction(void Function(String action)? handler) {}
}

/// 等 [done]：找書在假時間裡開始，計時器要 pump 才走、寫紀錄檔要真的時間，
/// 輪流給（進行中那一輪的圖示一直轉，pumpAndSettle 等不到停）。
Future<void> settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue);
}

void main() {
  late Directory logs;

  setUp(() {
    logs = Directory.systemTemp.createTempSync('ai-find-page');
  });
  tearDown(() async {
    logs.deleteSync(recursive: true);
  });

  Future<SharedPreferences> prefs({bool service = true}) async {
    SharedPreferences.setMockInitialValues({
      if (service)
        AiRepairSettings.serviceKey:
            '{"baseUrl":"https://ai.example/v1","apiKey":"k","model":"m"}',
    });
    return SharedPreferences.getInstance();
  }

  Future<void> show(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: page,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('typing a wish and starting runs the find with the chosen '
      'depth, then shows the picks, the explanation and a saved report', (
    tester,
  ) async {
    final settings = await prefs();
    ({String description, AiFindDepth depth})? started;
    late AiFindSession session;
    late AiFindRun run;
    final saved = <AiFindRecord>[];
    await show(
      tester,
      AiFindPage(
        prefs: settings,
        startRun:
            ({
              required description,
              required depth,
              required service,
              required scope,
            }) {
              started = (description: description, depth: depth);
              final replies = [
                _call('search', {'keyword': '穿越'}),
                _call('detail', {'book': 'b1'}),
                _call('read', {'book': 'b1'}),
                _call('submit', {
                  'books': [
                    {'book': 'b1', 'reason': '穿越後獵魔，節奏快'},
                  ],
                  'summary': '搜了穿越，讀過第一章',
                }),
              ];
              session = AiFindSession(
                description: description,
                depth: depth,
                library: _Library(),
                ask: (_, _) async => replies.removeAt(0),
                serviceLabel: 'ai.example · m',
                log: AiRepairLog.find(
                  description: description,
                  directory: () async => logs,
                ),
              );
              return run = AiFindRun(
                session,
                save: (record) async => saved.add(record),
                work: BackgroundWork(platform: _Platform()),
              );
            },
      ),
    );
    expect(find.text('送到 ai.example · m'), findsOneWidget);
    await tester.tap(find.text('開始找書'));
    await tester.pumpAndSettle();
    expect(started, isNull, reason: '沒打字時按不了');

    await tester.enterText(find.byType(TextField), '爽文、穿越');
    await tester.tap(find.text('深入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('開始找書'));
    await tester.pump();
    await tester.pump();
    await settle(tester, () => run.isFinished);
    await tester.pump();

    expect(started, (description: '爽文、穿越', depth: AiFindDepth.deep));
    expect(settings.getString(aiFindDepthKey), 'deep', reason: '下次停在深入');
    expect(find.text('推薦 · 1'), findsOneWidget);
    expect(find.text('獵魔人'), findsOneWidget);
    expect(find.text('穿越後獵魔，節奏快'), findsOneWidget);
    expect(find.text('搜了穿越，讀過第一章'), findsOneWidget);
    expect(find.text('深度：深入 · 4 輪 · 12.8 萬 token'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);

    final record = saved.single;
    expect(record.id, session.id);
    expect(record.picks.single.book.name, '獵魔人');
    await tester.pumpWidget(const SizedBox.shrink());
    var written = false;
    unawaited(session.log.file().then((_) => written = true));
    await settle(tester, () => written);
  });

  testWidgets('starting without an AI service asks to set one up', (
    tester,
  ) async {
    var started = false;
    await show(
      tester,
      AiFindPage(
        prefs: await prefs(service: false),
        startRun:
            ({
              required description,
              required depth,
              required service,
              required scope,
            }) {
              started = true;
              throw StateError('不該開始');
            },
      ),
    );
    await tester.enterText(find.byType(TextField), '修仙');
    await tester.pumpAndSettle();
    await tester.tap(find.text('開始找書'));
    await tester.pumpAndSettle();
    expect(find.text('還沒設定 AI 服務。'), findsOneWidget);
    expect(find.text('設定 AI 服務'), findsOneWidget);
    expect(started, isFalse);
  });

  testWidgets('a past find shows its report without the done button; one that '
      'did not finish says why', (tester) async {
    final shown = AiFindRecord(
      id: 'x',
      description: '修仙，完結',
      depth: 'normal',
      createdAt: 0,
      outcome: AiFindOutcome.found,
      summary: '搜了修仙',
      picks: [(book: _book('凡人修仙傳'), reason: '完結的修仙')],
      rounds: 9,
      tokens: 213000,
    );
    await show(tester, AiFindPage(prefs: await prefs(), record: shown));
    expect(find.text('深度：一般 · 9 輪 · 21.3 萬 token'), findsOneWidget);
    expect(find.text('凡人修仙傳'), findsOneWidget);
    expect(find.text('完成'), findsNothing);

    await show(
      tester,
      AiFindPage(
        prefs: await prefs(),
        record: AiFindRecord(
          id: 'y',
          description: '無限流',
          depth: 'quick',
          createdAt: 0,
          outcome: AiFindOutcome.unfinished,
          failure: '沒有結果：用完 36 輪還沒交出',
        ),
      ),
    );
    expect(find.text('沒有找完'), findsOneWidget);
    expect(find.text('沒有結果：用完 36 輪還沒交出'), findsOneWidget);
  });

  test('the date of a past find drops the year only for this year', () {
    final now = DateTime(2026, 11, 15);
    expect(
      aiFindDateLabel(DateTime(2026, 11, 13).millisecondsSinceEpoch, now),
      '11/13',
    );
    expect(
      aiFindDateLabel(DateTime(2025, 11, 13).millisecondsSinceEpoch, now),
      '2025/11/13',
    );
  });
}
