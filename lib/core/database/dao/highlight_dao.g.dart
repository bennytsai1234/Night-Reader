// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'highlight_dao.dart';

// ignore_for_file: type=lint
mixin _$HighlightDaoMixin on DatabaseAccessor<AppDatabase> {
  $HighlightsTable get highlights => attachedDatabase.highlights;
  HighlightDaoManager get managers => HighlightDaoManager(this);
}

class HighlightDaoManager {
  final _$HighlightDaoMixin _db;
  HighlightDaoManager(this._db);
  $$HighlightsTableTableManager get highlights =>
      $$HighlightsTableTableManager(_db.attachedDatabase, _db.highlights);
}
