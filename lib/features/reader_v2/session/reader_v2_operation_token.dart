import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';

import 'reader_v2_location.dart';

enum ReaderV2OperationKind { open, jump, restore, presentation, contentReload }

class ReaderV2OperationToken {
  const ReaderV2OperationToken({
    required this.id,
    required this.kind,
    required this.layoutGeneration,
    required this.targetLocation,
    this.layoutSpec,
  });

  final int id;
  final ReaderV2OperationKind kind;

  /// Layout generation this operation intends to materialize.
  ///
  /// A superseding operation inherits an uncommitted generation so normal
  /// cancellation cannot silently drop a pending presentation/content change.
  final int layoutGeneration;
  final ReaderV2LayoutSpec? layoutSpec;

  /// Semantic intent, independent of the last painted or persisted location.
  final ReaderV2Location targetLocation;
}
