import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_find/ai_find_library.dart';
import 'package:night_reader/core/ai_find/ai_find_prompt.dart';
import 'package:night_reader/core/ai_find/ai_find_session.dart';
import 'package:night_reader/core/ai_repair/agent_loop.dart';
import 'package:night_reader/core/ai_repair/ai_chat_client.dart';
import 'package:night_reader/core/ai_repair/ai_repair_log.dart';
import 'package:night_reader/core/ai_repair/ai_repair_secrets.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart'
    show AiRepairStepState;
import 'package:night_reader/core/models/ai_find_record.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/core/services/chinese_utils.dart';

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
  String? detailIntro;
  int pending = 0;

  /// 指定某本在搜尋頁的哪一段。
  Map<String, int> tierOf = {};
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
    final books = results[keyword] ?? const <SearchBook>[];
    return (
      books: books,
      // 沒指定的都算部分相符（假書庫的書名不一定含關鍵字）。
      tiers: [for (final book in books) tierOf[book.name] ?? 1],
      sources: 3,
      failed: 1,
      pending: pending,
    );
  }

  @override
  Future<Book> detail(SearchBook book, CancelToken cancelToken) async {
    calls.add('detail ${book.name}');
    return Book(
      name: book.name,
      author: book.author ?? '',
      intro: detailIntro ?? '${book.name}：穿越後獵魔升級',
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
    final index = number == aiFindLastChapter ? 2 : number;
    if (index > 2) throw const AiFindUnreadable('沒有這一章，共 2 章');
    return (title: '第$index章', text: '字' * 4500, number: index, total: 2);
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

  /// 給了時書架上是這一本（有書源、有分類與簡介），不然是沒有書源的詭秘之主。
  SearchBook? shelfBook;

  @override
  Future<List<AiFindShelfEntry>> shelf() async => [
    (
      name: shelfBook?.name ?? '詭秘之主',
      author: shelfBook?.author ?? '烏賊',
      kind: BookSourceKind.novel,
      onShelf: true,
      local: false,
      readSeconds: 7200,
      chapter: '第100章',
      chapterIndex: 100,
      chapterTotal: 1400,
      category: shelfBook == null ? null : '都市,後宮',
      intro: shelfBook == null ? null : '穿越後的豔遇人生',
      book: shelfBook,
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
    int count = aiFindDefaultCount,
    List<String> avoid = const [],
  }) {
    final find = AiFindSession(
      description: '爽文、穿越，想要更刺激的',
      depth: depth,
      count: count,
      avoid: avoid,
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
        ('read', {'book': 'b1', 'chapter': -1}),
        ('read', {'book': 'b2', 'chapter': -1}),
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
    expect(reads[1], contains('第 2／2 章（最後一章） 第2章'));
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

  test('deep: a novel read only from the start is sent back to read its last '
      'chapter; reading the last chapter by number counts too', () async {
    final ai = _Ai([
      _calls([
        ('search', {'keyword': '穿越'}),
      ]),
      _calls([
        ('detail', {'book': 'b1'}),
        ('detail', {'book': 'b2'}),
        ('read', {'book': 'b1', 'chapter': 1}),
        ('read', {'book': 'b2', 'chapter': 2}),
      ]),
      _calls([
        (
          'submit',
          {
            'books': [
              {'book': 'b1', 'reason': '獵魔'},
              {'book': 'b2', 'reason': '斬妖'},
            ],
            'summary': '先交',
          },
        ),
      ]),
      _calls([
        ('read', {'book': 'b1', 'chapter': -1}),
      ]),
      _calls([
        (
          'submit',
          {
            'books': [
              {'book': 'b1', 'reason': '獵魔，最後一章是斷更公告，可能太監'},
              {'book': 'b2', 'reason': '斬妖'},
            ],
            'summary': '讀過頭尾',
          },
        ),
      ]),
    ]);
    final find = session(
      _Library({
        '穿越': [_book('獵魔人'), _book('斬妖')],
      }),
      ai,
      depth: AiFindDepth.deep,
    );
    await find.start();
    final rejected = ai.toolResults(4).single;
    expect(rejected, contains('b1《獵魔人》：還沒讀過最後一章'));
    expect(rejected, isNot(contains('b2')), reason: '讀了第 2／2 章就是最後一章');
    expect(find.picks.map((p) => p.book.name), ['獵魔人', '斬妖']);
  });

  test('the AI is told how many books to find; handing in more is sent back '
      'to pick the best ones', () async {
    final ai = _Ai([
      _calls([
        ('search', {'keyword': '穿越'}),
      ]),
      _calls([
        (
          'submit',
          {
            'books': [
              {'book': 'b1', 'reason': '獵魔'},
              {'book': 'b2', 'reason': '斬妖'},
            ],
            'summary': '兩本',
          },
        ),
      ]),
      _calls([
        (
          'submit',
          {
            'books': [
              {'book': 'b2', 'reason': '斬妖'},
            ],
            'summary': '最合的一本',
          },
        ),
      ]),
    ]);
    final find = session(
      _Library({
        '穿越': [_book('獵魔人'), _book('斬妖')],
      }),
      ai,
      depth: AiFindDepth.quick,
      count: 1,
    );
    await find.start();
    expect(ai.seen.first[1].content, contains('# 本數\n1'));
    expect(ai.toolResults(3).single, contains('交了 2 本，使用者要 1 本：挑最合的 1 本再交'));
    expect(find.picks.map((p) => p.book.name), ['斬妖']);
  });

  test('searches in one reply run at the same time, the same search runs '
      'once, and the results come back in call order', () async {
    final library = _Library({
      '穿越': [_book('獵魔人')],
      '爽文': [_book('斬妖')],
    })..searchGate = Completer<void>();
    final ai = _Ai([
      _calls([
        ('search', {'keyword': '穿越'}),
        ('search', {'keyword': '爽文'}),
        ('search', {'keyword': '穿越'}),
      ]),
    ]);
    final find = session(library, ai);
    final running = find.start();
    await pumpEventQueue();
    expect(library.calls, [
      'search 穿越 novel',
      'search 爽文 novel',
    ], reason: '兩個都已經送出，第三個等第一個');
    library.searchGate!.complete();
    await running;
    final results = ai.toolResults(2);
    expect(results, hasLength(3));
    expect(results[0], contains('搜尋「穿越」'));
    expect(results[1], contains('搜尋「爽文」'));
    expect(results[2], contains('b1｜獵魔人'));
    expect(find.rounds.first.detail, contains('搜尋「穿越」小說，找到 1 本'));
    expect(find.rounds.first.detail, isNot(contains('…')));
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

  test('only books the AI was shown get a number, and a field with a line '
      'break stays on its book line', () async {
    final library = _Library({
      '穿越': [for (var i = 0; i < 40; i++) _book('穿越$i')],
      '爽文': [
        SearchBook(
          bookUrl: 'https://a.test/爽',
          name: '爽文',
          author: '作者',
          origin: 'https://a.test',
          kind: '完结\n{{\$..shortName',
        ),
      ],
    });
    final ai = _Ai([
      _calls([
        ('search', {'keyword': '穿越'}),
        ('search', {'keyword': '爽文'}),
      ]),
    ]);
    await session(library, ai).start();
    final results = ai.toolResults(2);
    expect(results.first, contains('b30｜穿越29'));
    expect(results.first, isNot(contains('b31')));
    expect(
      results.last,
      contains('b31｜爽文｜作者｜完结 {{\$..shortName｜1 個書源'),
      reason: '第一次只給看了 30 本，下一本接 b31',
    );
  });

  test('search results are split into the search page tiers, each book '
      'shows the start of its intro, and sources cut off by the time limit '
      'are counted', () async {
    final library =
        _Library({
            '咒術迴戰': [_book('咒術迴戰'), _book('咒術迴戰：反派第一人'), _book('我在忍界搞咒術')],
          })
          ..pending = 40
          ..tierOf = {'咒術迴戰': 0, '咒術迴戰：反派第一人': 1, '我在忍界搞咒術': 2};
    final ai = _Ai([
      _calls([
        ('search', {'keyword': '咒術迴戰'}),
      ]),
    ]);
    await session(library, ai).start();
    final result = ai.toolResults(2).single;
    expect(result, contains('40 個到時限還沒回來、不等了'));
    final lines = result.split('\n');
    expect(lines.sublist(1), [
      '## 完全相符',
      startsWith('b1｜咒術迴戰｜'),
      '## 部分相符',
      startsWith('b2｜咒術迴戰：反派第一人｜'),
    ]);
    expect(lines.first, contains('另有 1 本書名與作者都不含這個詞，沒列出'));
    expect(lines[2], endsWith('｜簡介：咒術迴戰 的簡介'));
  });

  test('a filter keeps the searched books whose name, category or intro has '
      'every group, in simplified or traditional, without searching again', () {
    // App 裡搜尋開始前就載好字典（SearchModel）；這裡只給比對用到的字。
    ChineseUtils.initializeFromDictionaryData(['', '', '', '後\t后\n宮\t宫\n']);
    SearchBook withIntro(String name, String intro, {String? kind}) =>
        _book(name)
          ..intro = intro
          ..kind = kind;
    final library = _Library({
      '穿越': [
        withIntro('穿越射鵰', '郭靖的兄弟', kind: '武俠,後宮'),
        withIntro('穿越之偷香', '回到金庸的世界，一路后宫'),
        withIntro('穿越金庸', '一心練武，無女主'),
        withIntro('穿越末世', '末世求生，後宮'),
      ],
    })..tierOf = {'穿越射鵰': 0};
    final ai = _Ai([
      _calls([
        ('search', {'keyword': '穿越', 'filter': '後宮 金庸|射鵰'}),
        ('search', {'keyword': '穿越', 'filter': '星際'}),
      ]),
    ]);
    return session(library, ai).start().then((_) {
      final results = ai.toolResults(2);
      final lines = results.first.split('\n');
      expect(lines.first, contains('篩選「後宮 金庸|射鵰」：4 本裡符合 2 本'));
      expect(lines.sublist(1), [
        '## 完全相符',
        startsWith('b1｜穿越射鵰｜'),
        '## 部分相符',
        startsWith('b2｜穿越之偷香｜'),
      ]);
      expect(results.last, contains('篩選「星際」：4 本裡符合 0 本'));
      expect(
        library.calls.where((call) => call.startsWith('search')),
        hasLength(1),
        reason: '換篩選詞用同一次搜尋的結果',
      );
    });
  });

  test('the same search with another filter is not the same call', () {
    AiToolCall call(Map<String, Object?> args) =>
        (id: 'c', name: 'search', arguments: jsonEncode(args));
    expect(
      readAiFindCall(call({'keyword': '穿越', 'filter': '後宮'})).key,
      isNot(readAiFindCall(call({'keyword': '穿越', 'filter': '金庸'})).key),
    );
  });

  test('the shelf tells each book its category and the start of its intro, '
      'and a shelf book with a source gets a number to look at and '
      'recommend', () async {
    final library = _Library({})
      ..shelfBook = _book('偷香高手', author: '小刀')
      ..detailIntro = '穿越到金庸的世界';
    final ai = _Ai([
      _calls([('shelf', {})]),
      _calls([
        ('detail', {'book': 'b1'}),
        ('read', {'book': 'b1'}),
      ]),
      _calls([
        (
          'submit',
          {
            'books': [
              {'book': 'b1', 'reason': '在你書架上'},
            ],
            'summary': '照書架',
          },
        ),
      ]),
    ]);
    final find = session(library, ai, count: 1);
    await find.start();
    final shelf = ai.toolResults(2).single;
    expect(
      shelf,
      contains(
        'b1｜偷香高手｜小刀｜小說｜讀了 2.0 小時｜讀到第 100／1400 章｜'
        '分類：都市,後宮｜簡介：穿越後的豔遇人生',
      ),
    );
    expect(library.calls, containsAll(['detail 偷香高手', 'chapter 偷香高手 1']));
    expect(find.picks.single.book.name, '偷香高手');
  });

  test('a submit before a detail in the same reply is judged before that '
      'detail runs', () async {
    final library = _Library({
      '穿越': [_book('獵魔人')],
    });
    final ai = _Ai([
      _calls([
        ('search', {'keyword': '穿越'}),
      ]),
      _calls([
        (
          'submit',
          {
            'books': [
              {'book': 'b1', 'reason': '獵魔'},
            ],
            'summary': '先交',
          },
        ),
        ('detail', {'book': 'b1'}),
      ]),
    ]);
    await session(library, ai).start();
    final results = ai.toolResults(3);
    expect(results.first, contains('b1《獵魔人》：還沒看過詳情'));
    expect(results.last, contains('# b1 的詳情'));
  });

  test('the same book spelled with different width or spaces keeps one '
      'number and cannot be recommended twice', () async {
    final library = _Library({
      '獵魔': [_book('獵魔人')],
      '人': [
        SearchBook(
          bookUrl: 'https://b.test/x',
          name: '獵魔 人',
          author: '作者',
          origin: 'https://b.test',
        ),
      ],
    });
    final ai = _Ai([
      _calls([
        ('search', {'keyword': '獵魔'}),
        ('search', {'keyword': '人'}),
      ]),
    ]);
    await session(library, ai, depth: AiFindDepth.quick).start();
    final results = ai.toolResults(2);
    expect(results.last, contains('b1｜'), reason: '第二次搜到的同一本還是 b1');
    expect(results.last, isNot(contains('b2')));
  });

  test('a detail says how many chapters the book has, or that the page does '
      'not say', () async {
    final ai = _Ai([
      _calls([
        ('search', {'keyword': '穿越'}),
      ]),
      _calls([
        ('detail', {'book': 'b1'}),
      ]),
    ]);
    await session(
      _Library({
        '穿越': [_book('獵魔人')],
      }),
      ai,
    ).start();
    expect(ai.toolResults(3).single, contains('章數：詳情頁沒寫'));
  });

  test('names tells every regional name of a work, or that there is no '
      'entry', () async {
    final ai = _Ai([
      _calls([
        ('names', {'name': '鏈鋸人'}),
        ('names', {'name': '沒有這部'}),
      ]),
    ]);
    await session(_Library({}), ai).start();
    final results = ai.toolResults(2);
    expect(results.first, contains('條目《鏈鋸人》'));
    expect(results.first, contains('中國大陸：电锯人'));
    expect(results.first, contains('開頭：《鏈鋸人》是由日本漫畫家'));
    expect(results.first, contains('別名（轉到這個條目的名稱）：電鋸人、Chainsaw Man'));
    expect(results.first, contains('同一個詞搜到的其他條目：鏈鋸人角色列表'));
    expect(results.last, contains('中文維基百科沒有「沒有這部」的條目'));
  });

  test('a detail with HTML tags and line breaks reads as plain text', () async {
    final library = _Library({
      '穿越': [_book('獵魔人')],
    })..detailIntro = '<div class="intro">獵魔人：<br>穿越後<b>獵魔</b>升級</div>';
    final ai = _Ai([
      _calls([
        ('search', {'keyword': '穿越'}),
      ]),
      _calls([
        ('detail', {'book': 'b1'}),
      ]),
    ]);
    await session(library, ai).start();
    final detail = ai.toolResults(3).single;
    expect(detail, contains('簡介：獵魔人：\n穿越後獵魔升級'));
    expect(detail, isNot(contains('<')));
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

  group('pause and resume', () {
    _Library library() => _Library({
      '穿越': [_book('獵魔人'), _book('斬妖')],
    });
    List<AiReply> script() => [
      _calls([
        ('search', {'keyword': '穿越'}),
        ('shelf', {}),
      ]),
      _calls([
        ('explore', {}),
        ('detail', {'book': 'b1'}),
      ]),
      _calls([
        ('explore', {'source': 's1', 'category': 0}),
      ]),
      _calls([
        (
          'submit',
          {
            'books': [
              {'book': 'b1', 'reason': '獵魔'},
              {'book': 'b2', 'reason': '斬妖'},
            ],
            'summary': '先交',
          },
        ),
      ]),
      _calls([
        ('detail', {'book': 'b2'}),
        ('read', {'book': 'b1', 'chapter': 1}),
        ('read', {'book': 'b2', 'chapter': 1}),
        ('read', {'book': 'b1', 'chapter': -1}),
        ('read', {'book': 'b2', 'chapter': -1}),
      ]),
      _calls([
        (
          'submit',
          {
            'books': [
              {'book': 'b1', 'reason': '穿越後獵魔'},
              {'book': 'b2', 'reason': '升級爽文'},
            ],
            'summary': '讀過兩本',
          },
        ),
      ]),
    ];
    String sent(List<AiMessage> messages) =>
        jsonEncode([for (final m in messages) agentMessageToJson(m)]);

    test(
      'stopping before any round and resuming from what was saved sends '
      'what an uninterrupted find sends and ends with the same picks',
      () async {
        // 深入：交出要看過詳情、讀過正文，接著做時看過什麼要從存檔讀回來；
        // 發現頁的書源編號與書的編號也要接得上；「不想看的」清單也一樣。
        final ai = _Ai(script());
        final full = session(
          library(),
          ai,
          depth: AiFindDepth.deep,
          avoid: ['女頻', '後宮'],
        );
        final saved = <String>[];
        full.onCheckpoint = saved.add;
        await full.start();
        expect(ai.seen.first[1].content, endsWith('# 不想看的\n女頻、後宮'));
        expect(full.outcome, AiFindOutcome.found);
        expect(full.picks.map((p) => p.book.name), ['獵魔人', '斬妖']);
        expect(saved, hasLength(6));

        for (final (k, progress) in saved.indexed) {
          final next = _Ai(script().sublist(k));
          final resumed = AiFindSession.restore(
            progress,
            library: library(),
            ask: next.call,
            log: AiRepairLog.find(
              description: '爽文、穿越',
              directory: () async => logs,
            ),
          );
          sessions.add(resumed);
          final again = <String>[];
          resumed.onCheckpoint = again.add;
          expect(resumed.rounds, hasLength(k));
          expect(resumed.nextRound, k + 1);
          await resumed.start();
          expect(
            next.seen.map(sent),
            ai.seen.sublist(k).map(sent),
            reason: '從第 ${k + 1} 輪前接著做',
          );
          expect(resumed.outcome, full.outcome);
          expect(resumed.picks.map((p) => p.book.name), ['獵魔人', '斬妖']);
          expect(
            resumed.picks.first.book.origins,
            full.picks.first.book.origins,
          );
          expect(resumed.tokens, full.tokens);
          expect(resumed.rounds, hasLength(full.rounds.length));
          expect(resumed.record!.id, full.record!.id);
        }
      },
    );

    test('pause stops the running search and leaves the find paused, not '
        'ended', () async {
      final lib = _Library({})..searchGate = Completer<void>();
      final ai = _Ai([
        _calls([
          ('search', {'keyword': '穿越'}),
        ]),
      ]);
      final find = session(lib, ai);
      final saved = <String>[];
      find.onCheckpoint = saved.add;
      final running = find.start();
      await pumpEventQueue();
      find.pause();
      expect(find.isPausing, isTrue);
      await running.timeout(const Duration(seconds: 5));
      expect(lib.searchCancelled, isTrue);
      expect(find.isPaused, isTrue);
      expect(find.isFinished, isFalse);
      expect(find.record, isNull, reason: '暫停不是結束，不存成過去的找書');
      expect(saved, hasLength(1), reason: '第一輪開頭就存了');
    });

    test('ending a paused find records it as ended', () async {
      final ai = _Ai(script());
      final find = session(library(), ai);
      final saved = <String>[];
      find.onCheckpoint = saved.add;
      await find.start();
      final paused = AiFindSession.restore(
        saved[2],
        library: library(),
        ask: _Ai(const []).call,
        log: AiRepairLog.find(
          description: '爽文、穿越',
          directory: () async => logs,
        ),
      );
      sessions.add(paused);
      paused.stop();
      expect(paused.outcome, AiFindOutcome.stopped);
      expect(paused.record!.failure, '已結束');
      expect(paused.record!.rounds, 2);
    });

    test('a save from another version is not resumed but still tells what '
        'the find was', () {
      final progress = jsonEncode({
        'version': aiFindProgressVersion + 1,
        'id': 'x',
        'description': '想看的',
        'depth': 'normal',
        'startedAt': 1,
        'rounds': [{}, {}],
        'tokens': 5,
      });
      expect(
        () => AiFindSession.restore(
          progress,
          library: library(),
          ask: _Ai(const []).call,
        ),
        throwsFormatException,
      );
      final record = AiFindSession.brokenRecord(progress, '接不下去')!;
      expect(record.outcome, AiFindOutcome.unfinished);
      expect(record.description, '想看的');
      expect(record.rounds, 2);
      expect(AiFindSession.brokenRecord('不是 JSON', '接不下去'), isNull);
    });
  });
}
