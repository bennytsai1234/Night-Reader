enum ReaderV2OperationKind { open, jump, restore, presentation, contentReload }

class ReaderV2OperationToken {
  const ReaderV2OperationToken({
    required this.id,
    required this.kind,
    required this.layoutGeneration,
  });

  final int id;
  final ReaderV2OperationKind kind;
  final int layoutGeneration;
}
