// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book_source_dao.dart';

// ignore_for_file: type=lint
mixin _$BookSourceDaoMixin on DatabaseAccessor<AppDatabase> {
  $BookSourcesTable get bookSources => attachedDatabase.bookSources;
  BookSourceDaoManager get managers => BookSourceDaoManager(this);
}

class BookSourceDaoManager {
  final _$BookSourceDaoMixin _db;
  BookSourceDaoManager(this._db);
  $$BookSourcesTableTableManager get bookSources =>
      $$BookSourcesTableTableManager(_db.attachedDatabase, _db.bookSources);
}
