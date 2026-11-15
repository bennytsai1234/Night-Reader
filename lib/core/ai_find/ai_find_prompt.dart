import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:night_reader/core/ai_repair/agent_loop.dart';
import 'package:night_reader/core/ai_repair/ai_chat_client.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';

/// AI 找書的深度（ADR 0060）：交出時每本書要做到哪裡才收。
enum AiFindDepth {
  quick('快速', '從搜尋結果的書名、字數與簡介開頭挑，不必每本都點開看。'),
  normal('一般', '每本都去看詳情（簡介、分類、字數）再推薦。'),
  deep('深入', '每本都去看詳情，小說再試讀一章正文，讀不到的寫明原因；漫畫、有聲書照一般。');

  const AiFindDepth(this.label, this.explanation);
  final String label;

  /// 開始前的頁面上，深度切換下面那一行：這個深度每本書查到哪裡才推薦。
  /// 和提示詞的「深度決定每本要查到哪裡才收」、交出時的檢查同一套。
  final String explanation;

  static AiFindDepth fromName(String? name) =>
      values.asNameMap()[name] ?? AiFindDepth.normal;
}

/// 要找幾本：使用者在開始前輸入，預設 [aiFindDefaultCount]，最多
/// [aiFindMaxCount]（交出時一本一本查到深度要的地方，本數越多越久）。
const int aiFindDefaultCount = 10;
const int aiFindMaxCount = 30;

/// 搜尋一次給 AI 幾本，其餘的用 page 接著拿。
const int aiFindSearchPageSize = 30;

/// 讀章節一次給幾字。
const int aiFindReadLength = 3000;

/// AI 呼叫的工具（[aiFindTools]）。
sealed class AiFindCommand {
  const AiFindCommand();

  static AiFindCommand? fromCall(String name, Map<String, dynamic> args) {
    int? integer(String key) => switch (args[key]) {
      final int value => value,
      final String value => int.tryParse(value.trim()),
      null => null,
      _ => -1,
    };
    String? text(String key) => switch (args[key]) {
      final String value when value.trim().isNotEmpty => value.trim(),
      _ => null,
    };
    // 編號寫成 3、"3"、"B3" 都認成 b3。
    String? id(Object? value, String prefix) {
      final raw = switch (value) {
        final String v => v.trim().toLowerCase(),
        final int v => '$v',
        _ => '',
      };
      if (raw.isEmpty) return null;
      return RegExp(r'^\d+$').hasMatch(raw) ? '$prefix$raw' : raw;
    }

    switch (name) {
      case 'search':
        final keyword = text('keyword');
        final kind = _kinds[text('kind') ?? 'novel'];
        final page = integer('page') ?? 1;
        if (keyword == null || kind == null || page < 1) return null;
        return AiFindSearch(keyword, kind, page);
      case 'detail':
        final book = id(args['book'], 'b');
        return book == null ? null : AiFindDetail(book);
      case 'read':
        final book = id(args['book'], 'b');
        final chapter = integer('chapter') ?? 1;
        final from = integer('from') ?? 0;
        if (book == null || chapter < 1 || from < 0) return null;
        return AiFindRead(book, chapter, from);
      case 'explore':
        final category = integer('category');
        final page = integer('page') ?? 1;
        if ((category ?? 0) < 0 || page < 1) return null;
        return AiFindExplore(id(args['source'], 's'), category, page);
      case 'names':
        final work = text('name');
        return work == null ? null : AiFindNames(work);
      case 'shelf':
        return const AiFindShelf();
      case 'submit':
        final summary = text('summary');
        final books = args['books'];
        if (summary == null || books is! List) return null;
        final picks = <({String book, String reason})>[];
        for (final item in books) {
          if (item is! Map) return null;
          final book = id(item['book'], 'b');
          final reason = switch (item['reason']) {
            final String value when value.trim().isNotEmpty => value.trim(),
            _ => null,
          };
          if (book == null || reason == null) return null;
          picks.add((book: book, reason: reason));
        }
        return AiFindSubmit(picks, summary);
    }
    return null;
  }

