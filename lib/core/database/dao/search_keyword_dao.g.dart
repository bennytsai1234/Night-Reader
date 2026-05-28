// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_keyword_dao.dart';

// ignore_for_file: type=lint
mixin _$SearchKeywordDaoMixin on DatabaseAccessor<AppDatabase> {
  $SearchKeywordsTable get searchKeywords => attachedDatabase.searchKeywords;
  SearchKeywordDaoManager get managers => SearchKeywordDaoManager(this);
}

class SearchKeywordDaoManager {
  final _$SearchKeywordDaoMixin _db;
  SearchKeywordDaoManager(this._db);
  $$SearchKeywordsTableTableManager get searchKeywords =>
      $$SearchKeywordsTableTableManager(
        _db.attachedDatabase,
        _db.searchKeywords,
      );
}
