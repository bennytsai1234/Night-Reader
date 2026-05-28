// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_dao.dart';

// ignore_for_file: type=lint
mixin _$DownloadDaoMixin on DatabaseAccessor<AppDatabase> {
  $DownloadTasksTable get downloadTasks => attachedDatabase.downloadTasks;
  DownloadDaoManager get managers => DownloadDaoManager(this);
}

class DownloadDaoManager {
  final _$DownloadDaoMixin _db;
  DownloadDaoManager(this._db);
  $$DownloadTasksTableTableManager get downloadTasks =>
      $$DownloadTasksTableTableManager(_db.attachedDatabase, _db.downloadTasks);
}
