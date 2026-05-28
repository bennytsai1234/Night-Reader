import 'package:drift/drift.dart';
import '../../models/source_subscription.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'source_subscription_dao.g.dart';

@DriftAccessor(tables: [SourceSubscriptions])
class SourceSubscriptionDao extends DatabaseAccessor<AppDatabase>
    with _$SourceSubscriptionDaoMixin {
  SourceSubscriptionDao(super.db);

  Future<List<SourceSubscription>> getAll() {
    return (select(sourceSubscriptions)
      ..orderBy([(t) => OrderingTerm(expression: t.order)])).get();
  }

  Stream<List<SourceSubscription>> watchAll() {
    return (select(sourceSubscriptions)
      ..orderBy([(t) => OrderingTerm(expression: t.order)])).watch();
  }

  Future<void> upsert(SourceSubscription sub) => into(
    sourceSubscriptions,
  ).insertOnConflictUpdate(SourceSubscriptionToInsertable(sub).toInsertable());

  Future<void> deleteByUrl(String url) =>
      (delete(sourceSubscriptions)..where((t) => t.url.equals(url))).go();
}