  static const Map<String, BookSourceKind> _kinds = {
    'novel': BookSourceKind.novel,
    'comic': BookSourceKind.comic,
    'audio': BookSourceKind.audio,
  };
}

final class AiFindSearch extends AiFindCommand {
  const AiFindSearch(this.keyword, this.kind, this.page);
  final String keyword;
  final BookSourceKind kind;
  final int page;
}

final class AiFindDetail extends AiFindCommand {
  const AiFindDetail(this.book);
  final String book;
}

final class AiFindRead extends AiFindCommand {
  const AiFindRead(this.book, this.chapter, this.from);
  final String book;
  final int chapter;
  final int from;
}

/// 沒給 [source] 是列有發現頁的書源；給了 [source]、沒給 [category] 是列
/// 它的分類；都給了是那個分類第 [page] 頁的書。
final class AiFindExplore extends AiFindCommand {
  const AiFindExplore(this.source, this.category, this.page);
  final String? source;
  final int? category;
  final int page;
}

/// 查一部作品在中文維基百科的條目與各地寫法。
final class AiFindNames extends AiFindCommand {
  const AiFindNames(this.name);
  final String name;
}

final class AiFindShelf extends AiFindCommand {
  const AiFindShelf();
}

final class AiFindSubmit extends AiFindCommand {
  const AiFindSubmit(this.books, this.summary);
  final List<({String book, String reason})> books;
  final String summary;
}

Map<String, Object?> _object(
  Map<String, Object?> properties, [
  List<String> required = const [],
]) => {'type': 'object', 'properties': properties, 'required': required};

const Map<String, Object?> _book = {
  'type': 'string',
  'description': '書的編號，例如 b3（搜尋、發現頁的結果裡給的）',
};

final List<AiTool> aiFindTools = [
  (
    name: 'search',
    description:
        '用關鍵字搜使用者的書源（書名、作者或題材字眼都可以，照各書源自己的搜尋）。'
        '同一本合併成一筆，一次回 $aiFindSearchPageSize 本：編號、書名、作者、字數、'
        '分類、最新章節、幾個書源有。',
    parameters: _object(
      {
        'keyword': {'type': 'string', 'description': '關鍵字'},
        'kind': {
          'type': 'string',
          'enum': ['novel', 'comic', 'audio'],
          'description': '搜哪一類書：novel 小說、comic 漫畫、audio 有聲書，預設 novel',
        },
        'page': {'type': 'integer', 'description': '第幾批，從 1 數，預設 1'},
      },
      ['keyword'],
    ),
  ),
  (
    name: 'detail',
    description: '看一本書的詳情：簡介、分類與標籤、字數、最新章節。',
    parameters: _object({'book': _book}, ['book']),
  ),
  (
    name: 'read',
    description:
        '讀一本小說的某一章，一次給 $aiFindReadLength 字，寫出這章共幾字、下一段從哪讀。'
        '漫畫與有聲書讀不了正文。',
    parameters: _object(
      {
        'book': _book,
        'chapter': {'type': 'integer', 'description': '第幾章，從 1 數，預設 1'},
        'from': {'type': 'integer', 'description': '從這章第幾字讀起，預設 0'},
      },
      ['book'],
    ),
  ),
  (
    name: 'explore',
    description:
        '看書源的發現頁（排行、分類這些書單）。不給參數：列有發現頁的書源；'
        '給 source：列它的分類；再給 category：列那個分類的書，'
        '一次一頁。',
    parameters: _object({
      'source': {'type': 'string', 'description': '書源的編號，例如 s2'},
      'category': {'type': 'integer', 'description': '分類的編號，從 0 數'},
      'page': {'type': 'integer', 'description': '第幾頁，從 1 數，預設 1'},
    }),
  ),
  (
    name: 'names',
    description:
        '查一部作品的各地譯名與簡稱：查中文維基百科，回條目名、台灣、中國大陸、'
        '香港各自的寫法與條目開頭一段。兩岸譯名常不同字（例如「鏈鋸人」與「電鋸人」），'
        '書源的搜尋只比對書名，每個寫法都要搜才找得齊。',
    parameters: _object(
      {
        'name': {'type': 'string', 'description': '作品名稱或簡稱'},
      },
      ['name'],
    ),
  ),
  (
    name: 'shelf',
    description: '看使用者的書架與閱讀紀錄：書名、作者、類別、讀了多久、讀到哪。',
    parameters: _object({}),
  ),
  (
    name: 'submit',
    description:
        '交出推薦：每本寫編號與推薦理由，另寫一段整體的說明。'
        '什麼都沒找到時 books 給空的，說明為什麼。',
    parameters: _object(
      {
        'books': {
          'type': 'array',
          'items': _object(
            {
              'book': _book,
              'reason': {'type': 'string', 'description': '推薦理由：哪裡符合使用者的描述'},
            },
            ['book', 'reason'],
          ),
        },
        'summary': {'type': 'string', 'description': '整體的說明：怎麼找的、為什麼是這幾本'},
      },
      ['books', 'summary'],
    ),
  ),
];

