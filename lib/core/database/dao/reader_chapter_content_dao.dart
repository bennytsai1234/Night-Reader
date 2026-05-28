import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:night_reader/core/models/reader_chapter_content.dart';
import '../app_database.dart';
import '../tables/app_tables.dart';

part 'reader_chapter_content_dao.g.dart';

@DriftAccessor(tables: [ReaderChapterContents])
class ReaderChapterContentDao extends DatabaseAccessor<AppDatabase>
    with _$ReaderChapterContentDaoMixin {
  ReaderChapterContentDao(super.db);

  static String contentKey({
    required String origin,
    required String bookUrl,
    required String chapterUrl,
  }) {
    final material = '$origin\n$bookUrl\n$chapterUrl';
    return sha1.convert(utf8.encode(material)).toString();
  }

  Future<String?> getContent({required String contentKey}) async {
    final entry = await getEntry(contentKey: contentKey);
    final content = entry?.content;
    return content == null || content.isEmpty ? null : content;
  }

  Future<ReaderChapterContentEntry?> getEntry({
    required String contentKey,
  }) async {
    final query = select(readerChapterContents)
      ..where((t) => t.contentKey.equals(contentKey));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return ReaderChapterContentEntry(
      contentKey: row.contentKey,
      origin: row.origin,
      bookUrl: row.bookUrl,
      chapterUrl: row.chapterUrl,
      chapterIndex: row.chapterIndex,
      status: ReaderChapterContentStatus.fromCode(row.status),
      content: row.content,
      failureMessage: row.failureMessage,
      updatedAt: row.updatedAt,
    );
  }

  Future<List<ReaderChapterContentEntry>> getAllEntries() async {
    final rows = await select(readerChapterContents).get();
    return rows
        .map(
          (row) => ReaderChapterContentEntry(
            contentKey: row.contentKey,
            origin: row.origin,
            bookUrl: row.bookUrl,
            chapterUrl: row.chapterUrl,
            chapterIndex: row.chapterIndex,
            status: ReaderChapterContentStatus.fromCode(row.status),
            content: row.content,
            failureMessage: row.failureMessage,
            updatedAt: row.updatedAt,
          ),
        )
        .toList();
  }

  Future<List<ReaderChapterContentEntry>> getEntriesByBookUrls(
    Iterable<String> bookUrls,
  ) async {
    final urls = bookUrls.where((url) => url.isNotEmpty).toSet();
    if (urls.isEmpty) return const <ReaderChapterContentEntry>[];
    final rows =
        await (select(readerChapterContents)
          ..where((t) => t.bookUrl.isIn(urls))).get();
    return rows
        .map(
          (row) => ReaderChapterContentEntry(
            contentKey: row.contentKey,
            origin: row.origin,
            bookUrl: row.bookUrl,
            chapterUrl: row.chapterUrl,
            chapterIndex: row.chapterIndex,
            status: ReaderChapterContentStatus.fromCode(row.status),
            content: row.content,
            failureMessage: row.failureMessage,
            updatedAt: row.updatedAt,
          ),
        )
        .toList();
  }

  Future<void> upsertEntry(ReaderChapterContentEntry entry) {
    return saveContent(
      contentKey: entry.contentKey,
      origin: entry.origin,
      bookUrl: entry.bookUrl,
      chapterUrl: entry.chapterUrl,
      chapterIndex: entry.chapterIndex,
      content: entry.content ?? '',
      updatedAt: entry.updatedAt,
      status: entry.status,
      failureMessage: entry.failureMessage,
    );
  }

  Future<bool> hasContent({required String contentKey}) async {
    return hasReadyContent(contentKey: contentKey);
  }

  Future<bool> hasReadyContent({required String contentKey}) async {
    final row =
        await customSelect(
          '''
          SELECT 1
          FROM reader_chapter_contents
          WHERE contentKey = ?
            AND status = ?
            AND content IS NOT NULL
            AND content != ''
          LIMIT 1
          ''',
          variables: [
            Variable.withString(contentKey),
            Variable.withInt(ReaderChapterContentStatus.ready.code),
          ],
          readsFrom: {readerChapterContents},
        ).getSingleOrNull();
    return row != null;
  }

  Future<Set<int>> getStoredChapterIndices({
    required String origin,
    required String bookUrl,
  }) async {
    final rows =
        await customSelect(
          '''
          SELECT chapterIndex
          FROM reader_chapter_contents
          WHERE origin = ?
            AND bookUrl = ?
            AND status = ?
            AND content IS NOT NULL
            AND content != ''
          ORDER BY chapterIndex
          ''',
          variables: [
            Variable.withString(origin),
            Variable.withString(bookUrl),
            Variable.withInt(ReaderChapterContentStatus.ready.code),
          ],
          readsFrom: {readerChapterContents},
        ).get();
    return rows.map((row) => row.read<int>('chapterIndex')).toSet();
  }

  Future<void> saveContent({
    required String contentKey,
    required String origin,
    required String bookUrl,
    required String chapterUrl,
    required int chapterIndex,
    required String content,
    required int updatedAt,
    ReaderChapterContentStatus status = ReaderChapterContentStatus.ready,
    String? failureMessage,
  }) {
    return into(readerChapterContents).insertOnConflictUpdate(
      ReaderChapterContentsCompanion.insert(
        contentKey: contentKey,
        origin: origin,
        bookUrl: bookUrl,
        chapterUrl: chapterUrl,
        chapterIndex: chapterIndex,
        content: Value(content),
        status: Value(status.code),
        failureMessage: Value(failureMessage),
        updatedAt: updatedAt,
      ),
    );
  }

  Future<void> saveFailure({
    required String contentKey,
    required String origin,
    required String bookUrl,
    required String chapterUrl,
    required int chapterIndex,
    required String message,
    required int updatedAt,
  }) {
    return saveContent(
      contentKey: contentKey,
      origin: origin,
      bookUrl: bookUrl,
      chapterUrl: chapterUrl,
      chapterIndex: chapterIndex,
      content: message,
      updatedAt: updatedAt,
      status: ReaderChapterContentStatus.failed,
      failureMessage: message,
    );
  }

  Future<void> deleteContent({required String contentKey}) {
    return (delete(readerChapterContents)
      ..where((t) => t.contentKey.equals(contentKey))).go();
  }

  Future<void> deleteByBook(String origin, String bookUrl) {
    return (delete(readerChapterContents)
      ..where((t) => t.origin.equals(origin) & t.bookUrl.equals(bookUrl))).go();
  }

  Future<void> clearAllContent() {
    return delete(readerChapterContents).go();
  }

  Future<int> getTotalContentSize() async {
    final rows =
        await customSelect(
          'SELECT COALESCE(SUM(LENGTH(content)), 0) AS total FROM reader_chapter_contents WHERE status = 1 AND content IS NOT NULL AND content != ""',
          readsFrom: {readerChapterContents},
        ).get();
    if (rows.isEmpty) return 0;
    return rows.first.read<int>('total');
  }
}
