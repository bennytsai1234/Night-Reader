// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'source_subscription_dao.dart';

// ignore_for_file: type=lint
mixin _$SourceSubscriptionDaoMixin on DatabaseAccessor<AppDatabase> {
  $SourceSubscriptionsTable get sourceSubscriptions =>
      attachedDatabase.sourceSubscriptions;
  SourceSubscriptionDaoManager get managers =>
      SourceSubscriptionDaoManager(this);
}

class SourceSubscriptionDaoManager {
  final _$SourceSubscriptionDaoMixin _db;
  SourceSubscriptionDaoManager(this._db);
  $$SourceSubscriptionsTableTableManager get sourceSubscriptions =>
      $$SourceSubscriptionsTableTableManager(
        _db.attachedDatabase,
        _db.sourceSubscriptions,
      );
}
