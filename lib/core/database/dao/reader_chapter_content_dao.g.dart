// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reader_chapter_content_dao.dart';

// ignore_for_file: type=lint
mixin _$ReaderChapterContentDaoMixin on DatabaseAccessor<AppDatabase> {
  $ReaderChapterContentsTable get readerChapterContents =>
      attachedDatabase.readerChapterContents;
  ReaderChapterContentDaoManager get managers =>
      ReaderChapterContentDaoManager(this);
}

class ReaderChapterContentDaoManager {
  final _$ReaderChapterContentDaoMixin _db;
  ReaderChapterContentDaoManager(this._db);
  $$ReaderChapterContentsTableTableManager get readerChapterContents =>
      $$ReaderChapterContentsTableTableManager(
        _db.attachedDatabase,
        _db.readerChapterContents,
      );
}
