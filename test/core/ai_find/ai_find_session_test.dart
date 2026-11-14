import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_find/ai_find_library.dart';
import 'package:night_reader/core/ai_find/ai_find_prompt.dart';
import 'package:night_reader/core/ai_find/ai_find_session.dart';
import 'package:night_reader/core/ai_repair/ai_chat_client.dart';
import 'package:night_reader/core/ai_repair/ai_repair_log.dart';
import 'package:night_reader/core/ai_repair/ai_repair_secrets.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart'
    show AiRepairStepState;
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';

SearchBook _book(String name, {String author = '作者', int type = 0}) =>
    SearchBook(
      bookUrl: 'https://a.test/$name',
      name: name,
      author: author,
      origin: 'https://a.test',
      originName: 'A 站',
      type: type,
      intro: '$name 的簡介',
    );

/// 記憶體裡的書庫：搜尋照 [results] 回；[searchGate] 給了時搜尋等它完成或
/// 被取消（測停止）。
class _Library implements AiFindLibrary {
  _Library(this.results);

  final Map<String, List<SearchBook>> results;
  final List<String> calls = [];
  @override
  final Set<String> secrets = {};
  Completer<void>? searchGate;
  bool searchCancelled = false;

  @override
  Future<AiFindSearchResult> search(
    String keyword,
    BookSourceKind kind,
    CancelToken cancelToken,
  ) async {
    calls.add('search $keyword ${kind.name}');
    final gate = searchGate;
    if (gate != null) {
      await Future.any([gate.future, cancelToken.whenCancel]);
      if (cancelToken.isCancelled) {
        searchCancelled = true;
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(),
          reason: '已停止',
        );
      }
    }
    return (
      books: results[keyword] ?? const <SearchBook>[],
      sources: 3,
      failed: 1,
    );
  }

  @override
  Future<Book> detail(SearchBook book, CancelToken cancelToken) async {
    calls.add('detail ${book.name}');
    return Book(
      name: book.name,
      author: book.author ?? '',
      intro: '${book.name}：穿越後獵魔升級',
      kind: '玄幻,完結',
    );
  }

  @override
  Future<AiFindChapter> chapter(
    SearchBook book,
    int number,
    CancelToken cancelToken,
  ) async {
    calls.add('chapter ${book.name} $number');
    if (number > 2) throw const AiFindUnreadable('沒有這一章，共 2 章');
    return (title: '第$number章', text: '字' * 4500, total: 2);
  }

  @override
  Future<List<AiFindExploreSource>> exploreSources() async => [
    (url: 'https://a.test', name: 'A 站', kind: BookSourceKind.novel),
  ];

  @override
  Future<List<String>> exploreCategories(
    AiFindExploreSource source,
    CancelToken cancelToken,
  ) async => ['月票榜', '完結'];

  @override
  Future<List<SearchBook>> exploreBooks(
    AiFindExploreSource source,
    int category,
    int page,
    CancelToken cancelToken,
  ) async => [_book('獵魔人'), _book('排行新書')];

  @override
  Future<List<AiFindShelfEntry>> shelf() async => [
    (
      name: '詭秘之主',
      author: '烏賊',
      kind: BookSourceKind.novel,
      onShelf: true,
      local: false,
      readSeconds: 7200,
      chapter: '第100章',
      chapterIndex: 100,
      chapterTotal: 1400,
    ),
  ];
}

/// 一次呼叫好幾個工具的回覆：`(名稱, 參數)`。
AiReply _calls(List<(String, Map<String, Object?>)> calls) => (
  content: '',
  toolCalls: [
    for (final (i, (name, args)) in calls.indexed)
      (id: 'call_$i', name: name, arguments: jsonEncode(args)),
  ],
  reasoning: '',
  usage: (prompt: 1000, cached: 0, completion: 100, reasoning: 0),
  firstData: Duration.zero,
);

/// 照順序回 [script] 的假 AI，記下每一輪收到的對話。
class _Ai {
  _Ai(this.script);
  final List<AiReply> script;
  final List<List<AiMessage>> seen = [];
  var _next = 0;

