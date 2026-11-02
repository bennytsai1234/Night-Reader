import 'dart:convert';

import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';

import 'sync_kind.dart';
import 'sync_records.dart';

/// 書源的同步：一個書源一筆，用書源網址對上（ADR 0039）。
class SourceSync extends SyncKind {
  SourceSync({BookSourceDao? dao}) : _dao = dao ?? getIt<BookSourceDao>();

  final BookSourceDao _dao;

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

  static SyncRecord recordOf(BookSource source) {
    // 繞一次 JSON：規則物件換成一般的 Map，指紋才穩定。
    final json = jsonDecode(jsonEncode(source.toJson())) as Map<String, dynamic>
      ..remove('bookSourceUrl')
      ..removeWhere((key, _) => _localFields.contains(key));
    return SyncRecord(time: 0, data: json);
  }

  @override
  Future<Map<String, SyncRecord>> local() async => {
    for (final source in await _dao.getAll())
      if (source.bookSourceUrl.isNotEmpty)
        source.bookSourceUrl: recordOf(source),
  };

  @override
  Future<Map<String, SyncRecord>> apply(Map<String, SyncRecord> remote) async {
    final deleted = [
      for (final entry in remote.entries)
        if (entry.value.deleted) entry.key,
    ];
    final before = await _byUrl();
    final upserts = <BookSource>[];
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
      upserts.add(source);
    }
    if (upserts.isNotEmpty) await _dao.upsertAll(upserts);
    if (deleted.isNotEmpty) await _dao.deleteByUrls(deleted);

    // 套用後這台實際存下的樣子，下次同步和它比，看得出之後有沒有改過。
    final after = await _byUrl();
    return {
      for (final key in remote.keys)
        key: switch (after[key]) {
          final stored? => recordOf(stored),
          null => const SyncRecord(time: 0, data: {}, deleted: true),
        },
    };
  }

  Future<Map<String, BookSource>> _byUrl() async => {
    for (final source in await _dao.getAll()) source.bookSourceUrl: source,
  };
}
