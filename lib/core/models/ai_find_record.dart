import 'dart:convert';

import 'json_read.dart';
import 'search_book.dart';

/// 推薦的一本：[book] 是找到它的那張書卡（點了照它的書源進書籍詳情），
/// [reason] 是 AI 寫的推薦理由。
typedef AiFindPick = ({SearchBook book, String reason});

/// 一次找書怎麼結束的。
enum AiFindOutcome {
  /// AI 交出了推薦（可能是零本）。
  found,

  /// 使用者按了停止。
  stopped,

  /// 沒找完：輪數用完、卡住、失控，或服務出了錯。
  unfinished;

  static AiFindOutcome parse(Object? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return unfinished;
  }
}

/// 一次 AI 找書留下的報告（ADR 0060）：搜尋頁「過去的找書」的一列，點了
/// 看那次的結果與 AI 的說明。一次一筆，進備份與同步（新的贏、刪除也同步）。
///
/// [id] 是開始找書時配的，兩台不會撞號；[depth] 是深度的名稱
/// （`AiFindDepth.name`），[createdAt] 是開始的時刻（毫秒）。
class AiFindRecord {
  AiFindRecord({
    required this.id,
    required this.description,
    required this.depth,
    required this.createdAt,
    required this.outcome,
    this.failure = '',
    this.summary = '',
    this.picks = const [],
    this.rounds = 0,
    this.tokens = 0,
  });

  final String id;
  final String description;
  final String depth;
  final int createdAt;
  final AiFindOutcome outcome;

  /// 沒找完時的原因；找完是空字串。
  final String failure;

  /// AI 交出時寫的說明。
  final String summary;
  final List<AiFindPick> picks;
  final int rounds;
  final int tokens;

  /// 資料表的 `picks` 欄：每本書卡的 JSON 加理由。
  String get picksJson => jsonEncode([
    for (final pick in picks)
      {'book': pick.book.toJson(), 'reason': pick.reason},
  ]);

  static List<AiFindPick> picksFrom(Object? json) {
    final list = switch (json) {
      final String text when text.isNotEmpty => _decodeList(text),
      final List<dynamic> list => list,
      _ => const <dynamic>[],
    };
    return [
      for (final item in list)
        if (item case {
          'book': final Map<String, dynamic> book,
          'reason': final String reason,
        })
          (book: SearchBook.fromJson(book), reason: reason),
    ];
  }

  static List<dynamic> _decodeList(String text) {
    try {
      return switch (jsonDecode(text)) {
        final List<dynamic> list => list,
        _ => const [],
      };
    } on FormatException {
      return const [];
    }
  }

  /// 資料表一列（`@UseRowClass`）：推薦存成 [picksJson] 那份文字。
  factory AiFindRecord.row({
    required String id,
    required String description,
    required String depth,
    required int createdAt,
    required AiFindOutcome outcome,
    required String failure,
    required String summary,
    required String picksJson,
    required int rounds,
    required int tokens,
  }) => AiFindRecord(
    id: id,
    description: description,
    depth: depth,
    createdAt: createdAt,
    outcome: outcome,
    failure: failure,
    summary: summary,
    picks: picksFrom(picksJson),
    rounds: rounds,
    tokens: tokens,
  );

  factory AiFindRecord.fromJson(Map<String, dynamic> json) => AiFindRecord(
    id: readJsonString(json['id']) ?? '',
    description: readJsonString(json['description']) ?? '',
    depth: readJsonString(json['depth']) ?? '',
    createdAt: readJsonInt(json['createdAt'], fallback: 0),
    outcome: AiFindOutcome.parse(json['outcome']),
    failure: readJsonString(json['failure']) ?? '',
    summary: readJsonString(json['summary']) ?? '',
    picks: picksFrom(json['picks']),
    rounds: readJsonInt(json['rounds'], fallback: 0),
    tokens: readJsonInt(json['tokens'], fallback: 0),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'description': description,
    'depth': depth,
    'createdAt': createdAt,
    'outcome': outcome.name,
    'failure': failure,
    'summary': summary,
    'picks': [
      for (final pick in picks)
        {'book': pick.book.toJson(), 'reason': pick.reason},
    ],
    'rounds': rounds,
    'tokens': tokens,
  };
}
