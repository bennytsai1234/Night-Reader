import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/book/book_help.dart';
import 'package:night_reader/core/models/bookmark.dart';

import 'sync_kind.dart';
import 'sync_records.dart';

/// 書籤的同步：一個書籤一筆，用編號（建立時間加隨機數，`BookmarkDao.newId`）
/// 對上；刪除也同步（ADR 0039、0042）。
class BookmarkSync extends SyncKind {
  BookmarkSync({BookmarkDao? dao}) : _dao = dao ?? getIt<BookmarkDao>();

  final BookmarkDao _dao;

  static const String kind = 'bookmarks';

  @override
  String get name => kind;

  static SyncRecord recordOf(Bookmark bookmark) =>
      SyncRecord(time: 0, data: bookmark.toJson()..remove('id'));

  /// 書籤的內容是「哪本書、哪一章（章名）的第幾個字、選了什麼字」。章節
  /// 序號與錨點裡的序號只是這台目錄裡的座標：換源、書源插章時跟著變，讀到
  /// 的地方沒變，不算改過；沒有章名時才看序號。
  @override
  SyncFingerprint get fingerprint => _fingerprintOf;

  static String _fingerprintOf(SyncRecord record) {
    if (record.deleted) return record.fingerprint;
    final data = record.data;
    final title = data['chapterTitle'];
    final hasTitle = title is String && title.trim().isNotEmpty;
    return SyncRecord.fingerprintOf({
      'bookName': data['bookName'],
      'bookAuthor': data['bookAuthor'],
      if (hasTitle) 'chapterTitle': title.trim(),
      if (!hasTitle) 'chapterIndex': data['chapterIndex'],
      'charOffset': data['charOffset'],
      'excerpt': data['excerpt'],
    });
  }

  @override
  Future<Map<String, SyncRecord>> local() async => {
    for (final bookmark in await _dao.getAll())
      '${bookmark.id}': recordOf(bookmark),
  };

  @override
  Future<Map<String, SyncRecord>> apply(Map<String, SyncRecord> remote) async {
    final upserts = <Bookmark>[];
    final deleted = <int>[];
    final applied = <String, SyncRecord>{};
    for (final MapEntry(:key, value: record) in remote.entries) {
      final id = int.tryParse(key);
      if (id == null || id <= 0) continue;
      if (record.deleted) {
        deleted.add(id);
        applied[key] = record;
      } else {
        final bookmark = Bookmark.fromJson({
          ...record.data,
          'id': id,
          // 別台舊版還帶著「作者：」：照這台升級時清過的寫法，對得上書。
          'bookAuthor': BookHelp.stripAuthorLabel(
            '${record.data['bookAuthor'] ?? ''}',
          ),
        });
        upserts.add(bookmark);
        applied[key] = recordOf(bookmark);
      }
    }
    if (upserts.isNotEmpty) await _dao.upsertAll(upserts);
    if (deleted.isNotEmpty) await _dao.deleteByIds(deleted);
    return applied;
  }
}
