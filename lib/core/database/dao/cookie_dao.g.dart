// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cookie_dao.dart';

// ignore_for_file: type=lint
mixin _$CookieDaoMixin on DatabaseAccessor<AppDatabase> {
  $CookiesTable get cookies => attachedDatabase.cookies;
  CookieDaoManager get managers => CookieDaoManager(this);
}

class CookieDaoManager {
  final _$CookieDaoMixin _db;
  CookieDaoManager(this._db);
  $$CookiesTableTableManager get cookies =>
      $$CookiesTableTableManager(_db.attachedDatabase, _db.cookies);
}
