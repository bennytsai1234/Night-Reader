import 'dart:convert';

import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_kind.dart';
import 'sync_records.dart';

/// 書源的同步：一個書源一筆，用書源網址對上（ADR 0039）。
///
/// 書源改了網址是同一個書源換了身分：這台以前的網址記在 [SourceMoves]，
/// 跟著新網址那筆送上去（`movedFrom`）；另一台套用時，舊網址記著的書、
/// 正文與登入資料照編輯書源時的同一套搬過去，不是新增一個、刪掉一個。
class SourceSync extends SyncKind {
  SourceSync({
    BookSourceDao? dao,
    BookDao? bookDao,
    SharedPreferences? prefs,
    Future<void> Function(BookSource source, String previousUrl)? move,
  }) : _dao = dao ?? getIt<BookSourceDao>(),
       _bookDao = bookDao ?? getIt<BookDao>(),
       _moves = SourceMoves(prefs ?? getIt<SharedPreferences>()),
       _move = move ?? _saveEdited;

  final BookSourceDao _dao;
  final BookDao _bookDao;
  final SourceMoves _moves;
  final Future<void> Function(BookSource source, String previousUrl) _move;

  static Future<void> _saveEdited(BookSource source, String previousUrl) =>
      BookSourceService().saveEditedSource(source, previousUrl: previousUrl);

  /// 這台自己量出來或自己記的：回應時間與換源排序的權重照這台的網路變，
  /// 最後更新時間每次校驗都會改。不同步，套用雲端的書源時也保留這台的。
  static const Set<String> _localFields = {
    'respondTime',
    'weight',
    'lastUpdateTime',
  };

  static const String kind = 'sources';

  @override
  String get name => kind;

  static SyncRecord recordOf(BookSource source, {List<String>? movedFrom}) {
    // 繞一次 JSON：規則物件換成一般的 Map，指紋才穩定。
    final json = jsonDecode(jsonEncode(source.toJson())) as Map<String, dynamic>
      ..remove('bookSourceUrl')
      ..removeWhere((key, _) => _localFields.contains(key));
    if (movedFrom != null && movedFrom.isNotEmpty) {
      json['movedFrom'] = movedFrom;
    }
    return SyncRecord(time: 0, data: json);
  }

  @override
  Future<Map<String, SyncRecord>> local() async {
    final moves = _moves.read();
    return {
      for (final source in await _dao.getAll())
        if (source.bookSourceUrl.isNotEmpty)
          source.bookSourceUrl: recordOf(
            source,
            movedFrom: moves[source.bookSourceUrl],
          ),
    };
  }

  @override
  Future<Map<String, SyncRecord>> apply(Map<String, SyncRecord> remote) async {
    final deleted = [
      for (final entry in remote.entries)
        if (entry.value.deleted) entry.key,
    ];
    final before = await _byUrl();
    final upserts = <BookSource>[];
    final applied = <String, SyncRecord>{};
    for (final MapEntry(:key, value: record) in remote.entries) {
      if (record.deleted) continue;
      final existing = before[key];
      final source = BookSource.fromJson({
        ...record.data,
        'bookSourceUrl': key,
        if (existing != null) ...{
          'respondTime': existing.respondTime,
          'weight': existing.weight,
          'lastUpdateTime': existing.lastUpdateTime,
        },
      });
      final movedFrom = [
        for (final url in record.data['movedFrom'] as List? ?? const [])
          if (url is String && url != key) url,
      ];
      final previous = existing == null
          ? await _previousUrl(movedFrom, before)
          : null;
      if (previous != null) {
        await _move(source, previous);
      } else {
        upserts.add(source);
      }
      if (movedFrom.isNotEmpty) await _moves.set(key, movedFrom);
      // 這次寫進去的樣子，不重讀：寫完才又被編輯的，下次同步比得出來。
      applied[key] = recordOf(source, movedFrom: movedFrom);
    }
    if (upserts.isNotEmpty) await _dao.upsertAll(upserts);
    if (deleted.isNotEmpty) await _dao.deleteByUrls(deleted);
    for (final url in deleted) {
      applied[url] = const SyncRecord(time: 0, data: {}, deleted: true);
    }
    return applied;
  }

  /// 書源以前的網址裡，這台還記著的那個（有那個書源，或有書記著它）。
  Future<String?> _previousUrl(
    List<String> movedFrom,
    Map<String, BookSource> sources,
  ) async {
    for (final url in movedFrom.reversed) {
      if (sources.containsKey(url) ||
          (await _bookDao.bookUrlsFromOrigin(url)).isNotEmpty) {
        return url;
      }
    }
    return null;
  }

  Future<Map<String, BookSource>> _byUrl() async => {
    for (final source in await _dao.getAll()) source.bookSourceUrl: source,
  };
}

/// 書源改過網址的紀錄：現在的網址 → 以前用過的網址（舊的在前）。編輯書源
/// 改網址時記下（`BookSourceService.saveEditedSource`），同步時跟著送給別台。
class SourceMoves {
  SourceMoves(this._prefs);

  static const String _key = 'sync.source_moves';

  final SharedPreferences _prefs;

  Map<String, List<String>> read() {
    final raw = _prefs.getString(_key);
    if (raw == null) return {};
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return {};
      return {
        for (final MapEntry(:key, :value) in json.entries)
          if (value is List) '$key': [for (final url in value) '$url'],
      };
    } on FormatException {
      return {};
    }
  }

  /// [from] 改成 [to]：[from] 以前的網址也一起記到 [to] 底下。
  Future<void> record({required String from, required String to}) {
    final moves = read();
    final history = [...?moves.remove(from), from]..remove(to);
    return _write(moves..[to] = history.toSet().toList());
  }

  /// 照另一台記的換成同一份，兩台送上去的內容才一樣。
  Future<void> set(String url, List<String> movedFrom) =>
      _write(read()..[url] = movedFrom);

  Future<void> _write(Map<String, List<String>> moves) =>
      _prefs.setString(_key, jsonEncode(moves));
}
