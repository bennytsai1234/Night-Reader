// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book_dao.dart';

// ignore_for_file: type=lint
mixin _$BookDaoMixin on DatabaseAccessor<AppDatabase> {
  $BooksTable get books => attachedDatabase.books;
  BookDaoManager get managers => BookDaoManager(this);
}

class BookDaoManager {
  final _$BookDaoMixin _db;
  BookDaoManager(this._db);
  $$BooksTableTableManager get books =>
      $$BooksTableTableManager(_db.attachedDatabase, _db.books);
}
