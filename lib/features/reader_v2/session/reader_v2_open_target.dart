import 'dart:convert';

import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/bookmark.dart';

import 'reader_v2_location.dart';

enum ReaderV2OpenIntent { resume, chapterStart, bookmark }

class ReaderV2OpenTarget {
  const ReaderV2OpenTarget({required this.location, required this.intent});

  final ReaderV2Location location;
  final ReaderV2OpenIntent intent;

  factory ReaderV2OpenTarget.resume(Book book) {
    ReaderV2Location? persistedAnchor;
    final encoded = book.readerAnchorJson;
    if (encoded != null && encoded.isNotEmpty) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is Map) {
          persistedAnchor = ReaderV2Location.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        }
      } catch (_) {
        // Legacy/corrupt anchor JSON must never make the book unopenable. The
        // scalar progress columns remain the backwards-compatible fallback.
      }
    }
    final scalar = ReaderV2Location(
      chapterIndex: book.chapterIndex,
      charOffset: book.charOffset,
      visualOffsetPx: book.visualOffsetPx,
    ).normalized();
    final anchor = persistedAnchor;
    return ReaderV2OpenTarget(
      intent: ReaderV2OpenIntent.resume,
      // The DB writes scalar progress and readerAnchorJson atomically. If an
      // older/imported row disagrees, the scalar coordinates are the chapter
      // ownership truth; stale anchor metadata must not redirect another
      // chapter.
      location:
          anchor != null &&
              anchor.chapterIndex == scalar.chapterIndex &&
              anchor.charOffset == scalar.charOffset
          ? anchor.copyWith(visualOffsetPx: scalar.visualOffsetPx)
          : scalar,
    );
  }

  factory ReaderV2OpenTarget.chapterStart(int chapterIndex) {
    return ReaderV2OpenTarget(
      intent: ReaderV2OpenIntent.chapterStart,
      location:
          ReaderV2Location(
            chapterIndex: chapterIndex,
            charOffset: 0,
          ).normalized(),
    );
  }

  factory ReaderV2OpenTarget.bookmark(Bookmark bookmark) {
    return ReaderV2OpenTarget(
      intent: ReaderV2OpenIntent.bookmark,
      location:
          ReaderV2Location(
            chapterIndex: bookmark.chapterIndex,
            charOffset: bookmark.chapterPos,
          ).normalized(),
    );
  }

  factory ReaderV2OpenTarget.location(
    ReaderV2Location location, {
    ReaderV2OpenIntent intent = ReaderV2OpenIntent.chapterStart,
  }) {
    return ReaderV2OpenTarget(intent: intent, location: location.normalized());
  }
}
