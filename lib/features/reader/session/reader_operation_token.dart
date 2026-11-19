import 'reader_location.dart';

enum ReaderOperationKind { open, jump, restore, presentation, contentReload }

class ReaderOperationToken {
  const ReaderOperationToken({
    required this.id,
    required this.kind,
    required this.layoutGeneration,
    required this.targetLocation,
  });

  final int id;
  final ReaderOperationKind kind;

  /// Layout generation this operation intends to materialize.
  ///
  /// A superseding operation inherits an uncommitted generation so normal
  /// cancellation cannot silently drop a pending presentation change.
  final int layoutGeneration;

  /// Semantic intent, independent of the last painted or persisted location.
  final ReaderLocation targetLocation;
}
