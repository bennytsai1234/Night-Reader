// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_book_dao.dart';

// ignore_for_file: type=lint
mixin _$SearchBookDaoMixin on DatabaseAccessor<AppDatabase> {
  $SearchBooksTable get searchBooks => attachedDatabase.searchBooks;
  $BookSourcesTable get bookSources => attachedDatabase.bookSources;
  SearchBookDaoManager get managers => SearchBookDaoManager(this);
}

class SearchBookDaoManager {
  final _$SearchBookDaoMixin _db;
  SearchBookDaoManager(this._db);
  $$SearchBooksTableTableManager get searchBooks =>
      $$SearchBooksTableTableManager(_db.attachedDatabase, _db.searchBooks);
  $$BookSourcesTableTableManager get bookSources =>
      $$BookSourcesTableTableManager(_db.attachedDatabase, _db.bookSources);
}
