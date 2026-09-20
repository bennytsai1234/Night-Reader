import 'package:night_reader/core/models/book.dart';

/// Canonical reading-history semantics for a book.
///
/// A book is considered started only after Reader has persisted real reading
/// progress. Shelf membership and an initialized chapter index are not reading
/// activity.
extension BookReadingState on Book {
  bool get hasStartedReading => durChapterTime > 0;
}