/// 系統提示：每次找書都一樣，服務的快取每次都打得中。
const String aiFindSystemPrompt =
    '你是夜讀的找書員：使用者用一段話描述想看的書，你用工具在他自己的書源裡搜、'
    '比較、讀，交出值得一讀的幾本與理由。互不相依的查詢放在同一次回覆一起呼叫，'
    '要看前一個結果才知道下一步的留到下一次。\n\n'
    '# 規則\n'
    '- 只能推薦工具回過的書，用它的編號交出。\n'
    '- 推薦的書從搜尋結果裡挑，和描述有部分相符就可以推。\n'
    '- 使用者提到的作品他已經看過，原作本身不推薦；他要的是那部作品的同人與延伸'
    '（穿越或重生到那個世界、綜漫或諸天裡有這部作品），不是風格相似、和原作無關'
    '的書。\n'
    '- 合不合看故事，不看字眼：穿越、重生、爽文、系統這類，簡介和分類常不會照字'
    '寫，要從故事判斷（例如主角從現代到了另一個世界是穿越，一路變強、壓過對手是'
    '爽文）。描述裡的條件是偏好，部分相符就可以推。\n'
    '- 交出使用者要的本數（「本數」那一段）：相關的不夠時有幾本交幾本，說明裡寫'
    '為什麼不夠；超過本數會被退回。\n'
    '- 乙女向（女主角和原作男角色談戀愛）與成人向的書可以搜、可以看，但只有描述'
    '提到、或書架上讀的就是那一類時才推薦；其他時候不推薦。\n'
    '- 使用者列了「不想看的」（例如女頻、後宮）時，那幾類的書可以搜、可以看，但不'
    '推薦；合不合看故事，不看字眼。這次的描述明確說要其中一類時，照描述。\n'
    '- 描述沒寫偏好時，書架與閱讀紀錄（shelf）看得出他看過什麼、偏好哪一類（男頻、'
    '女頻、乙女向、成人向），照那類挑；上面的書算看過，不推薦。\n'
    '- 推薦理由寫這本哪裡相符、哪裡不確定或不符，依據是你從工具看到的書名、分類、'
    '簡介、正文。\n'
    '- 深度決定每本要查到哪裡才收：快速是工具回過就收；一般是每本都看過詳情；'
    '深入是每本都看過詳情，小說還要讀過至少一章（讀不到的寫明讀不到的原因也收）。'
    '交出不合的書會被退回並列出哪幾本不合。\n\n'
    '# 找法\n'
    '1. 弄清楚他說的是什麼：提到作品時，用 names 查每部作品（同一次回覆一起查），'
    '從條目開頭判斷是不是他說的那部；不是時從「其他條目」挑對的那個再查。記下各地'
    '寫法、別名，和你知道的主要角色、專有名詞。\n'
    '2. 擬搜尋策略：書源的搜尋比對的是書名與作者，一次搜尋要等近一分鐘、同時跑兩個，'
    '先搜最可能有收穫的。可以用的招：\n'
    '   - 作品名：各地寫法、別名、簡稱，找書名帶作品名的同人。\n'
    '   - 角色名與專有名詞：主角、人氣角色、組織，找書名用角色名的同人。\n'
    '   - 綜漫、諸天、無限流：書名不帶作品名，要看簡介有沒有這部作品。\n'
    '   - 沒提到作品時，搜描述裡的題材字眼。\n'
    '3. 每輪看收穫再決定：結果只列書名或作者含那個詞的書，分成完全相符、部分相符，'
    '每本附簡介開頭。相關的夠交出要的本數就去挑；太少就換下一招或翻下一批，不用'
    '每一招都試。\n'
    '4. 挑優：先看相符程度，再看篇幅（字數或章數）多、幾個書源有（越多通常越熱門）；'
    '同樣相符時篇幅長的優先，不到 30 萬字的也可以推，理由寫明篇幅短。完結、連載、'
    '停更都不影響挑選，篇幅夠讀就好，推薦理由不寫更新狀態與最後更新的時間，描述'
    '問到時才寫。照深度看詳情、讀章節確認。\n'
    '5. 交出；找不到相關的，交出零本並說明找了什麼。';