  Future<AiReply> call(List<AiMessage> messages, CancelToken token) async {
    seen.add([...messages]);
    if (_next >= script.length) {
      return _calls([
        ('submit', {'books': [], 'summary': '劇本用完'}),
      ]);
    }
    return script[_next++];
  }

  /// 第 [round] 輪（從 1 數）送出時，最後幾句工具結果的內容。
  List<String> toolResults(int round) {
    final messages = seen[round - 1];
    final results = <String>[];
    for (final message in messages.reversed) {
      if (message.role != 'tool') break;
      results.insert(0, message.content);
    }
    return results;
  }
}

void main() {
  late Directory logs;
  final sessions = <AiFindSession>[];
  setUp(() => logs = Directory.systemTemp.createTempSync('ai-find-log'));
  tearDown(() async {
    // 紀錄一面做一面寫：等寫完再刪資料夾。
    for (final find in sessions) {
      await find.log.file();
    }
    sessions.clear();
    logs.deleteSync(recursive: true);
  });

  AiFindSession session(
    _Library library,
    _Ai ai, {
    AiFindDepth depth = AiFindDepth.normal,
  }) {
    final find = AiFindSession(
      description: '爽文、穿越，想要更刺激的',
      depth: depth,
      library: library,
      ask: ai.call,
      log: AiRepairLog.find(description: '爽文、穿越', directory: () async => logs),
    );
    sessions.add(find);
    return find;
  }

  test('search, detail, a rejected submit, reading, then an accepted '
      'submit: the picks are the books the tools found', () async {
    final library = _Library({
      '穿越': [_book('獵魔人'), _book('斬妖'), _book('漫畫獵魔', type: 2)],
    });
    final ai = _Ai([
      _calls([
        ('search', {'keyword': '穿越'}),
        ('shelf', {}),
      ]),
      _calls([
        ('detail', {'book': 'b1'}),
        ('detail', {'book': '2'}),
      ]),
      _calls([
        (
          'submit',
          {
            'books': [
              {'book': 'b1', 'reason': '獵魔'},
              {'book': 'b2', 'reason': '斬妖'},
              {'book': 'b9', 'reason': '編的'},
            ],
            'summary': '先交',
          },
        ),
      ]),
      _calls([
        ('read', {'book': 'b1', 'chapter': 1}),
        ('read', {'book': 'b2', 'chapter': 3}),
      ]),
      _calls([
        ('read', {'book': 'b1', 'chapter': 1, 'from': 3000}),
      ]),
      _calls([
        (
          'submit',
          {
            'books': [
              {'book': 'b1', 'reason': '穿越後獵魔，節奏快'},
              {'book': 'b2', 'reason': '升級爽文'},
            ],
            'summary': '搜了穿越，讀過兩本',
          },
        ),
      ]),
    ]);
    final find = session(library, ai, depth: AiFindDepth.deep);
    await find.start();

    expect(find.outcome, AiFindOutcome.found);
    expect(find.picks.map((p) => p.book.name), ['獵魔人', '斬妖']);
    expect(find.picks.first.reason, '穿越後獵魔，節奏快');
    expect(find.summary, '搜了穿越，讀過兩本');
    expect(find.tokens, 6 * 1100, reason: '每輪送出加回覆');
    expect(find.rounds, hasLength(6));

    final search = ai.toolResults(2).first;
    expect(search, contains('共 3 本'));
    expect(search, contains('b1｜獵魔人｜作者'));
    expect(search, contains('1 個書源'));
    expect(
      ai.toolResults(2).last,
      contains('詭秘之主｜烏賊｜小說｜讀了 2.0 小時｜讀到第 100／1400 章'),
    );

    final rejected = ai.toolResults(4).single;
    expect(rejected, contains('交出被退回'));
    expect(rejected, contains('b1《獵魔人》：還沒讀過正文'), reason: '一次列出每本不合的');
    expect(rejected, contains('b2《斬妖》：還沒讀過正文'));
    expect(rejected, contains('b9：沒有這個編號'));

    final reads = ai.toolResults(5);
    expect(reads.first, contains('這章共 4500 字，這是 0 到 3000，下一段從 3000 讀'));
    expect(reads.last, contains('第 3 章讀不到：沒有這一章'));
    expect(ai.toolResults(6).single, contains('這是 3000 到 4500，這章讀完了'));
    expect(library.calls, isNot(contains('chapter 漫畫獵魔 1')));
  });

  test(
    'the same book found again keeps its number and what was checked',
    () async {
      final library = _Library({
        '穿越': [_book('獵魔人')],
      });
      final ai = _Ai([
        _calls([
          ('search', {'keyword': '穿越'}),
        ]),
        _calls([
          ('detail', {'book': 'b1'}),
        ]),
        _calls([('explore', {})]),
        _calls([
          ('explore', {'source': 's1'}),
        ]),
        _calls([
          ('explore', {'source': 's1', 'category': 0}),
        ]),
        _calls([
          (
            'submit',
            {
              'books': [
                {'book': 'b1', 'reason': '排行也有'},
              ],
              'summary': '搜尋與排行都有',
            },
          ),
        ]),
      ]);
      final find = session(library, ai);
      await find.start();

      expect(ai.toolResults(4).single, contains('s1｜A 站｜小說'));
      expect(ai.toolResults(5).single, contains('0｜月票榜'));
      final ranking = ai.toolResults(6).single;
      expect(ranking, contains('b1｜獵魔人'), reason: '排行裡的同一本還是 b1');
      expect(ranking, contains('b2｜排行新書'));
      expect(find.outcome, AiFindOutcome.found);
      expect(find.picks.single.book.name, '獵魔人');
    },
  );

  test('a quick search takes books without details; zero books can be '
      'handed in with a reason', () async {
    final quick = _Ai([
      _calls([
        ('search', {'keyword': '穿越'}),
      ]),
      _calls([
        (
          'submit',
          {
            'books': [
              {'book': 'b1', 'reason': '書名就是'},
            ],
            'summary': '快速',
          },
        ),
      ]),
    ]);
    final found = session(
      _Library({
        '穿越': [_book('獵魔人')],
      }),
      quick,
      depth: AiFindDepth.quick,
    );
    await found.start();
    expect(found.picks, hasLength(1));

    final none = _Ai([
      _calls([
        ('search', {'keyword': '文言文太空歌劇'}),
      ]),
      _calls([
        ('submit', {'books': [], 'summary': '你的書源裡沒有'}),
      ]),
    ]);
    final empty = session(_Library({}), none);
    await empty.start();
    expect(empty.outcome, AiFindOutcome.found);
    expect(empty.picks, isEmpty);
    expect(empty.summary, '你的書源裡沒有');
    expect(none.toolResults(2).single, contains('沒有搜到書'));
  });

  test('stop cancels the search that is running', () async {
    final library = _Library({})..searchGate = Completer<void>();
    final ai = _Ai([
      _calls([
        ('search', {'keyword': '穿越'}),
      ]),
    ]);
    final find = session(library, ai);
    final running = find.start();
    await pumpEventQueue();
    expect(library.calls, ['search 穿越 novel']);
    find.stop();
    await running.timeout(const Duration(seconds: 5));
    expect(library.searchCancelled, isTrue);
    expect(find.outcome, AiFindOutcome.stopped);
  });

  test('unreadable calls and a book number that was never given are told '
      'back to the AI', () async {
    final ai = _Ai([
      _calls([
        ('detail', {'book': 'b7'}),
        ('dance', {}),
        ('search', {}),
      ]),
      _calls([
        ('submit', {'books': [], 'summary': '沒找到'}),
      ]),
    ]);
    final find = session(_Library({}), ai);
    await find.start();
    final results = ai.toolResults(2);
    expect(results[0], contains('沒有編號 b7 的書'));
    expect(
      results[1],
      allOf(startsWith(aiFindBadCall), contains('沒有叫 dance 的工具')),
    );
    expect(results[2], allOf(contains('少了必要的參數'), contains('keyword')));
  });

  test('a search says how many sources were asked, how many failed and '
      'how long it took', () async {
    final ai = _Ai([
      _calls([
        ('search', {'keyword': '穿越'}),
      ]),
    ]);
    await session(
      _Library({
        '穿越': [_book('獵魔人')],
      }),
      ai,
    ).start();
    expect(
      ai.toolResults(2).single,
      matches(RegExp(r'送了 3 個書源，1 個出錯或逾時，花 \d+\.\d 秒')),
    );
  });

  test('secrets of the sources the tools touched are masked in what the AI '
      'reads and in the log', () async {
    const secret = 'token-abc-123456';
    final library = _Library({
      '穿越': [_book('獵魔人$secret')],
    })..secrets.add(secret);
    final ai = _Ai([
      _calls([
        ('search', {'keyword': '穿越'}),
      ]),
    ]);
    final find = session(library, ai);
    await find.start();
    final result = ai.toolResults(2).single;
    expect(result, isNot(contains(secret)));
    expect(result, contains(aiRepairRedacted));
    final log = await (await find.log.file())!.readAsString();
    expect(log, isNot(contains(secret)));
  });

  test('arguments that are not JSON are dropped and the same conversation '
      'is sent again', () async {
    final ai = _Ai([
      (
        content: '',
        toolCalls: [(id: 'bad', name: 'search', arguments: '{"keyword">"x"}')],
        reasoning: '',
        usage: null,
        firstData: Duration.zero,
      ),
    ]);
    final find = session(_Library({}), ai);
    await find.start();
    expect(find.outcome, AiFindOutcome.found);
    expect(ai.seen[1], hasLength(ai.seen[0].length), reason: '寫壞的那則沒有接進對話');
  });

  group('every way of not converging ends as unfinished', () {
    AiReply noTool() => (
      content: '我想想',
      toolCalls: const [],
      reasoning: '',
      usage: null,
      firstData: Duration.zero,
    );
    // 每次交不同的編號：同樣的交出算同一個呼叫，第 4 次就先停了。
    AiReply submitUnknown(int i) => _calls([
      (
        'submit',
        {
          'books': [
            {'book': 'b${90 + i}', 'reason': '編的'},
          ],
          'summary': '交',
        },
      ),
    ]);

    for (final (name, script, reason) in [
      (
        'no tool call three rounds in a row',
        [for (var i = 0; i < 3; i++) noTool()],
        '連續 3 輪沒有呼叫工具',
      ),
      (
        'the same search four times',
        [
          for (var i = 0; i < 4; i++)
            _calls([
              ('search', {'keyword': '穿越'}),
            ]),
        ],
        '同樣的工具與參數第 4 次',
      ),
      (
        'a submit rejected five times',
        [for (var i = 0; i < 5; i++) submitUnknown(i)],
        '交出連續被退 5 次',
      ),
      (
        'rounds running out',
        [
          for (var i = 0; i < AiAgentKnobs.maxRounds; i++)
            _calls([
              ('search', {'keyword': '關鍵字$i'}),
            ]),
        ],
        '用完 ${AiAgentKnobs.maxRounds} 輪還沒交出',
      ),
    ]) {
      test(name, () async {
        final find = session(_Library({}), _Ai(script));
        await find.start();
        expect(find.outcome, AiFindOutcome.unfinished);
        expect(find.failure, contains(reason));
        expect(find.isRunning, isFalse);
        expect(
          find.rounds.where((r) => r.state == AiRepairStepState.running),
          isEmpty,
          reason: '頁面上沒有停在進行中的那一輪',
        );
      });
    }
  });

  test('every tool says which arguments it needs', () {
    for (final tool in aiFindTools) {
      final properties = tool.parameters['properties']! as Map;
      for (final name in tool.parameters['required']! as List) {
        expect(properties.keys, contains(name), reason: tool.name);
      }
    }
  });
}
