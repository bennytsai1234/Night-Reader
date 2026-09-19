import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/models/book.dart';

/// A cross-owner operation that must become quiescent before a source switch
/// can publish a new reader world.
///
/// The lease owns only its subsystem. [retireInTransaction] persists the
/// retirement inside the source-switch database transaction; [committed] and
/// [rolledBack] finalize the in-memory lifecycle after the transaction outcome.
abstract interface class SourceSwitchOperationLease {
  Future<void> retireInTransaction(AppDatabase db);
  void committed();
  void rolledBack();
}

typedef SourceSwitchOperationQuiescer =
    Future<SourceSwitchOperationLease> Function(Book oldBook);

typedef SourceSwitchAssetRetirer =
    Future<void> Function(Book oldBook, Book migratedBook);
