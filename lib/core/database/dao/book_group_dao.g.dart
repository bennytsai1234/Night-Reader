// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book_group_dao.dart';

// ignore_for_file: type=lint
mixin _$BookGroupDaoMixin on DatabaseAccessor<AppDatabase> {
  $BookGroupsTable get bookGroups => attachedDatabase.bookGroups;
  BookGroupDaoManager get managers => BookGroupDaoManager(this);
}

class BookGroupDaoManager {
  final _$BookGroupDaoMixin _db;
  BookGroupDaoManager(this._db);
  $$BookGroupsTableTableManager get bookGroups =>
      $$BookGroupsTableTableManager(_db.attachedDatabase, _db.bookGroups);
}
