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
  final int layoutGeneration;

  /// Semantic intent, independent of the last painted or persisted location.
  final ReaderV2Location targetLocation;
}
