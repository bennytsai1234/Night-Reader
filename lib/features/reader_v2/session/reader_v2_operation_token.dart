import 'reader_v2_location.dart';

enum ReaderV2OperationKind { open, jump, restore, presentation, contentReload }

class ReaderV2OperationToken {
  const ReaderV2OperationToken({
    required this.id,
    required this.kind,
    required this.layoutGeneration,
    required this.targetLocation,
  });

  final int id;
  final ReaderV2OperationKind kind;

  /// Layout generation this operation intends to materialize.
  ///
  /// A superseding operation inherits an uncommitted generation so normal
  /// cancellation cannot silently drop a pending presentation change.
  final int layoutGeneration;

  /// Semantic intent, independent of the last painted or persisted location.
  final ReaderV2Location targetLocation;
}
