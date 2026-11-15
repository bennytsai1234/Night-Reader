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
import 'package:night_reader/core/services/background_work/paused_work_file.dart';
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
  ) async =>
      (books: [_book('獵魔人')], tiers: [1], sources: 2, failed: 0, pending: 0);

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
  Future<AiFindWorkNames?> workNames(
    String name,
    CancelToken cancelToken,
  ) async => name == '鏈鋸人'
      ? (
          title: '鏈鋸人',
          names: {'台灣': '鏈鋸人', '中國大陸': '电锯人'},
          aliases: ['電鋸人', 'Chainsaw Man'],
          intro: '《鏈鋸人》是由日本漫畫家藤本樹所創作的黑暗奇幻少年漫畫。',
          others: ['鏈鋸人角色列表'],
        )
      : null;

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

/// 存在記憶體裡的暫停存檔（元件測試的假時間裡不碰真的檔案）。
class _MemoryFile extends PausedWorkFile {
  _MemoryFile([this.text]) : super('ai_find');
  String? text;
  bool closed = false;

  @override
  bool get isClosed => closed;

  @override
  Future<String?> read() async => text;

  @override
  void save(String text) {
    if (!closed) this.text = text;
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    closed = true;
    text = null;
  }
}

/// 收到取消才回來的假 AI 回覆（暫停、結束時正在等 AI）。
Future<AiReply> _untilCancelled(CancelToken token) async {
  await token.whenCancel;
  throw DioException.requestCancelled(
    requestOptions: RequestOptions(),
    reason: '已取消',
  );
}

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

  testWidgets('while it runs, each round shows up with what it is doing', (
    tester,
  ) async {
    final hold = Completer<AiReply>();
    var asked = 0;
    late AiFindRun run;
    await show(
      tester,
      AiFindPage(
        prefs: await prefs(),
        startRun:
            ({
              required description,
              required depth,
              required service,
              required scope,
            }) => run = AiFindRun(
              AiFindSession(
                description: description,
                depth: depth,
                library: _Library(),
                ask: (_, _) async => ++asked == 1
                    ? _call('search', {'keyword': '穿越'})
                    : hold.future,
                log: AiRepairLog.find(
                  description: description,
                  directory: () async => logs,
                ),
              ),
              save: (_) async {},
              work: BackgroundWork(platform: _Platform()),
            ),
      ),
    );
    await tester.enterText(find.byType(TextField), '穿越');
    await tester.pumpAndSettle();
    await tester.tap(find.text('開始找書'));
    await settle(tester, () => asked >= 2);
    await tester.pump();

    expect(find.text('第 1 輪'), findsOneWidget);
    expect(find.text('搜尋「穿越」小說，找到 1 本'), findsOneWidget);
    expect(find.text('第 2 輪'), findsOneWidget);
    expect(find.text('3.2 萬 token'), findsOneWidget);

    run.session.stop();
    hold.complete(_call('submit', {'books': [], 'summary': ''}));
    await settle(tester, () => run.isFinished);
    await tester.pumpWidget(const SizedBox.shrink());
    var written = false;
    unawaited(run.session.log.file().then((_) => written = true));
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

  testWidgets('a recommended book opens its detail, back returns to the '
      'results, and the next one opens the same way', (tester) async {
    final opened = <String>[];
    await show(
      tester,
      AiFindPage(
        prefs: await prefs(),
        record: AiFindRecord(
          id: 'x',
          description: '我喜歡海賊王',
          depth: 'normal',
          createdAt: 0,
          outcome: AiFindOutcome.found,
          picks: [
            (book: _book('海贼王之剑豪之心'), reason: '穿越者的劍豪路'),
            (book: _book('海贼王之大文豪'), reason: '穿越成報社老闆的兒子'),
          ],
        ),
        bookPage: (book) {
          final name = (book.book as SearchBook).name;
          opened.add(name);
          return Scaffold(body: Center(child: Text('詳情：$name')));
        },
      ),
    );

    await tester.tap(find.text('海贼王之剑豪之心'));
    await tester.pumpAndSettle();
    expect(find.text('詳情：海贼王之剑豪之心'), findsOneWidget);

    Navigator.of(tester.element(find.text('詳情：海贼王之剑豪之心'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('推薦 · 2'), findsOneWidget, reason: '回到結果頁');

    await tester.tap(find.text('海贼王之大文豪'));
    await tester.pumpAndSettle();
    expect(find.text('詳情：海贼王之大文豪'), findsOneWidget);
    expect(opened, ['海贼王之剑豪之心', '海贼王之大文豪']);
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

  testWidgets('pause stops at the start of the last saved round: the page '
      'says so with continue and end, and continue picks up from there', (
    tester,
  ) async {
    final file = _MemoryFile();
    final work = BackgroundWork(platform: _Platform());
    final saved = <AiFindRecord>[];
    final resumedFrom = <int>[];
    var asked = 0;
    late AiFindRun run;
    await show(
      tester,
      AiFindPage(
        prefs: await prefs(),
        startRun:
            ({
              required description,
              required depth,
              required service,
              required scope,
            }) => run = AiFindRun(
              AiFindSession(
                description: description,
                depth: depth,
                library: _Library(),
                ask: (_, token) async => ++asked == 1
                    ? _call('search', {'keyword': '穿越'})
                    : _untilCancelled(token),
                log: AiRepairLog.find(
                  description: description,
                  directory: () async => logs,
                ),
              ),
              save: (record) async => saved.add(record),
              progress: file,
              work: work,
              reopen: (progress, log) async {
                final next = AiFindSession.restore(
                  progress,
                  library: _Library(),
                  ask: (_, _) async =>
                      _call('submit', {'books': [], 'summary': '沒找到想要的'}),
                  log: log,
                );
                resumedFrom.add(next.nextRound);
                return next;
              },
            ),
      ),
    );
    await tester.enterText(find.byType(TextField), '穿越');
    await tester.pumpAndSettle();
    await tester.tap(find.text('開始找書'));
    await settle(tester, () => asked >= 2);
    await tester.pump();
    expect(find.text('暫停'), findsOneWidget);
    expect(find.text('結束'), findsOneWidget);

    await tester.tap(find.text('暫停'));
    await settle(tester, () => run.isPaused);
    await tester.pump();

    expect(work.isBusy, isFalse, reason: '暫停空出背景工作的位置、收掉通知');
    expect(find.text('已暫停'), findsOneWidget);
    expect(find.text('按「繼續」從第 2 輪接著問'), findsOneWidget);
    expect(find.text('第 2 輪'), findsNothing, reason: '做到一半的那一輪不留');
    expect(find.text('繼續'), findsOneWidget);
    expect(find.text('結束'), findsOneWidget);
    expect(saved, isEmpty, reason: '暫停不是結束');
    expect(file.text, isNotNull);

    await tester.tap(find.text('繼續'));
    await settle(tester, () => run.isFinished);
    await tester.pump();

    expect(resumedFrom, [2]);
    expect(find.text('沒找到想要的'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(saved.single.rounds, 2);
    expect(saved.single.outcome, AiFindOutcome.found);
    expect(file.closed, isTrue, reason: '結束的不會再活回來');
    await tester.pumpWidget(const SizedBox.shrink());
    var written = false;
    unawaited(run.session.log.file().then((_) => written = true));
    await settle(tester, () => written);
  });

  group('a find left paused when the app was closed', () {
    Future<String> progressAfterOneRound() async {
      final saves = <String>[];
      final session = AiFindSession(
        description: '穿越',
        depth: AiFindDepth.quick,
        library: _Library(),
        ask: (messages, _) async => messages.any((m) => m.role == 'assistant')
            ? _call('submit', {'books': [], 'summary': ''})
            : _call('search', {'keyword': '穿越'}),
        log: AiRepairLog.find(description: '穿越', directory: () async => logs),
      )..onCheckpoint = saves.add;
      await session.start();
      await session.log.file();
      session.dispose();
      return saves[1];
    }

    test('comes back paused; ending it saves it as an ended find and drops '
        'the save', () async {
      final file = _MemoryFile(await progressAfterOneRound());
      final saved = <AiFindRecord>[];
      await restorePausedAiFind(
        file: file,
        save: (record) async => saved.add(record),
        work: BackgroundWork(platform: null),
      );
      final run = aiFindRuns.current! as AiFindRun;
      expect(run.isPaused, isTrue);
      expect(run.isDone, isFalse, reason: '✦ 推回暫停的這一次');
      expect(run.session.rounds, hasLength(1));
      expect(run.session.nextRound, 2);
      expect(run.canResume, isTrue);

      await run.end();
      expect(run.isFinished, isTrue);
      expect(saved.single.outcome, AiFindOutcome.stopped);
      expect(saved.single.rounds, 1);
      expect(file.closed, isTrue);
      run
        ..attach()
        ..detach();
      await pumpEventQueue();
      expect(aiFindRuns.current, isNull);
    });

    test('a save from another version becomes an unfinished find', () async {
      final file = _MemoryFile(
        jsonEncode({
          'version': 0,
          'id': 'old',
          'description': '舊的',
          'depth': 'normal',
          'startedAt': 1,
        }),
      );
      final saved = <AiFindRecord>[];
      await restorePausedAiFind(
        file: file,
        save: (record) async => saved.add(record),
      );
      expect(aiFindRuns.current, isNull);
      expect(saved.single.outcome, AiFindOutcome.unfinished);
      expect(saved.single.description, '舊的');
      expect(file.closed, isTrue);
    });
  });
}