/// 第一輪送給 AI 的話：系統提示與這次的描述、深度、本數，和「不想看的」清單。
List<AiMessage> aiFindOpening({
  required String description,
  required AiFindDepth depth,
  int count = aiFindDefaultCount,
  List<String> avoid = const [],
}) => [
  const AiMessage.system(aiFindSystemPrompt),
  AiMessage.user(
    '# 使用者的描述\n$description\n\n# 深度\n${depth.label}\n\n# 本數\n$count'
    '${avoid.isEmpty ? '' : '\n\n# 不想看的\n${avoid.join('、')}'}',
  ),
];

/// 提示詞的版本：系統提示與工具清單的雜湊開頭，寫進紀錄。
final String aiFindPromptVersion = sha1
    .convert(
      utf8.encode(
        '$aiFindSystemPrompt\n${jsonEncode(aiToolsJson(aiFindTools))}',
      ),
    )
    .toString()
    .substring(0, 8);

/// 工具呼叫讀不懂時回給 AI 的話的開頭。
const String aiFindBadCall = '# 讀不懂這個工具呼叫';

/// 讀 AI 呼叫的一個工具：讀得懂時是指令與它的 key，讀不懂時 [fact] 說哪裡
/// 不對。交出的 key 不含理由與說明以外的差別：同一批書換個說法交出也算同一次。
({AiFindCommand? command, String key, String fact, bool malformed})
readAiFindCall(AiToolCall call) {
  final decoded = decodeToolCall(call, aiFindTools, badCall: aiFindBadCall);
  final args = decoded.args;
  if (args == null) {
    return (
      command: null,
      key: '',
      fact: decoded.fact,
      malformed: decoded.malformed,
    );
  }
  final command = AiFindCommand.fromCall(call.name, args);
  if (command == null) {
    return (
      command: null,
      key: '',
      fact: missingToolArguments(call, aiFindTools, aiFindBadCall),
      malformed: false,
    );
  }
  final key = switch (command) {
    AiFindSearch(:final keyword, :final kind, :final page) =>
      'search $keyword ${kind.name} $page',
    AiFindDetail(:final book) => 'detail $book',
    AiFindRead(:final book, :final chapter, :final from) =>
      'read $book $chapter $from',
    AiFindExplore(:final source, :final category, :final page) =>
      'explore $source $category $page',
    AiFindNames(:final name) => 'names $name',
    AiFindShelf() => 'shelf',
    AiFindSubmit(:final books) => 'submit ${[for (final b in books) b.book]}',
  };
  return (command: command, key: key, fact: '', malformed: false);
}
